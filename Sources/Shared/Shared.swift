import Foundation

/// Constants shared by the agent, the per-folder stub apps and the Dock tile plug-in.
enum DFShared {
    static let agentBundleID = "com.mylesdean.DockFolders"
    static let stubBundleIDPrefix = "com.mylesdean.DockFolders.folder."
    static let urlScheme = "dockfolders"
    static let folderIDInfoKey = "DFFolderID"
    /// Which tile image a stub's plug-in shows (see Folder.tileKey); folder stubs made before
    /// slots don't have it and use their folder id.
    static let tileKeyInfoKey = "DFTileKey"

    /// Posted (distributed) by the agent whenever a folder's tile image changes.
    /// `object` is the folder's tile key, or "*" for every folder.
    static let tileChangedNotification = Notification.Name("com.mylesdean.DockFolders.tileChanged")

    /// The real home folder, even when running inside an XPC service.
    static var homeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var supportDirectory: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Dock Folders", isDirectory: true)
    }

    static var tilesDirectory: URL { supportDirectory.appendingPathComponent("Tiles", isDirectory: true) }
    static var stubsDirectory: URL { supportDirectory.appendingPathComponent("Folders", isDirectory: true) }
    static var storeURL: URL { supportDirectory.appendingPathComponent("folders.json") }

    static func tileImageURL(for tileKey: String) -> URL {
        tilesDirectory.appendingPathComponent("\(tileKey).png")
    }
}
