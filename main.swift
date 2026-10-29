// Courier: send files from your Mac to a Tailscale device, from the menu bar or the Drop window.
// Core.swift holds the model, MenuBar.swift the app and menu bar, Windows.swift the SwiftUI views.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
