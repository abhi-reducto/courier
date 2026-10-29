# Courier: notes for coding agents

Courier is a macOS menu bar app (AppKit + SwiftUI, no Xcode project) that sends files to Tailscale devices over SSH and pastes the remote path into a coding agent's terminal through Rex. The README describes it from the user's side; this file is for changing and building it.

## Build and run

```sh
./install.sh
```

That's the whole build: `swiftc` compiles the four Swift files into `~/Applications/Courier.app`, renders the app icon (`make-icon.swift`), copies the Lucide SVGs into `Contents/Resources`, ad-hoc signs the bundle, installs `rimg` and `rex-paste` into `~/.local/bin`, and relaunches the app. There is no test suite; verify by building, by running `rimg` directly, and by rendering screenshots (below).

Requirements: macOS 14+, Xcode Command Line Tools. Don't add an Xcode project, Swift Package, or third-party dependencies.

## Files

| File | What's in it |
|---|---|
| `main.swift` | Entry point only |
| `Core.swift` | Model: `Device`, `Settings` (UserDefaults-backed, `ObservableObject`), `Uploads` (runs `rimg`, publishes progress, results, history), Tailscale/SSH/Rex lookups, `friendlyError` |
| `MenuBar.swift` | `AppDelegate`: status item and its menu, drop target on the status item, Dock/menu bar visibility, the window and its toolbar, the app's main menu, notifications |
| `Windows.swift` | SwiftUI: `MainView` (drop surface, device list, recent files) and `SettingsPane` |
| `rimg` | zsh uploader. Streams files over one shared SSH connection, claims `name (N)` names atomically on the remote, pastes via `rex-paste`, copies paths to the clipboard |
| `rex-paste` | Python. Finds the terminal running an agent through the Rex API and pastes text into it |
| `make-icon.swift` | Draws the 1024px app icon |
| `scripts/screenshots.sh` | Renders `docs/screenshots/*.png` from demo data |

## The app ↔ rimg contract

The app runs `rimg` with `RIMG_HOST`, `RIMG_DIR`, `RIMG_REX`, `RIMG_AGENTS`, and `RIMG_PROGRESS=1`. In that mode `rimg` writes these lines to stderr, which `Uploads.send` parses (they're stripped from error text):

- `@progress N`: overall percent
- `@sent <bytes> <remote path>`: one per file or folder sent
- `@uploaded`: all files are on the device; the agent paste is still running. The app shows "Sent" here instead of waiting.

stdout is one remote path per line. Anything else on stderr is an error message; `friendlyError` turns common SSH failures into sentences. Keep `rimg` usable by hand from a terminal: without `RIMG_PROGRESS=1` it shows a live percentage instead.

## Checking UI changes

You likely can't take real screenshots (no screen-recording permission), so render the views offscreen:

```sh
scripts/screenshots.sh
```

It builds a copy of the app under a separate app ID (`dev.abhia.courier.screenshots`) with demo devices and history injected via `Settings.deviceSource`, and writes light/dark PNGs of the window and Settings into `docs/screenshots/`. Look at them before saying a UI change is done. Never put real device names, paths, or file names in screenshots or commits.

Limits of offscreen rendering: macOS's glass/vibrancy materials draw as blank or white blobs (the toolbar button is drawn unbordered for this reason), the status item menu can't be captured, and drag-and-drop can't be simulated.

## Pitfalls already hit

- A `LazyVGrid` inside a `Form` doesn't lay out on macOS. Use `Grid`.
- `.ignoresSafeArea` around a `Form`, or a scrolling `Form` as the very first view under a transparent title bar, renders the whole window blank. `SettingsPane` sits below a 4pt spacer for this reason.
- Grouped `Form`s paint their own background; use `.scrollContentBackground(.hidden)` so the window is one color. The toolbar uses a transparent title bar with `.fullSizeContentView` for the same reason.
- `NSHostingController` resizes its window to the SwiftUI content by default. The main window sets `sizingOptions = []`.
- Dropping files on an `NSStatusItem` only works through a subview that registers for drags and implements `draggingUpdated` and `prepareForDragOperation`; its `hitTest` returns nil so clicks still open the menu.
- Switching to `.accessory` activation policy (leaving the Dock) hides the app's windows; `applyVisibility` brings the window back.
- A right-aligned column in an `NSMenu` can't line up with submenu arrows or ⌘ shortcuts, so the status menu has neither.
- Notifications go through `UNUserNotificationCenter` so they carry Courier's icon (not `osascript`, which shows Script Editor's).

## Conventions

- Native macOS controls and one calm surface: no repeated information, no second window for settings, gray secondary text, hairline separators. Check both light and dark.
- Comments explain why, briefly, in the style already in the files. User-facing text is short, plain, and says what to do next.
- Settings are `@Published` properties on `Settings` persisted to `UserDefaults` in `didSet`. The app ID is `dev.abhia.courier`; `Settings.migrateOldSettings` copies settings once from the earlier IDs (`ai.reducto.courier`, `ai.reducto.abhi.drop`).
- Icons are Lucide SVGs in `icons/` (stroke color set to `#000` so `NSImage` renders them as templates). Add new ones from the same Lucide version (`lucide-static@0.460.0`) and load them with `lucideImage`.
