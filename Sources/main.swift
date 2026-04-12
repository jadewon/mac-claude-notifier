import Cocoa
import UserNotifications

// MARK: - Parse CLI arguments
var stdinJSON: [String: Any] = [:]
var activateBundleID = "com.apple.Terminal"

func parseArguments() {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--data"), i + 1 < args.count {
        let filePath = args[i + 1]
        if let data = FileManager.default.contents(atPath: filePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            stdinJSON = json
        }
        try? FileManager.default.removeItem(atPath: filePath)
    }
    if let i = args.firstIndex(of: "--activate"), i + 1 < args.count {
        activateBundleID = args[i + 1]
    }
}

parseArguments()
let hasInput = !stdinJSON.isEmpty

// MARK: - App Delegate
class NotifierDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasInput {
            // No data — likely relaunched by macOS from notification center. Just exit.
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
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
        let message = stdinJSON["message"] as? String ?? "Done"
        let title = stdinJSON["title"] as? String
        let type = stdinJSON["notification_type"] as? String ?? "unknown"
        let cwd = stdinJSON["cwd"] as? String ?? ""

        let sessionLabel = readCustomTitle() ?? (cwd as NSString).lastPathComponent

        var notiTitle: String
        var soundName: String

        switch type {
        case "permission_prompt":  notiTitle = "🔐 Permission Required"; soundName = "Blow"
        case "idle_prompt":        notiTitle = "💤 Waiting for Input";    soundName = "Tink"
        case "auth_success":       notiTitle = "✅ Auth Complete";        soundName = "Glass"
        case "elicitation_dialog": notiTitle = "💬 Input Needed";         soundName = "Blow"
        default:                   notiTitle = "🤖 Claude Code";          soundName = "default"
        }

        var subtitle = title ?? ""
        if !sessionLabel.isEmpty {
            subtitle = subtitle.isEmpty ? "[\(sessionLabel)]" : "[\(sessionLabel)] \(subtitle)"
        }

        let content = UNMutableNotificationContent()
        content.title = notiTitle
        content.subtitle = subtitle
        content.body = message
        content.sound = soundName == "default"
            ? UNNotificationSound.default
            : UNNotificationSound(named: UNNotificationSoundName(soundName))

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
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: activateBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = NotifierDelegate()
app.delegate = delegate
app.run()
