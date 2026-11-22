import AppKit
import Foundation

@main
private enum AppIconResolverSelfCheck {
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
        let bundleIdentifier = "com.mylesdean.DockFolders.AppIconResolverSelfCheck.\(UUID().uuidString)"
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("AppIconResolverSelfCheck-\(UUID().uuidString)", isDirectory: true)
        let applicationURL = temporaryRoot.appendingPathComponent("Custom Icon.app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let customIconURL = resourcesURL.appendingPathComponent("custom-icon.png")
        let traversalIconURL = contentsURL.appendingPathComponent("traversal-icon.png")
        let defaults = UserDefaults(suiteName: bundleIdentifier)!

        defer {
            defaults.removePersistentDomain(forName: bundleIdentifier)
            defaults.synchronize()
            try? fileManager.removeItem(at: temporaryRoot)
        }

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": "Custom Icon Check",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "CustomIconCheck"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let iconData = try makePNG(width: 13, height: 17)
        try iconData.write(to: customIconURL)
        try iconData.write(to: traversalIconURL)

        defaults.set("custom", forKey: "DockIconPreference")
        defaults.set("custom-icon.png", forKey: "DockIconResourceName")
        defaults.synchronize()

        let expectedIcon = try unwrap(NSImage(contentsOf: customIconURL), "The custom test icon should load")
        let customIcon = AppIconResolver.icon(for: applicationURL)
        expect(
            customIcon.tiffRepresentation == expectedIcon.tiffRepresentation,
            "A valid DockIconResourceName should load from Contents/Resources"
        )

        defaults.set("../traversal-icon.png", forKey: "DockIconResourceName")
        defaults.synchronize()
        let traversalResult = AppIconResolver.icon(for: applicationURL)
        expect(
            traversalResult.tiffRepresentation != expectedIcon.tiffRepresentation,
            "A resource name containing path traversal should be rejected"
        )

        print("App icon resolver self-check passed for \(checks) cases.")
    }

    private static func makePNG(width: Int, height: Int) throws -> Data {
        let bitmap = try unwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            "The test bitmap should be created"
        )

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        return try unwrap(bitmap.representation(using: .png, properties: [:]), "The test PNG should be encoded")
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw NSError(
                domain: "AppIconResolverSelfCheck",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return value
    }
}
