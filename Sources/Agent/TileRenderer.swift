import AppKit
import SwiftUI

/// Draws a folder's Dock icon: a translucent glass squircle holding a miniature app grid,
/// laid out on the standard macOS icon grid so it sits naturally next to other Dock icons.
enum TileRenderer {
    /// The macOS 26 app icon shape: an 824/1024 square with continuous ("squircle") corners whose
    /// radius is 26% of its side. Measured from the system's own icons (Notes, Music, Calendar),
    /// which it matches to within a pixel; Big Sur–era templates used 22.5%.
    static let iconCornerRatio: CGFloat = 0.26

    static func render(
        apps: [URL],
        pixelSize: Int = 512,
        dark: Bool,
        displayMode: DockIconDisplayMode,
        preferredColumns: Int,
        preferredRows: Int
    ) -> NSBitmapImageRep? {
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

        let layout = DockIconGridLayout.make(
            appCount: apps.count,
            preferredColumns: preferredColumns,
            preferredRows: preferredRows,
            displayMode: displayMode,
            in: body
        )
        for (index, rect) in layout.slots.enumerated() {
            if layout.isOverflowSlot(index) {
                drawOverflowBadge(layout.overflowLabel ?? "", in: rect, dark: dark)
                continue
            }
            guard index < layout.displayedAppCount, index < apps.count else { continue }
            let url = apps[index]
            // App icons include the standard transparent margin; enlarge so the artwork fills the slot.
            let icon = AppIconResolver.icon(for: url)
            let expansion = rect.width * 0.1215
            icon.draw(
                in: rect.insetBy(dx: -expansion, dy: -expansion),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func drawOverflowBadge(_ label: String, in rect: CGRect, dark: Bool) {
        let radius = rect.width * 0.22
        let badge = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(dark ? 0.56 : 0.34).setFill()
        badge.fill()
        NSColor.white.withAlphaComponent(dark ? 0.34 : 0.52).setStroke()
        badge.lineWidth = max(1, rect.width * 0.025)
        badge.stroke()

        let fontSize = max(rect.width * 0.32, 1)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.96),
            .paragraphStyle: paragraph
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2,
            width: rect.width,
            height: textSize.height
        )
        (label as NSString).draw(in: textRect, withAttributes: attributes)
    }

    static func pngData(
        apps: [URL],
        pixelSize: Int = 512,
        dark: Bool,
        displayMode: DockIconDisplayMode,
        preferredColumns: Int,
        preferredRows: Int
    ) -> Data? {
        render(
            apps: apps,
            pixelSize: pixelSize,
            dark: dark,
            displayMode: displayMode,
            preferredColumns: preferredColumns,
            preferredRows: preferredRows
        )?.representation(using: .png, properties: [:])
    }

    /// The app icon from artwork (Resources/AppIcon.png): its visible square is fitted to the
    /// macOS 26 icon grid (824 of 1024) and shape, with the standard drop shadow, so it sits like
    /// any other app's icon. Without artwork, a generated one.
    static func renderAppIcon(pixelSize: Int, artwork: CGImage?) -> NSBitmapImageRep? {
        guard let artwork else { return renderAppIcon(pixelSize: pixelSize) }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let s = CGFloat(pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.interpolationQuality = .high
        let side = s * 824 / 1024
        let body = CGRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
        let squircle = Path(roundedRect: body, cornerRadius: side * iconCornerRatio, style: .continuous).cgPath

        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        cg.addPath(squircle)
        cg.setFillColor(NSColor.black.cgColor)
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(squircle)
        cg.clip()
        let art = opaqueBounds(of: artwork).flatMap { artwork.cropping(to: $0) } ?? artwork
        cg.draw(art, in: body)
        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The part of an image that isn't transparent (top-left origin, as `cropping(to:)` wants).
    private static func opaqueBounds(of image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The generated Dock Folders app icon: a dark glass squircle with four coloured mini tiles.
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

    static func writeAppIcon(to url: URL, artwork artworkURL: URL? = nil) {
        let artwork = artworkURL.flatMap { NSImage(contentsOf: $0) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, sizes.count, nil) else { return }
        for size in sizes {
            if let image = renderAppIcon(pixelSize: size, artwork: artwork)?.cgImage { CGImageDestinationAddImage(destination, image, nil) }
        }
        CGImageDestinationFinalize(destination)
    }

    /// Writes an .icns (used by Finder, and by the Dock before the plug-in has drawn).
    static func writeICNS(
        apps: [URL],
        dark: Bool,
        displayMode: DockIconDisplayMode,
        preferredColumns: Int,
        preferredRows: Int,
        to url: URL
    ) {
        let sizes = [16, 32, 128, 256, 512]
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.apple.icns" as CFString,
            sizes.count,
            nil
        ) else { return }
        for size in sizes {
            if let image = render(
                apps: apps,
                pixelSize: size,
                dark: dark,
                displayMode: displayMode,
                preferredColumns: preferredColumns,
                preferredRows: preferredRows
            )?.cgImage {
                CGImageDestinationAddImage(destination, image, nil)
            }
        }
        CGImageDestinationFinalize(destination)
    }
}
