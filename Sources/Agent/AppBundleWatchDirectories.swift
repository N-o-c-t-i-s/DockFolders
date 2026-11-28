import Foundation

/// Normalizes the parent directories that must be watched for app bundle changes.
enum AppBundleWatchDirectories {
    static func normalizedDirectories(forAppPaths paths: [String]) -> [URL] {
        let directories = paths.map { path in
            URL(fileURLWithPath: path)
                .standardizedFileURL
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
        }
        return Array(Set(directories)).sorted { $0.path < $1.path }
    }
}
