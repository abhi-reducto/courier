// Renders docs/screenshots/*.png from demo data. Run scripts/screenshots.sh, not this file directly.
import AppKit
import SwiftUI
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let out = CommandLine.arguments[1]

// Demo data only; this runs under its own app ID, so real settings are untouched.
Settings.deviceSource = {[
    Device(name: "devbox", dns: "devbox.example.ts.net", online: true, os: "linux"),
    Device(name: "gpu-runner", dns: "gpu-runner.example.ts.net", online: true, os: "linux"),
    Device(name: "studio", dns: "studio.example.ts.net", online: true, os: "macOS"),
    Device(name: "old-nas", dns: "old-nas.example.ts.net", online: false, os: "linux"),
]}
let s = Settings.shared
s.refresh()
s.hidden = []
s.selected = "devbox"
s.dirs = ["devbox": "~/inbox", "gpu-runner": "~/datasets/incoming"]
s.icons = ["studio": "monitor"]
s.autoPaste = true
s.disabledAgents = ["devin", "goose"]
let now = Date()
Uploads.shared.history = [
    SentFile(path: "/home/me/inbox/Screenshot 2026-10-29 at 9.41.12.png", bytes: 1_284_000, device: "devbox", date: now.addingTimeInterval(-90)),
    SentFile(path: "/home/me/datasets/incoming/q3-metrics.csv", bytes: 48_200, device: "gpu-runner", date: now.addingTimeInterval(-3600)),
    SentFile(path: "/Users/me/.cache/claude-images/design-specs", bytes: 3_400_000, device: "studio", date: now.addingTimeInterval(-86400)),
]

let d = AppDelegate()
func shot(_ name: String, dark: Bool, settings: Bool, progress: Int? = nil) {
    UIState.shared.showSettings = settings
    Uploads.shared.progress = progress.map { ["devbox": $0] } ?? [:]
    d.openMain()
    let w = d.mainWindow!
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    d.settingsToolbarItem?.isBordered = false   // the glass button style can't be captured offscreen
    d.settingsToolbarItem?.image = NSImage(systemSymbolName: settings ? "xmark" : "gearshape", accessibilityDescription: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let view = w.contentView!.superview!
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    w.close(); d.mainWindow = nil
}
shot("settings-light", dark: false, settings: true)
shot("settings-dark", dark: true, settings: true)
shot("home-light", dark: false, settings: false)
shot("home-dark", dark: true, settings: false)
shot("sending-dark", dark: true, settings: false, progress: 62)
exit(0)
