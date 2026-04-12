import Cocoa
import UserNotifications

// MARK: - Parse CLI arguments
var stdinJSON: [String: Any] = [:]
var activateBundleID = "com.apple.Terminal"

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
