import AppKit
import SwiftUI

/// Draws a folder's Dock icon: a translucent glass squircle holding its first four apps (2×2),
/// laid out on the standard macOS icon grid so it sits naturally next to other Dock icons.
enum TileRenderer {
    /// The macOS 26 app icon shape: an 824/1024 square with continuous ("squircle") corners whose
    /// radius is 26% of its side. Measured from the system's own icons (Notes, Music, Calendar),
    /// which it matches to within a pixel; Big Sur–era templates used 22.5%.
    static let iconCornerRatio: CGFloat = 0.26

    static func render(apps: [URL], pixelSize: Int = 512, dark: Bool) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let s = CGFloat(pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let cg = context.cgContext

        // Icon grid: an 824/1024 squircle centred in the canvas.
        let side = s * 824 / 1024
        let body = CGRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
        let squircle = Path(roundedRect: body, cornerRadius: side * iconCornerRatio, style: .continuous).cgPath

        // Soft drop shadow, like other Dock icons.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                     color: NSColor.black.withAlphaComponent(dark ? 0.35 : 0.18).cgColor)
        cg.addPath(squircle)
        cg.setFillColor(NSColor.white.withAlphaComponent(dark ? 0.16 : 0.45).cgColor)
        cg.fillPath()
        cg.restoreGState()

        // Glassy sheen: a gentle top-to-bottom gradient inside the squircle.
        cg.saveGState()
        cg.addPath(squircle)
        cg.clip()
        let top = NSColor.white.withAlphaComponent(dark ? 0.14 : 0.30).cgColor
        let bottom = NSColor.white.withAlphaComponent(0.0).cgColor
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
        }
        cg.restoreGState()

        // Hairline rim.
        cg.saveGState()
        cg.addPath(squircle)
        cg.setStrokeColor(NSColor.white.withAlphaComponent(dark ? 0.28 : 0.65).cgColor)
        cg.setLineWidth(max(1, s / 256))
        cg.strokePath()
        cg.restoreGState()

        // 2×2 mini icons.
        let padding = side * 0.13
        let gap = side * 0.075
        let slot = (side - padding * 2 - gap) / 2
        for (index, url) in apps.prefix(4).enumerated() {
            let column = CGFloat(index % 2)
            let row = CGFloat(index / 2)
            let rect = CGRect(
                x: body.minX + padding + column * (slot + gap),
                y: body.maxY - padding - slot - row * (slot + gap),
                width: slot, height: slot
            )
            // App icons include the standard transparent margin; enlarge so the artwork fills the slot.
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.draw(in: rect.insetBy(dx: -slot * 0.1215, dy: -slot * 0.1215), from: .zero, operation: .sourceOver, fraction: 1)
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func pngData(apps: [URL], pixelSize: Int = 512, dark: Bool) -> Data? {
        render(apps: apps, pixelSize: pixelSize, dark: dark)?.representation(using: .png, properties: [:])
    }

    /// The Dock Folders app icon: a dark glass squircle with four coloured mini tiles.
    static func renderAppIcon(pixelSize: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let s = CGFloat(pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        let side = s * 824 / 1024
        let body = CGRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
        let squircle = Path(roundedRect: body, cornerRadius: side * iconCornerRatio, style: .continuous).cgPath

        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        cg.addPath(squircle)
        cg.setFillColor(NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1).cgColor)
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(squircle)
        cg.clip()
        let colors = [NSColor(white: 1, alpha: 0.18).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
        }
        cg.restoreGState()

        let tints: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink]
        let padding = side * 0.17, gap = side * 0.08
        let slot = (side - padding * 2 - gap) / 2
        for (index, tint) in tints.enumerated() {
            let rect = CGRect(x: body.minX + padding + CGFloat(index % 2) * (slot + gap),
                              y: body.maxY - padding - slot - CGFloat(index / 2) * (slot + gap),
                              width: slot, height: slot)
            cg.addPath(Path(roundedRect: rect, cornerRadius: slot * 0.24, style: .continuous).cgPath)
            cg.setFillColor(tint.cgColor)
            cg.fillPath()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func writeAppIcon(to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, 5, nil) else { return }
        for size in [16, 32, 128, 256, 512] {
            if let image = renderAppIcon(pixelSize: size)?.cgImage { CGImageDestinationAddImage(destination, image, nil) }
        }
        CGImageDestinationFinalize(destination)
    }

    /// Writes an .icns (used by Finder, and by the Dock before the plug-in has drawn).
    static func writeICNS(apps: [URL], dark: Bool, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, 5, nil) else { return }
        for size in [16, 32, 128, 256, 512] {
            if let image = render(apps: apps, pixelSize: size, dark: dark)?.cgImage {
                CGImageDestinationAddImage(destination, image, nil)
            }
        }
        CGImageDestinationFinalize(destination)
    }
}
