import SwiftUI

struct HighlightSettingsView: View {
    @ObservedObject var settings: HighlightSettings

    var body: some View {
        VStack(spacing: 4) {
            Button("Add New Keyword") {
                settings.addKeyword()
            }
            .padding(.vertical, 4)

            List {
                ForEach($settings.keywords) { $keyword in
                    HStack {
                        Toggle("", isOn: $keyword.isEnabled)
                            .toggleStyle(.checkbox)

                        TextField("Keyword", text: $keyword.keyword)
                            .textFieldStyle(.plain)

                        Rectangle()
                            .fill(keyword.swiftUIColor)
                            .frame(width: 16, height: 16)
                            .overlay(
                                ColorPicker("", selection: $keyword.swiftUIColor)
                                    .labelsHidden()
                                    .opacity(0.01)
                            )

                        Button(action: {
                            keyword.isNotificationEnabled.toggle()
                        }) {
                            Image(systemName: keyword.isNotificationEnabled ? "bell.fill" : "bell.slash")
                                .foregroundColor(keyword.isNotificationEnabled ? .blue : .gray)
                        }
                        .buttonStyle(.plain)
                        .help(keyword.isNotificationEnabled ? "Disable notifications" : "Enable notifications")

                        Button(action: {
                            settings.remove(keyword: $keyword.wrappedValue)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete keyword")
                    }
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 6)
    }
}
