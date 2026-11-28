import Darwin
import Foundation

/// Watches app bundle directories and reconciles stored folders after app bundles leave or return.
final class AppBundleMonitor {
    private struct WatchedDirectory {
        let id: UUID
        let source: DispatchSourceFileSystemObject
    }

    private static let reconcileDelay: TimeInterval = 0.4
    private static let eventMask: DispatchSource.FileSystemEvent = [
        .write, .delete, .rename, .extend, .attrib, .link
    ]

    private var isStarted = false
    private var storeObserver: NSObjectProtocol?
    private var watchedDirectories: [String: WatchedDirectory] = [:]
    private var reconcileWorkItem: DispatchWorkItem?
    private var reconcileGeneration = 0
    private var isReconciling = false

    /// Starts once and performs an initial reconciliation of missing app paths.
    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }
        guard !isStarted else { return }
        isStarted = true

        storeObserver = NotificationCenter.default.addObserver(
            forName: FolderStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.folderStoreDidChange()
        }

        rebuildWatchers()
        scheduleReconcile()
    }

    /// Stops all directory sources and discards pending reconciliation work.
    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        guard isStarted else { return }
        isStarted = false

        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        reconcileGeneration += 1
        reconcileWorkItem?.cancel()
        reconcileWorkItem = nil

        let sources = watchedDirectories.values.map(\.source)
        watchedDirectories.removeAll()
        sources.forEach { $0.cancel() }
    }

    private func folderStoreDidChange() {
        guard isStarted else { return }
        rebuildWatchers()
        if !isReconciling {
            scheduleReconcile()
        }
    }

    private func rebuildWatchers() {
        guard isStarted else { return }
        let appPaths = FolderStore.shared.folders.flatMap(\.apps)
        let desired = AppBundleWatchDirectories.normalizedDirectories(forAppPaths: appPaths)
        let desiredPaths = Set(desired.map(\.path))

        let staleWatchers = watchedDirectories
            .filter { !desiredPaths.contains($0.key) }
            .map { ($0.key, $0.value.id) }
        for (path, id) in staleWatchers {
            removeWatcher(path: path, id: id)
        }

        for directory in desired where watchedDirectories[directory.path] == nil {
            addWatcher(for: directory)
        }
    }

    private func addWatcher(for directory: URL) {
        let descriptor = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_EVTONLY)
        }
        guard descriptor >= 0 else { return }

        let directoryPath = directory.path
        let watcherID = UUID()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: Self.eventMask,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.directoryDidChange(path: directoryPath, id: watcherID)
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        watchedDirectories[directoryPath] = WatchedDirectory(id: watcherID, source: source)
        source.resume()
    }

    private func directoryDidChange(path: String, id: UUID) {
        guard isStarted, let watcher = watchedDirectories[path], watcher.id == id else { return }
        let events = watcher.source.data
        if events.contains(.delete) || events.contains(.rename) {
            removeWatcher(path: path, id: id)
        }
        scheduleReconcile()
    }

    private func removeWatcher(path: String, id: UUID) {
        guard let watcher = watchedDirectories[path], watcher.id == id else { return }
        watchedDirectories.removeValue(forKey: path)
        watcher.source.cancel()
    }

    private func scheduleReconcile() {
        guard isStarted else { return }
        reconcileGeneration += 1
        let generation = reconcileGeneration
        reconcileWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted, self.reconcileGeneration == generation else { return }
            self.reconcileWorkItem = nil
            self.reconcileNow()
        }
        reconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconcileDelay, execute: workItem)
    }

    @discardableResult
    private func reconcileNow() -> Bool {
        guard isStarted, Thread.isMainThread else { return false }
        isReconciling = true
        defer { isReconciling = false }

        rebuildWatchers()
        let changed = FolderActions.removeMissingApps()
        FolderPanelController.shared.reload()
        if !changed {
            StubManager.refreshAllTiles()
        }
        if changed {
            rebuildWatchers()
        }
        return changed
    }
}
