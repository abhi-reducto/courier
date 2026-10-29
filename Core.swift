// Courier's model: Tailscale devices, settings, and uploads (which run ~/.local/bin/rimg).
import AppKit
import Combine

let rexDir = NSHomeDirectory() + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
let home = NSHomeDirectory()

func log(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    let url = URL(fileURLWithPath: "\(home)/Library/Logs/Courier.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

struct Device: Identifiable, Hashable {
    var id: String { name }
    let name: String      // Tailscale HostName
    let dns: String       // MagicDNS name
    let online: Bool
    var os: String = ""
}

// onStderrLine sees stderr line by line as it arrives; "@" lines (rimg's messages for the app) are left out of the returned stderr.
func run(_ path: String, _ args: [String], env: [String: String] = [:], onStderrLine: ((String) -> Void)? = nil) -> (Int32, String, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    var e = ProcessInfo.processInfo.environment
    e["PATH"] = "\(rexDir):\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin"
    e.merge(env) { $1 }
    p.environment = e
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (1, "", "\(error)") }
    var errText = ""
    let errDone = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        var buf = Data()
        let h = err.fileHandleForReading
        while case let chunk = h.availableData, !chunk.isEmpty {
            buf.append(chunk)
            while let nl = buf.firstIndex(of: 10) {
                let line = String(decoding: buf[buf.startIndex..<nl], as: UTF8.self)
                buf.removeSubrange(buf.startIndex...nl)
                onStderrLine?(line)
                if !line.hasPrefix("@") { errText += line + "\n" }
            }
        }
        errText += String(decoding: buf, as: UTF8.self)
        errDone.signal()
    }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    errDone.wait()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self), errText)
}

// The Tailscale CLI: Homebrew, the standalone install, or the one inside the Mac App Store app.
let tailscaleCLI = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
                    "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/tailscale"

func tailscaleDevices() -> [Device] {
    let (code, out, _) = run(tailscaleCLI, ["status", "--json"])
    guard code == 0, let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
          let peers = json["Peer"] as? [String: [String: Any]] else { return [] }
    return peers.values.compactMap { p in
        guard let name = p["HostName"] as? String, let dns = p["DNSName"] as? String,
              (p["OS"] as? String) != "iOS" else { return nil }
        return Device(name: name, dns: dns.hasSuffix(".") ? String(dns.dropLast()) : dns, online: p["Online"] as? Bool ?? false, os: p["OS"] as? String ?? "")
    }.sorted { ($0.online ? 0 : 1, $0.name.lowercased()) < ($1.online ? 0 : 1, $1.name.lowercased()) }
}

// ssh config aliases and the HostName each points at.
func sshAliases() -> [String: String] {
    guard let text = try? String(contentsOfFile: "\(home)/.ssh/config", encoding: .utf8) else { return [:] }
    var map: [String: String] = [:]
    var current: [String] = []
    for line in text.split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        switch parts[0].lowercased() {
        case "host": current = parts[1].split(separator: " ").map(String.init).filter { !$0.contains("*") }
            for a in current { map[a] = a }
        case "hostname": for a in current { map[a] = parts[1] }
        default: break
        }
    }
    return map
}

func rexLabels() -> [(label: String, endpoints: [String])] {
    let (code, out, _) = run("\(rexDir)/rex", ["hosts", "list", "--json"])
    guard code == 0, let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
          let hosts = json["hosts"] as? [[String: Any]] else { return [] }
    return hosts.compactMap { h in
        guard let host = h["host"] as? [String: Any], let label = host["label"] as? String else { return nil }
        return (label, host["endpoints"] as? [String] ?? [])
    }
}

// Pick the ssh target and Rex label for a device. Prefer an ssh alias named like the device
// (it carries the right user and keys), else the MagicDNS name.
func targets(for d: Device) -> (ssh: String, rex: String) {
    let aliases = sshAliases()
    let short = d.dns.split(separator: ".").first.map(String.init) ?? d.name
    let ssh = aliases.first { $0.key == d.name || $0.value == d.dns || $0.value == short }?.key ?? d.dns
    let rex = rexLabels().first { r in
        r.label == ssh || r.label == d.name || r.endpoints.contains { $0.contains("//\(d.dns)") || $0.contains("//rex-\(d.name).") }
    }?.label ?? ""
    return (ssh, rex)
}

// Coding agents Drop can paste into. Keys are what rex-paste matches against the terminal's program.
let agents: [(key: String, name: String)] = [
    ("claude", "Claude Code"), ("codex", "Codex"), ("cursor-agent", "Cursor Agent"), ("gemini", "Gemini CLI"),
    ("opencode", "OpenCode"), ("grok", "Grok"), ("amp", "Amp"), ("aider", "Aider"), ("goose", "Goose"),
    ("copilot", "Copilot CLI"), ("devin", "Devin"),
]
let defaultDir = "~/.cache/claude-images"

// Lucide icons (lucide.dev), bundled as SVGs in Contents/Resources.
func lucideImage(_ name: String, size: CGFloat = 18) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
          let img = NSImage(contentsOf: url) else { return nil }
    img.size = NSSize(width: size, height: size)
    img.isTemplate = true
    return img
}

// Icons a device can have, as (Lucide icon, label).
let deviceIcons: [(icon: String, name: String)] = [
    ("monitor", "Desktop"), ("laptop", "Laptop"), ("server", "Server"), ("cloud", "Cloud"),
    ("terminal", "Terminal"), ("smartphone", "Phone"), ("house", "Home"), ("briefcase", "Work"), ("box", "Box"),
]

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var selected: String { didSet { d.set(selected, forKey: "device") } }
    // Destination folder per device name: absolute, ~/..., or relative to home.
    @Published var dirs: [String: String] { didSet { d.set(dirs, forKey: "dirs") } }
    // Devices left out of the menu. Rex's own Tailscale nodes (rex-*) start hidden.
    @Published var hidden: Set<String> { didSet { d.set(Array(hidden), forKey: "hidden") } }
    @Published var autoPaste: Bool { didSet { d.set(autoPaste, forKey: "autoPaste") } }
    @Published var disabledAgents: Set<String> { didSet { d.set(Array(disabledAgents), forKey: "disabledAgents") } }
    // Chosen icon per device name; see icon(for:) for the default.
    @Published var icons: [String: String] { didSet { d.set(icons, forKey: "icons") } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }
    @Published var showInMenuBar: Bool { didSet { d.set(showInMenuBar, forKey: "showInMenuBar") } }
    @Published var devices: [Device] = []

    init() {
        Self.migrateFromDrop()
        selected = d.string(forKey: "device") ?? ""
        dirs = d.dictionary(forKey: "dirs") as? [String: String] ?? [:]
        hidden = Set(d.stringArray(forKey: "hidden") ?? [])
        autoPaste = d.object(forKey: "autoPaste") as? Bool ?? true
        disabledAgents = Set(d.stringArray(forKey: "disabledAgents") ?? [])
        icons = d.dictionary(forKey: "icons") as? [String: String] ?? [:]
        showInDock = d.object(forKey: "showInDock") as? Bool ?? false
        showInMenuBar = d.object(forKey: "showInMenuBar") as? Bool ?? true
        if d.stringArray(forKey: "hidden") == nil {
            hidden = Set(tailscaleDevices().map(\.name).filter { $0.hasPrefix("rex-") })
        }
    }

    // Courier was called Drop and stored its settings under that app ID. Copy them over once.
    static func migrateFromDrop() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromDrop") else { return }
        if let old = UserDefaults(suiteName: "ai.reducto.abhi.drop")?.persistentDomain(forName: "ai.reducto.abhi.drop") {
            for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        }
        d.set(true, forKey: "migratedFromDrop")
    }

    func dir(for device: String) -> String { dirs[device] ?? defaultDir }
    func icon(for device: String) -> String {
        if let i = icons[device] { return i }
        switch devices.first(where: { $0.name == device })?.os {
        case "macOS": return "laptop"
        case "linux": return "server"
        case "iOS", "android": return "smartphone"
        default: return "monitor"
        }
    }
    func device(_ name: String) -> Device {
        devices.first { $0.name == name } ?? Device(name: name, dns: name, online: true)
    }
    // Where devices come from. The screenshot script swaps in demo devices.
    static var deviceSource: () -> [Device] = tailscaleDevices
    func refresh() { devices = Self.deviceSource() }
    var enabledAgents: [String] { agents.map(\.key).filter { !disabledAgents.contains($0) } }
}

struct SentFile: Codable, Identifiable {
    var id = UUID()
    let path: String     // on the device
    let bytes: Int64
    let device: String
    let date: Date
    var name: String { (path as NSString).lastPathComponent }
}

struct UploadResult {
    let ok: Bool
    let message: String
    let paths: [String]
}

// Runs uploads and publishes their progress per device, for the window and the menu bar icon.
final class Uploads: ObservableObject {
    static let shared = Uploads()
    @Published var progress: [String: Int] = [:]          // device name -> percent, while uploading
    @Published var results: [String: UploadResult] = [:]  // device name -> last upload
    // Everything sent, newest first, kept across launches.
    @Published var history: [SentFile] = {
        guard let data = UserDefaults.standard.data(forKey: "history") else { return [] }
        return (try? JSONDecoder().decode([SentFile].self, from: data)) ?? []
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history") }
    }
    let finished = PassthroughSubject<UploadResult, Never>()

    // No files means the clipboard image.
    func send(_ files: [String], to name: String) {
        let settings = Settings.shared
        let device = settings.device(name)
        let folder = settings.dir(for: name)
        let autoPaste = settings.autoPaste
        let agentList = settings.enabledAgents.joined(separator: ",")
        progress[name] = 0
        results[name] = nil
        DispatchQueue.global().async {
            var sentPaths: [String] = []
            var reported = false  // set once "Sent" is shown, which can be before rimg exits
            func report(_ r: UploadResult) {
                DispatchQueue.main.async {
                    self.progress[name] = nil
                    self.results[name] = r
                    self.finished.send(r)
                }
            }
            let t = targets(for: device)
            let rex = autoPaste ? t.rex : ""
            let (code, out, err) = run("\(home)/.local/bin/rimg", files,
                                       env: ["RIMG_HOST": t.ssh, "RIMG_REX": rex, "RIMG_AGENTS": agentList,
                                             "RIMG_DIR": folder, "RIMG_PROGRESS": "1"]) { line in
                if line.hasPrefix("@progress "), let pct = Int(line.dropFirst(10)) {
                    DispatchQueue.main.async { self.progress[name] = pct }
                } else if line.hasPrefix("@sent ") {
                    // "@sent <bytes> <remote path>"
                    let parts = line.dropFirst(6).split(separator: " ", maxSplits: 1)
                    if parts.count == 2, let bytes = Int64(parts[0]) {
                        let file = SentFile(path: String(parts[1]), bytes: bytes, device: name, date: Date())
                        sentPaths.append(file.path)
                        DispatchQueue.main.async { self.history = Array(([file] + self.history).prefix(200)) }
                    }
                } else if line == "@uploaded" {
                    // Files are on the device; the agent paste is still running, but that's not worth waiting for.
                    reported = true
                    let n = sentPaths.count
                    report(UploadResult(ok: true, message: "Sent \(n) file\(n == 1 ? "" : "s") to \(name)"
                                        + (rex.isEmpty ? ". Path copied, paste with ⌘V" : ""), paths: sentPaths))
                }
            }
            let paths = out.split(separator: "\n").map(String.init)
            let result: UploadResult
            if code == 0 {
                let n = paths.count
                result = UploadResult(ok: true, message: "Sent \(n) file\(n == 1 ? "" : "s") to \(name)"
                                      + (rex.isEmpty ? ". Path copied, paste with ⌘V" : ""), paths: paths)
            } else {
                result = UploadResult(ok: false, message: friendlyError(err, device: name), paths: [])
            }
            if !reported { report(result) }
        }
    }
}

// Turns rimg and ssh errors into a sentence that says what to do.
func friendlyError(_ stderr: String, device: String) -> String {
    let has = { (s: String) in stderr.localizedCaseInsensitiveContains(s) }
    if has("Could not resolve hostname") || has("timed out") || has("No route to host") || has("Connection refused") {
        return "Couldn't reach \(device). Check that it's online and SSH is on."
    }
    if has("Permission denied") { return "\(device) turned down the SSH login. Check your SSH key for it." }
    if has("Host key verification failed") || has("REMOTE HOST IDENTIFICATION") {
        return "SSH doesn't trust \(device) yet. Run ssh to it once in Terminal to accept its key."
    }
    if has("No space left") { return "\(device) is out of disk space." }
    if has("can't create") || has("Read-only") { return "Couldn't write to that folder on \(device). Try a different one." }
    // rimg's own messages: drop the "rimg: " prefix, which is only there for the terminal.
    var msg = stderr.split(separator: "\n").last(where: { !$0.isEmpty }).map(String.init) ?? "Something went wrong sending to \(device)."
    if msg.hasPrefix("rimg: ") { msg.removeFirst(6) }
    return msg.prefix(1).uppercased() + msg.dropFirst()
}
