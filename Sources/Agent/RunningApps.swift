import AppKit

/// Tells Dock Folders when apps launch or quit, for the running dots.
///
/// NSWorkspace's launch/terminate notifications aren't enough: some apps (Clock, for one) never
/// post "did terminate" when they quit. macOS's list of running apps always changes, so watch that.
final class RunningApps {
    static let shared = RunningApps()
    static let didChange = Notification.Name("DockFoldersRunningAppsDidChange")

    private var token: NSKeyValueObservation?
    private var postPending = false

    func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.observe(\.runningApplications, options: []) { [weak self] _, _ in
            DispatchQueue.main.async { self?.post() }
        }
    }

    /// One notice per burst of changes.
    private func post() {
        guard !postPending else { return }
        postPending = true
        DispatchQueue.main.async { [weak self] in
            self?.postPending = false
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}
