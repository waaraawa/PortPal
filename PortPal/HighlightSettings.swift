import SwiftUI
import Combine

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
}
