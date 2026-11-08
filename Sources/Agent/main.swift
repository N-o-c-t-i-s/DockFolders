import AppKit

// Build-time helper: `Dock Folders --render-icon <path.icns>` writes the app icon and exits.
if let index = CommandLine.arguments.firstIndex(of: "--render-icon"), index + 1 < CommandLine.arguments.count {
    TileRenderer.writeAppIcon(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
