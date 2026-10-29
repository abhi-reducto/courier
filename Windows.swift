// SwiftUI views for the Drop window: one column with a drop surface and the device list, and
// Settings behind the round button in the corner. Native macOS controls and grouped lists,
// kept to one surface with nothing shown twice.
import AppKit
import ServiceManagement
import SwiftUI

enum Theme {
    static let nsBG = NSColor.windowBackgroundColor
    static let bg = Color(nsColor: nsBG)
    static let muted = Color.secondary
    static let hairline = Color.primary.opacity(0.08)
    static let mono = Font.system(size: 11.5, design: .monospaced)
}

final class UIState: ObservableObject {
    static let shared = UIState()
    @Published var showSettings = false
}

func icon(_ name: String, size: CGFloat) -> Image {
    lucideImage(name, size: size).map { Image(nsImage: $0) } ?? Image(systemName: "questionmark")
}

struct MainView: View {
    @ObservedObject var ui = UIState.shared

    var body: some View {
        Group {
            if ui.showSettings {
                SettingsPane().transition(.opacity)
            } else {
                HomePane().transition(.opacity)
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }
}

// MARK: Home

struct HomePane: View {
    @ObservedObject var s = Settings.shared
    @State private var showHidden = false

    var visible: [Device] { s.devices.filter { showHidden || !s.hidden.contains($0.name) || $0.name == s.selected } }
    var hiddenCount: Int { s.devices.filter { s.hidden.contains($0.name) && $0.name != s.selected }.count }

    var body: some View {
        VStack(spacing: 0) {
            DropSurface(device: s.device(s.selected))
                .padding(.horizontal, 20)
                .padding(.top, 10)
            Form {
                Section {
                    ForEach(visible) { d in DeviceLine(device: d) }
                } header: {
                    Text("Devices")
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Drop files on any device to send them there. Right-click for its icon and folder.")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        if hiddenCount > 0 {
                            Button(showHidden ? "Hide" : "Show \(hiddenCount) hidden") {
                                withAnimation(.easeOut(duration: 0.18)) { showHidden.toggle() }
                            }
                            .buttonStyle(.link).fixedSize()
                        }
                    }
                    .font(.caption).foregroundStyle(Theme.muted)
                }
                RecentSection()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)  // use the window background, not a second shade
        }
        .onAppear { s.refresh() }
    }
}

struct DropSurface: View {
    let device: Device
    @ObservedObject var s = Settings.shared
    @ObservedObject var uploads = Uploads.shared
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 12) {
                if let pct = uploads.progress[device.name] {
                    ProgressView(value: Double(pct), total: 100).frame(width: 180)
                    Text("Sending to \(device.name)… \(pct)%").foregroundStyle(Theme.muted).monospacedDigit()
                } else {
                    // The box opens while files hover over it.
                    icon(targeted ? "package-open" : "package", size: 30)
                        .foregroundStyle(targeted ? Color.accentColor : Theme.muted)
                    VStack(spacing: 3) {
                        Text("Drop files here").font(.headline)
                        (Text("to \(device.name) · ") + Text(s.dir(for: device.name)).font(Theme.mono))
                            .foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 8) {
                        Button("Choose Files…") { chooseFiles(for: device.name) }
                        Button("Send Clipboard") { sendClipboard(to: device.name) }
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(targeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? Color.accentColor.opacity(0.6) : Theme.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [5, 4])))
            .animation(.easeOut(duration: 0.15), value: targeted)
            .dropDestination(for: URL.self) { urls, _ in
                guard device.online, !urls.isEmpty else { return false }
                uploads.send(urls.map(\.path), to: device.name)
                return true
            } isTargeted: { targeted = $0 }

            if let r = uploads.results[device.name] { ResultLine(result: r) }
        }
    }
}

struct ResultLine: View {
    let result: UploadResult
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(result.ok ? Color.green : Color.red)
            Text(result.ok ? result.paths.joined(separator: "  ") : result.message)
                .font(result.ok ? Theme.mono : .callout)
                .foregroundStyle(Theme.muted)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if result.ok {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.paths.joined(separator: " "), forType: .string)
                }
                .buttonStyle(.link).font(.callout)
            }
        }
        .padding(.horizontal, 4)
    }
}

// One device: icon and name on the left, folder on the right. Click to select it (the drop area
// and the menu bar send to the selected device), drop files on it to send there directly,
// click the folder to edit it, right-click for more.
struct DeviceLine: View {
    let device: Device
    @ObservedObject var s = Settings.shared
    @ObservedObject var uploads = Uploads.shared
    @State private var targeted = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var isSelected: Bool { s.selected == device.name }

    var body: some View {
        HStack(spacing: 10) {
            icon(s.icon(for: device.name), size: 15)
                .foregroundStyle(isSelected ? Color.accentColor : Theme.muted)
            Text(device.name).lineLimit(1)
            Spacer(minLength: 16)
            trailing
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(device.online ? 1 : 0.45)
        .listRowBackground(targeted ? Color.accentColor.opacity(0.16)
                           : isSelected ? Color.accentColor.opacity(0.08) : nil)
        .onTapGesture { if device.online { s.selected = device.name } }
        .dropDestination(for: URL.self) { urls, _ in
            guard device.online, !urls.isEmpty else { return false }
            uploads.send(urls.map(\.path), to: device.name)
            return true
        } isTargeted: { targeted = $0 && device.online }
        .contextMenu {
            Button("Edit Folder") { beginEditing() }
            Menu("Icon") {
                ForEach(deviceIcons, id: \.icon) { i in
                    Button { s.icons[device.name] = i.icon } label: {
                        Label { Text(i.name) } icon: { icon(i.icon, size: 14) }
                    }
                }
            }
            Divider()
            Toggle("Show in Lists", isOn: Binding(
                get: { !s.hidden.contains(device.name) },
                set: { if $0 { s.hidden.remove(device.name) } else { s.hidden.insert(device.name) } }))
        }
    }

    @ViewBuilder var trailing: some View {
        if let pct = uploads.progress[device.name] {
            ProgressView(value: Double(pct), total: 100).frame(width: 80)
        } else if !device.online {
            Text("Offline").foregroundStyle(Theme.muted)
        } else if editing {
            TextField("", text: $draft, prompt: Text(defaultDir))
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono)
                .frame(maxWidth: 240)
                .focused($fieldFocused)
                .onSubmit(commit)
                .onExitCommand { editing = false }
                .onChange(of: fieldFocused) { _, f in if !f { commit() } }
        } else {
            Text(s.dir(for: device.name))
                .font(Theme.mono).foregroundStyle(Theme.muted)
                .lineLimit(1).truncationMode(.head)
                .onTapGesture { beginEditing() }
                .help("Click to change the folder")
        }
    }

    func beginEditing() {
        draft = s.dirs[device.name] ?? ""
        editing = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    func commit() {
        guard editing else { return }
        let v = draft.trimmingCharacters(in: .whitespaces)
        s.dirs[device.name] = v.isEmpty ? nil : v
        editing = false
    }
}

// Files sent, newest first. Click one to copy its path on the device.
struct RecentSection: View {
    @ObservedObject var uploads = Uploads.shared
    @State private var showAll = false
    @State private var copied: UUID?

    var shown: [SentFile] { showAll ? uploads.history : Array(uploads.history.prefix(6)) }

    var body: some View {
        if !uploads.history.isEmpty {
            Section {
                ForEach(shown) { f in row(f) }
            } header: {
                Text("Recent")
            } footer: {
                HStack {
                    if uploads.history.count > 6 {
                        Button(showAll ? "Show less" : "Show all \(uploads.history.count)") { showAll.toggle() }
                    }
                    Spacer()
                    Button("Clear") { uploads.history = [] }
                }
                .buttonStyle(.link).font(.caption)
            }
        }
    }

    func row(_ f: SentFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: f.name.contains(".") ? "doc" : "folder")
                .foregroundStyle(Theme.muted).frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.name).lineLimit(1).truncationMode(.middle)
                Text(copied == f.id ? "Path copied" : "\(f.device) · \(f.date.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Text(ByteCountFormatter.string(fromByteCount: f.bytes, countStyle: .file))
                .font(.callout).foregroundStyle(Theme.muted).monospacedDigit()
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture { copy(f) }
        .help(f.path)
        .contextMenu {
            Button("Copy Path") { copy(f) }
            Button("Remove from List") { uploads.history.removeAll { $0.id == f.id } }
        }
    }

    func copy(_ f: SentFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(f.path.replacingOccurrences(of: " ", with: "\\ "), forType: .string)
        copied = f.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == f.id { copied = nil } }
    }
}

// MARK: Settings

struct SettingsPane: View {
    @ObservedObject var s = Settings.shared
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        // A scrolling Form as the very first view under the transparent title bar draws nothing,
        // so it sits below a fixed-height spacer, like Home's drop area.
        VStack(spacing: 0) {
            Color.clear.frame(height: 4)
            form
        }
    }

    var form: some View {
        Form {
            Section {
                // At least one of these stays on, so the app can always be reached.
                Toggle("Show in Dock", isOn: $s.showInDock).disabled(!s.showInMenuBar)
                Toggle("Show in menu bar", isOn: $s.showInMenuBar).disabled(!s.showInDock)
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }))
            } header: {
                Text("General")
            } footer: {
                Text("One of Dock or menu bar always stays on.").font(.caption).foregroundStyle(Theme.muted)
            }

            Section {
                Toggle("Paste the path into a coding agent", isOn: $s.autoPaste)
                // Two columns of checkboxes. (A LazyVGrid inside a Form doesn't lay out on macOS.)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: agents.count, by: 2)), id: \.self) { i in
                        GridRow {
                            agentBox(agents[i])
                            if i + 1 < agents.count { agentBox(agents[i + 1]) }
                        }
                    }
                }
                .padding(.vertical, 4)
                .disabled(!s.autoPaste)
            } header: {
                Text("Auto-paste")
            } footer: {
                Text("Uses Rex if the device runs it: Courier pastes into the agent pane Rex.app is showing (turn on Remote Control in Rex.app's settings), or else the agent used most recently. It never presses Return. The path is always on your clipboard too.")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func agentBox(_ a: (key: String, name: String)) -> some View {
        Toggle(a.name, isOn: Binding(
            get: { !s.disabledAgents.contains(a.key) },
            set: { if $0 { s.disabledAgents.remove(a.key) } else { s.disabledAgents.insert(a.key) } }))
            .toggleStyle(.checkbox)
    }
}
