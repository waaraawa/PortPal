import SwiftUI
import Combine
import UserNotifications
import AudioToolbox
import AppKit

// 1. Codable을 지원하는 Color 표현을 위한 구조체
// SwiftUI.Color는 직접 Codable을 준수하지 않으므로, RGBA 값으로 변환하여 저장합니다.
struct CodableColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(color: Color) {
        let nsColor = NSColor(color)
        // NSColor를 genericRGB 색상 공간으로 변환하여 RGBA 값을 얻을 수 있도록 함
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
            // 변환 실패 시 기본값 설정 (예: 검정색)
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


// 2. 하이라이트 키워드와 색상을 정의하는 데이터 구조
struct HighlightKeyword: Identifiable, Codable, Hashable {
    var id = UUID()
    var keyword: String
    var color: CodableColor
    var isEnabled: Bool = true
    var isNotificationEnabled: Bool = false

    // color 프로퍼티를 직접 사용하기 위한 편의 프로퍼티
    var swiftUIColor: Color {
        get { color.color }
        set { color = CodableColor(color: newValue) }
    }
}

// 3. 하이라이트 설정을 관리하고 UserDefaults에 저장/로드하는 ViewModel
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

    // 기본값 설정
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
        // 저장된 데이터가 없으면 기본값 로드
        setDefaultKeywords()
    }

    // MARK: - 알림 기능

    private func requestNotificationPermission() {
        // 먼저 현재 권한 상태를 확인
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

        // 먼저 UNUserNotification 시도
        let content = UNMutableNotificationContent()
        content.title = "키워드 감지: \(keyword.keyword)"
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
                    // UNUserNotification이 실패하면 간단한 알림 창으로 폴백
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
            alert.messageText = "키워드 감지: \(keyword.keyword)"
            alert.informativeText = text.prefix(100).description + (text.count > 100 ? "..." : "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "확인")

            // 앱이 백그라운드에 있어도 알림이 표시되도록
            alert.runModal()
        }
    }

    private func showNotificationPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "알림 권한이 필요합니다"
            alert.informativeText = "키워드 알림 기능을 사용하려면 시스템 설정에서 PortPal의 알림 권한을 허용해주세요.\n\n시스템 설정 > 알림 및 집중 모드 > PortPal에서 '알림 허용'을 켜주세요."
            alert.alertStyle = .informational

            let openSettingsButton = alert.addButton(withTitle: "시스템 설정 열기")
            let cancelButton = alert.addButton(withTitle: "나중에")

            openSettingsButton.keyEquivalent = "\r" // Enter키
            cancelButton.keyEquivalent = "\u{1b}" // Escape키

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // 시스템 설정 열기
                self.openSystemNotificationSettings()
            }
        }
    }

    private func openSystemNotificationSettings() {
        // macOS Ventura 이상에서는 새로운 설정 앱 경로
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        } else {
            // 폴백: 일반 시스템 설정 열기
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
            // 기본 시스템 사운드 사용
            AudioServicesPlaySystemSound(SystemSoundID(1000)) // 시스템 기본 알림음
        }
    }

    // 수동으로 알림 권한 상태를 확인하는 함수 (UI에서 호출 가능)
    func checkNotificationPermission() {
        requestNotificationPermission()
    }
}
