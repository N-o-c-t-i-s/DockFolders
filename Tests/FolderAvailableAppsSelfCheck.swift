import AppKit
import Foundation

@main
private enum FolderAvailableAppsSelfCheck {
    static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            checks += 1
        }

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("FolderAvailableAppsSelfCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let firstApp = temporaryRoot.appendingPathComponent("First.app", isDirectory: true)
        let secondApp = temporaryRoot.appendingPathComponent("Second.app", isDirectory: true)
        let missingFirst = temporaryRoot.appendingPathComponent("Missing First.app", isDirectory: true)
        let missingSecond = temporaryRoot.appendingPathComponent("Missing Second.app", isDirectory: true)
        try fileManager.createDirectory(at: firstApp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondApp, withIntermediateDirectories: true)

        let mixedFolder = Folder(
            id: "mixed",
            name: "Mixed",
            apps: [missingFirst.path, firstApp.path, missingSecond.path, secondApp.path],
            stubName: "Mixed.app"
        )
        expect(
            mixedFolder.availableAppURLs.map(\.path) == [firstApp.path, secondApp.path],
            "available apps preserve order and remove missing paths"
        )

        let emptyFolder = Folder(id: "empty", name: "Empty", apps: [], stubName: "Empty.app")
        expect(emptyFolder.availableAppURLs.isEmpty, "an empty folder has no available apps")

        let allMissingFolder = Folder(
            id: "missing",
            name: "Missing",
            apps: [missingFirst.path, missingSecond.path],
            stubName: "Missing.app"
        )
        expect(allMissingFolder.availableAppURLs.isEmpty, "an all-missing folder has no available apps")

        let normalized = AppBundleWatchDirectories.normalizedDirectories(forAppPaths: [
            "/DockFoldersWatchChecks/Applications/Zeta.app",
            "/DockFoldersWatchChecks/Applications/Alpha.app",
            "/DockFoldersWatchChecks/Applications/../Applications/Beta.app",
            "/DockFoldersWatchChecks/Elsewhere/./One.app",
            "/DockFoldersWatchChecks/Elsewhere/Two.app"
        ])
        expect(
            normalized.map(\.path) == [
                "/DockFoldersWatchChecks/Applications",
                "/DockFoldersWatchChecks/Elsewhere"
            ],
            "watch directories are normalized and unique"
        )
        expect(
            AppBundleWatchDirectories.normalizedDirectories(forAppPaths: [
                "/DockFoldersWatchChecks/Elsewhere/Two.app",
                "/DockFoldersWatchChecks/Applications/Alpha.app",
                "/DockFoldersWatchChecks/Applications/Zeta.app"
            ]).map(\.path) == normalized.map(\.path),
            "watch directory order is deterministic"
        )
        expect(
            AppBundleWatchDirectories.normalizedDirectories(forAppPaths: []).isEmpty,
            "no app paths produce no watch directories"
        )

        print("Folder available apps self-check passed for \(checks) cases.")
    }
}
