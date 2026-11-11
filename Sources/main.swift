import Cocoa
import UserNotifications

// MARK: - Parse CLI arguments
var stdinJSON: [String: Any] = [:]
var activateBundleID = "com.apple.Terminal"
var itermSessionUUID: String?
var tmuxBin: String?
var tmuxSocket: String?
var tmuxPane: String?
var herdrBin: String?
var herdrTerminal: String?

// Optional overrides from CLI — if provided, skip type-based fallback logic
var overrideTitle: String?
var overrideSubtitle: String?
var overrideBody: String?
var overrideSound: String?

func parseArguments() {
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        let arg = args[i]
        let next: String? = (i + 1 < args.count) ? args[i + 1] : nil

        switch arg {
        case "--data":
            if let filePath = next {
                if let data = FileManager.default.contents(atPath: filePath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    stdinJSON = json
                }
                try? FileManager.default.removeItem(atPath: filePath)
                i += 2
                continue
            }
        case "--activate":
            if let v = next { activateBundleID = v; i += 2; continue }
        case "--iterm-session":
            if let v = next { itermSessionUUID = v; i += 2; continue }
        case "--tmux-bin":
            if let v = next { tmuxBin = v; i += 2; continue }
        case "--tmux-socket":
            if let v = next { tmuxSocket = v; i += 2; continue }
        case "--tmux-pane":
            if let v = next { tmuxPane = v; i += 2; continue }
        case "--herdr-bin":
            if let v = next { herdrBin = v; i += 2; continue }
        case "--herdr-terminal":
            if let v = next { herdrTerminal = v; i += 2; continue }
        case "--title":
            if let v = next { overrideTitle = v; i += 2; continue }
        case "--subtitle":
            if let v = next { overrideSubtitle = v; i += 2; continue }
        case "--body":
            if let v = next { overrideBody = v; i += 2; continue }
        case "--sound":
            if let v = next { overrideSound = v; i += 2; continue }
        default:
            break
        }
        i += 1
    }
}

parseArguments()
let hasInput = !stdinJSON.isEmpty || overrideBody != nil

// MARK: - App Delegate
class NotifierDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always set up the delegate — needed to handle notification clicks
        // when macOS relaunches the app after it has exited.
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        if !hasInput {
            // Relaunched without data — could be a notification click (delegate will
            // fire didReceive) or macOS housekeeping. Wait briefly; if no click
            // arrives, exit silently.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSApp.terminate(nil)
            }
            return
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                FileHandle.standardError.write("ClaudeNotifier: authorization error: \(error.localizedDescription)\n".data(using: .utf8)!)
            }
            if !granted {
                FileHandle.standardError.write("ClaudeNotifier: notification permission denied\n".data(using: .utf8)!)
            }
            DispatchQueue.main.async { self.postNotification() }
        }
    }

    func readCustomTitle() -> String? {
        guard let transcriptPath = stdinJSON["transcript_path"] as? String else { return nil }
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines).reversed() {
            if line.contains("\"customTitle\""),
               let lineData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let t = json["customTitle"] as? String, !t.isEmpty {
                return t
            }
        }
        return nil
    }

    func postNotification() {
        // Fallback values from JSON + type-based switch (used if CLI overrides absent)
        let message = stdinJSON["message"] as? String ?? "Done"
        let jsonTitle = stdinJSON["title"] as? String
        let type = stdinJSON["notification_type"] as? String ?? "unknown"
        let cwd = stdinJSON["cwd"] as? String ?? ""
        let sessionLabel = readCustomTitle() ?? (cwd as NSString).lastPathComponent

        var fallbackTitle: String
        var fallbackSound: String
        switch type {
        case "permission_prompt":  fallbackTitle = "🔐 Permission Required"; fallbackSound = "Blow"
        case "idle_prompt":        fallbackTitle = "💤 Waiting for Input";    fallbackSound = "Tink"
        case "auth_success":       fallbackTitle = "✅ Auth Complete";        fallbackSound = "Glass"
        case "elicitation_dialog": fallbackTitle = "💬 Input Needed";         fallbackSound = "Blow"
        default:                   fallbackTitle = "🤖 Claude Code";          fallbackSound = "default"
        }

        var fallbackSubtitle = jsonTitle ?? ""
        if !sessionLabel.isEmpty {
            fallbackSubtitle = fallbackSubtitle.isEmpty ? "[\(sessionLabel)]" : "[\(sessionLabel)] \(fallbackSubtitle)"
        }

        // Apply CLI overrides where provided, fall back otherwise
        let finalTitle = overrideTitle ?? fallbackTitle
        let finalSubtitle = overrideSubtitle ?? fallbackSubtitle
        let finalBody = overrideBody ?? message
        let finalSound = overrideSound ?? fallbackSound

        let content = UNMutableNotificationContent()
        content.title = finalTitle
        content.subtitle = finalSubtitle
        content.body = finalBody
        content.sound = finalSound == "default"
            ? UNNotificationSound.default
            : UNNotificationSound(named: UNNotificationSoundName(finalSound))

        // Embed activation info so notification clicks can restore it on app relaunch
        var userInfo: [String: Any] = ["bundleID": activateBundleID]
        if let uuid = itermSessionUUID { userInfo["itermSessionUUID"] = uuid }
        if let bin = tmuxBin       { userInfo["tmuxBin"]    = bin }
        if let sock = tmuxSocket   { userInfo["tmuxSocket"] = sock }
        if let pane = tmuxPane     { userInfo["tmuxPane"]   = pane }
        if let bin = herdrBin      { userInfo["herdrBin"]      = bin }
        if let t = herdrTerminal   { userInfo["herdrTerminal"] = t }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "claude-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                NSApp.terminate(nil)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Recover activation info from userInfo (CLI args aren't re-passed on relaunch)
        let userInfo = response.notification.request.content.userInfo
        if let bundleID = userInfo["bundleID"] as? String {
            activateBundleID = bundleID
        }
        if let uuid = userInfo["itermSessionUUID"] as? String {
            itermSessionUUID = uuid
        }
        if let bin = userInfo["tmuxBin"] as? String       { tmuxBin = bin }
        if let sock = userInfo["tmuxSocket"] as? String   { tmuxSocket = sock }
        if let pane = userInfo["tmuxPane"] as? String     { tmuxPane = pane }
        if let bin = userInfo["herdrBin"] as? String      { herdrBin = bin }
        if let t = userInfo["herdrTerminal"] as? String   { herdrTerminal = t }
        activateTerminal()
        completionHandler()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func activateTerminal() {
        var didSelectITerm = false
        if activateBundleID == "com.googlecode.iterm2", let uuid = itermSessionUUID {
            didSelectITerm = selectITermSession(uuid: uuid)
        }
        if !didSelectITerm {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: activateBundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }

        // After the terminal app is frontmost, jump tmux to the originating
        // session/window/pane in one shot. switch-client accepts a pane target.
        if let bin = tmuxBin, let sock = tmuxSocket, let pane = tmuxPane {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = ["-S", sock, "switch-client", "-t", pane]
                try? p.run()
            }
        }

        // Herdr: show the originating agent's space, tab and pane. `herdr-app do`
        // talks to the running window over its socket; it does not open a new one.
        if let bin = herdrBin, let terminal = herdrTerminal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = ["do", "agent.focus", "--terminal", terminal]
                try? p.run()
            }
        }
    }

    func selectITermSession(uuid: String) -> Bool {
        let script = """
        tell application "iTerm2"
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique id of aSession is "\(uuid)" then
                            tell aTab to select
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil && result.booleanValue {
                return true
            }
            if let err = error {
                FileHandle.standardError.write("ClaudeNotifier: iTerm AppleScript error: \(err)\n".data(using: .utf8)!)
            }
        }
        return false
    }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = NotifierDelegate()
app.delegate = delegate
app.run()
