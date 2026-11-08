import AppKit

// The tiny app that sits in the Dock for each folder.
//
// Usually it isn't running: Dock Folders intercepts clicks on its tile. It runs when
//  • an app inside the folder is running (--indicator): it stays up as a normal app so the Dock
//    draws its real running dot under the folder, and quits when the last one quits;
//  • an app is dropped onto the folder's Dock tile (we forward it to be added);
//  • Dock Folders isn't running (we start it and ask it to open this folder).

final class StubDelegate: NSObject, NSApplicationDelegate {
    private var droppedFiles: [URL] = []
    private var isIndicator = false
    private var folderID: String { Bundle.main.object(forInfoDictionaryKey: DFShared.folderIDInfoKey) as? String ?? "" }
    private var tileKey: String { Bundle.main.object(forInfoDictionaryKey: DFShared.tileKeyInfoKey) as? String ?? folderID }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock Folders launches each new stub once with --register: that first launch is what
        // lets macOS trust it, after which the Dock loads its live tile plug-in.
        if CommandLine.arguments.contains("--register") {
            NSApp.terminate(nil)
            return
        }
        // Never brought back by "Reopen windows when logging back in".
        NSApp.disableRelaunchOnLogin()

        if CommandLine.arguments.contains("--indicator") {
            becomeIndicator()
            return
        }
        scheduleForward()
        // Never linger, whatever happens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.isIndicator == false { NSApp.terminate(nil) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        droppedFiles.append(contentsOf: urls)
        scheduleForward()
    }

    /// Clicked in the Dock while Dock Folders wasn't watching, or Return in Dock keyboard mode.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        scheduleForward()
        return false
    }

    /// Picked in ⌘-Tab: open the folder, and hand focus straight back.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard isIndicator else { return }
        send(host: "open", extra: [URLQueryItem(name: "source", value: "switcher")], thenQuit: false)
        NSApp.hide(nil)
    }

    // MARK: Running indicator

    private func becomeIndicator() {
        isIndicator = true
        // A regular app gets the Dock's own running dot under its tile (and a ⌘-Tab entry).
        NSApp.setActivationPolicy(.regular)
        showTile()
        DistributedNotificationCenter.default().addObserver(
            forName: DFShared.tileChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let target = note.object as? String
            if target == nil || target == "*" || target == self.tileKey { self.showTile() }
        }
    }

    /// While running, the Dock shows the app's own tile, so mirror the folder's 2×2 icon.
    private func showTile() {
        guard let image = NSImage(contentsOf: DFShared.tileImageURL(for: tileKey)) else { return }
        NSApp.applicationIconImage = image
        let tile = NSApp.dockTile
        let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = image
        tile.contentView = view
        tile.display()
    }

    // MARK: Forwarding to Dock Folders

    private func scheduleForward() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(forward), object: nil)
        perform(#selector(forward), with: nil, afterDelay: 0.15)
    }

    @objc private func forward() {
        let files = droppedFiles
        droppedFiles.removeAll()
        send(host: files.isEmpty ? "open" : "add",
             extra: files.map { URLQueryItem(name: "path", value: $0.path) },
             thenQuit: !isIndicator)
    }

    private func send(host: String, extra: [URLQueryItem], thenQuit: Bool) {
        var components = URLComponents()
        components.scheme = DFShared.urlScheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "id", value: folderID)] + extra

        guard let url = components.url,
              let agent = NSWorkspace.shared.urlForApplication(withBundleIdentifier: DFShared.agentBundleID) else {
            if thenQuit { NSApp.terminate(nil) }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: agent, configuration: config) { _, _ in
            if thenQuit { DispatchQueue.main.async { NSApp.terminate(nil) } }
        }
    }
}

let app = NSApplication.shared
let delegate = StubDelegate()
app.delegate = delegate
app.run()
