import SwiftUI

struct HighlightSettingsView: View {
    @ObservedObject var settings: HighlightSettings

    var body: some View {
        VStack {
            List {
                ForEach($settings.keywords) { $keyword in
                    HStack {
                        Toggle(isOn: $keyword.isEnabled) {
                            TextField("Keyword", text: $keyword.keyword)
                        }
                        ColorPicker("", selection: $keyword.swiftUIColor)
                        Button(action: {
                            settings.remove(keyword: $keyword.wrappedValue)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button("Add New Keyword") {
                settings.addKeyword()
            }
            .padding()
        }
        .padding()
    }
}
