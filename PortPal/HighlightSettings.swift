import SwiftUI
import Combine
import UserNotifications
import AudioToolbox
import AppKit

// 1. Color structure supporting Codable
// SwiftUI.Color doesn't directly conform to Codable, so we convert and store RGBA values.
struct CodableColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(color: Color) {
        let nsColor = NSColor(color)
        // Convert NSColor to genericRGB color space to get RGBA values
        if let convertedColor = nsColor.usingColorSpace(.genericRGB) {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            self.red = Double(r)
            self.green = Double(g)
            self.blue = Double(b)
            self.opacity = Double(a)
        } else {
            // Set default values on conversion failure (e.g., black)
            self.red = 0
            self.green = 0
            self.blue = 0
            self.opacity = 1
        }
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}


// 2. Data structure defining highlight keywords and colors
struct HighlightKeyword: Identifiable, Codable, Hashable {
    var id = UUID()
    var keyword: String
    var color: CodableColor
    var isEnabled: Bool = true
    var isNotificationEnabled: Bool = false

    // Convenience property to use color property directly
    var swiftUIColor: Color {
        get { color.color }
        set { color = CodableColor(color: newValue) }
    }
}

// 3. ViewModel to manage highlight settings and save/load from UserDefaults
@MainActor
class HighlightSettings: ObservableObject {
    @Published var keywords: [HighlightKeyword] = [] {
        didSet {
            save()
        }
    }

    private let userDefaultsKey = "highlightKeywords"

    init() {
        load()
        requestNotificationPermission()
    }

    // Set default values
    private func setDefaultKeywords() {
        self.keywords = [
            HighlightKeyword(keyword: "Error", color: CodableColor(color: .red)),
            HighlightKeyword(keyword: "Warning", color: CodableColor(color: .orange)),
            HighlightKeyword(keyword: "Success", color: CodableColor(color: .green))
        ]
    }

    func addKeyword() {
        let newKeyword = HighlightKeyword(keyword: "New Keyword", color: CodableColor(color: .yellow))
        keywords.append(newKeyword)
    }

    func remove(at offsets: IndexSet) {
        keywords.remove(atOffsets: offsets)
    }

    func remove(keyword: HighlightKeyword) {
        keywords.removeAll { $0.id == keyword.id }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(keywords) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([HighlightKeyword].self, from: data) {
                self.keywords = decoded
                return
            }
        }
        // Load default values if no saved data exists
        setDefaultKeywords()
    }

    // MARK: - Notification functionality

    private func requestNotificationPermission() {
        // First check current permission status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("📋 Current notification settings: \(settings.authorizationStatus.rawValue)")

                switch settings.authorizationStatus {
                case .authorized:
                    print("✅ Notifications already authorized")
                case .denied:
                    print("❌ Notifications denied by user")
                    print("💡 To enable notifications, go to System Settings > Notifications > PortPal")
                    self.showNotificationPermissionAlert()
                case .notDetermined:
                    print("❓ Notification permission not determined, requesting...")
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ Notification permission error: \(error)")
                            } else {
                                print("✅ Notification permission granted: \(granted)")
                            }
                        }
                    }
                case .provisional:
                    print("⚠️ Provisional authorization")
                case .ephemeral:
                    print("⏳ Ephemeral authorization")
                @unknown default:
                    print("❓ Unknown authorization status")
                }
            }
        }
    }

    func triggerNotification(for keyword: HighlightKeyword, text: String) {
        guard keyword.isEnabled && keyword.isNotificationEnabled else {
            print("🔇 Notification skipped for '\(keyword.keyword)' - disabled")
            return
        }

        print("🔔 Triggering banner notification for keyword: '\(keyword.keyword)'")
        showBannerNotification(for: keyword, text: text)
    }

    private func showBannerNotification(for keyword: HighlightKeyword, text: String) {
        print("📱 Creating banner notification for: \(keyword.keyword)")

        // First try UNUserNotification
        let content = UNMutableNotificationContent()
        content.title = "Keyword Detected: \(keyword.keyword)"
        content.body = text.prefix(100).description + (text.count > 100 ? "..." : "")
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "keyword-\(keyword.id.uuidString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ UNUserNotification error: \(error)")
                    // Fallback to simple alert if UNUserNotification fails
                    self.showSimpleAlert(for: keyword, text: text)
                } else {
                    print("✅ UNUserNotification sent successfully")
                }
            }
        }
    }

    private func showSimpleAlert(for keyword: HighlightKeyword, text: String) {
        print("🪟 Showing simple alert as fallback")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Keyword Detected: \(keyword.keyword)"
            alert.informativeText = text.prefix(100).description + (text.count > 100 ? "..." : "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")

            // Show alert even when app is in background
            alert.runModal()
        }
    }

    private func showNotificationPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Notification Permission Required"
            alert.informativeText = "To use keyword notification features, please allow PortPal's notification permission in System Settings.\n\nGo to System Settings > Notifications & Focus > PortPal and turn on 'Allow Notifications'."
            alert.alertStyle = .informational

            let openSettingsButton = alert.addButton(withTitle: "Open System Settings")
            let cancelButton = alert.addButton(withTitle: "Later")

            openSettingsButton.keyEquivalent = "\r" // Enter key
            cancelButton.keyEquivalent = "\u{1b}" // Escape key

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Open system settings
                self.openSystemNotificationSettings()
            }
        }
    }

    private func openSystemNotificationSettings() {
        // New Settings app path for macOS Ventura and later
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: Open general system settings
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
        }
    }

    private func playNotificationSound() {
        print("🔊 Playing notification sound")

        if let soundURL = Bundle.main.url(forResource: "notification", withExtension: "aiff") {
            print("🎵 Using custom notification sound")
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else {
            print("🎵 Using system default sound")
            // Use default system sound
            AudioServicesPlaySystemSound(SystemSoundID(1000)) // System default notification sound
        }
    }

    // Function to manually check notification permission status (can be called from UI)
    func checkNotificationPermission() {
        requestNotificationPermission()
    }
}
