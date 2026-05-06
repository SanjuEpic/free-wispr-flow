import SwiftUI

struct SettingsTabView: View {
    @ObservedObject var settings: SettingsManager
    @StateObject private var hotkeyRecorder = HotkeyRecorder()
    @Environment(\.colorScheme) var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.windowBackground(for: scheme).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                transcriptionSection
                Spacer().frame(height: 28)
                hotkeySection
                Spacer().frame(height: 28)
                aboutSection
                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onChange(of: hotkeyRecorder.isRecordingComplete) { _, complete in
            guard complete else { return }
            let (keyCode, modifiers) = hotkeyRecorder.getHotkeyConfiguration()
            settings.updateHotkey(keyCode: keyCode, modifiers: modifiers)
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
            hotkeyRecorder.stopRecording()
        }
    }

    // MARK: - Sections

    private var transcriptionSection: some View {
        SectionBlock(label: "Transcription") {
            SettingsCard(scheme: scheme) {
                SettingRow(label: "Provider", scheme: scheme) {
                    ProviderMenu(selection: $settings.transcriptionProviderID, scheme: scheme) {
                        settings.updateTranscriptionProvider($0)
                    }
                }
                RowDivider(scheme: scheme)
                SettingRow(label: "Model status", scheme: scheme) {
                    Text(settings.providerStatus)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary(for: scheme))
                }
            }
        }
    }

    private var hotkeySection: some View {
        SectionBlock(label: "Hotkey") {
            SettingsCard(scheme: scheme) {
                SettingRow(label: "Recording shortcut", scheme: scheme) {
                    if hotkeyRecorder.isRecording {
                        Text("Press your shortcut…")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary(for: scheme))
                    } else {
                        HStack(spacing: 6) {
                            KeycapsView(hotkey: settings.getHotkeyDisplayString(), scheme: scheme)
                            Button("Change") { hotkeyRecorder.startRecording() }
                                .font(.system(size: 12))
                                .foregroundColor(.accentLink(for: scheme))
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        SectionBlock(label: "About") {
            SettingsCard(scheme: scheme) {
                HStack(spacing: 14) {
                    Text("uttr")
                        .font(.system(size: 22, weight: .medium))
                        .tracking(-0.88)
                        .foregroundColor(.textPrimary(for: scheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(appVersion)")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary(for: scheme))
                        Text("github.com/Rakk301/homebrew-uttr")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary(for: scheme))
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

}

// MARK: - Section scaffold

private struct SectionBlock<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 11))
                .tracking(0.44)
                .foregroundColor(.textTertiary(for: scheme))
                .padding(.leading, 4)
            content
        }
    }
}

// MARK: - Card

private struct SettingsCard<Content: View>: View {
    let scheme: ColorScheme
    let content: Content

    init(scheme: ColorScheme, @ViewBuilder content: () -> Content) {
        self.scheme = scheme
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cardBackground(for: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.cardBorder(for: scheme), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Row

private struct SettingRow<Content: View>: View {
    let label: String
    var indent: CGFloat = 0
    let scheme: ColorScheme
    let content: Content

    init(label: String, indent: CGFloat = 0, scheme: ColorScheme, @ViewBuilder content: () -> Content) {
        self.label = label
        self.indent = indent
        self.scheme = scheme
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary(for: scheme))
                .padding(.leading, indent)
            Spacer()
            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct RowDivider: View {
    let scheme: ColorScheme
    var body: some View {
        Rectangle()
            .fill(Color.rowSeparator(for: scheme))
            .frame(height: 0.5)
    }
}

// MARK: - Provider picker

private struct ProviderMenu: View {
    @Binding var selection: String
    let scheme: ColorScheme
    let onChange: (String) -> Void

    private let options: [(String, String)] = [
        ("fluidaudio.parakeet.v3", "Parakeet v3 — multilingual"),
        ("fluidaudio.parakeet.v2", "Parakeet v2 — English only"),
    ]

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { tag, label in
                Button(label) { selection = tag; onChange(tag) }
            }
        } label: {
            pickerLabel(options.first(where: { $0.0 == selection })?.1 ?? "", minWidth: 220)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func pickerLabel(_ text: String, minWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary(for: scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10))
                .foregroundColor(
                    scheme == .dark
                    ? Color(hex: 0xF5F1EA, opacity: 0.55)
                    : Color(hex: 0x1F1D1A, opacity: 0.60)
                )
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minWidth: minWidth)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.pickerBackground(for: scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.pickerBorder(for: scheme), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Keycaps

private struct KeycapsView: View {
    let hotkey: String
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keycaps.enumerated()), id: \.offset) { i, cap in
                if i > 0 {
                    Text("+")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary(for: scheme))
                }
                KeycapView(symbol: cap, scheme: scheme)
            }
        }
    }

    private var keycaps: [String] {
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        var result: [String] = []
        var keyStart = hotkey.startIndex
        for idx in hotkey.indices {
            guard modifiers.contains(hotkey[idx]) else { break }
            result.append(String(hotkey[idx]))
            keyStart = hotkey.index(after: idx)
        }
        let key = String(hotkey[keyStart...])
        if !key.isEmpty { result.append(key) }
        return result
    }
}

private struct KeycapView: View {
    let symbol: String
    let scheme: ColorScheme

    var body: some View {
        Text(symbol)
            .font(.system(size: 13))
            .foregroundColor(.textPrimary(for: scheme))
            .frame(minWidth: 32, minHeight: 26)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.keycapFace(for: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.keycapBorder(for: scheme), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 0, x: 0, y: 1)
            )
    }
}

#Preview {
    SettingsTabView(settings: SettingsManager())
        .frame(width: 520, height: 480)
}
