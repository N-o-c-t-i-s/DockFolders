import AppKit

/// Resolves the icon an application currently wants to show, including icons selected at runtime
/// by the application's own Dock icon preferences.
enum AppIconResolver {
    private static let dockIconPreferenceKey = "DockIconPreference"
    private static let dockIconResourceNameKey = "DockIconResourceName"

    static func icon(for applicationURL: URL) -> NSImage {
        let applicationURL = applicationURL.standardizedFileURL

        if let bundle = Bundle(url: applicationURL),
           let bundleIdentifier = bundle.bundleIdentifier,
           !bundleIdentifier.isEmpty,
           let defaults = UserDefaults(suiteName: bundleIdentifier) {
            // DockIconPreference identifies that the app has a configurable Dock icon feature.
            _ = defaults.string(forKey: dockIconPreferenceKey)

            if let resourceName = defaults.string(forKey: dockIconResourceNameKey),
               let resourceURL = safeResourceURL(named: resourceName, in: bundle),
               let image = NSImage(contentsOf: resourceURL) {
                return image
            }

            let runningApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            if let runningIcon = (runningApplications.first {
                $0.bundleURL?.standardizedFileURL == applicationURL
            } ?? runningApplications.first(where: { !$0.isTerminated }))?.icon {
                return runningIcon
            }
        }

        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    private static func safeResourceURL(named relativePath: String, in bundle: Bundle) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        let resourcesURL = bundle.bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .standardizedFileURL
        let resolvedResourcesURL = resourcesURL.resolvingSymlinksInPath().standardizedFileURL
        let candidateURL = resourcesURL
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = resolvedResourcesURL.path.hasSuffix("/")
            ? resolvedResourcesURL.path
            : resolvedResourcesURL.path + "/"

        guard candidateURL.path.hasPrefix(rootPath) else { return nil }
        return candidateURL
    }
}
