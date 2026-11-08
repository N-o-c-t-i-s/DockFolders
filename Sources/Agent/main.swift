import AppKit

// Build-time helper: `Dock Folders --render-icon <path.icns> [artwork.png]` writes the app icon
// (from the artwork when given) and exits.
if let index = CommandLine.arguments.firstIndex(of: "--render-icon"), index + 1 < CommandLine.arguments.count {
    let artwork = index + 2 < CommandLine.arguments.count ? URL(fileURLWithPath: CommandLine.arguments[index + 2]) : nil
    TileRenderer.writeAppIcon(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), artwork: artwork)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
