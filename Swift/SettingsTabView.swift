import SwiftUI

struct SettingsTabView: View {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var hotkeyRecorder = HotkeyRecorder()
    @State private var isDeveloperSettingsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header Section
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Configure your speech-to-text experience.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Basic Settings Section
                VStack(alignment: .leading, spacing: 16) {
                    // Provider picker
                    SettingRow(
                        label: "Transcription Provider",
                        description: "Choose the speech-to-text engine"
                    ) {
                        Picker("", selection: $settingsManager.transcriptionProviderID) {
                            Text("Parakeet v3 (multilingual)").tag("fluidaudio.parakeet.v3")
                            Text("Parakeet v2 (English)").tag("fluidaudio.parakeet.v2")
                            Text("Whisper (Python)").tag("python.whisper")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 220)
                        .onChange(of: settingsManager.transcriptionProviderID) { newValue in
                            settingsManager.updateTranscriptionProvider(newValue)
                        }
                    }

                    // Global Hotkey Setting
                    SettingRow(
                        label: "Global Hotkey",
                        description: "Keyboard shortcut to start/stop recording"
                    ) {
                        HStack(spacing: 8) {
                            if hotkeyRecorder.isRecording {
                                if hotkeyRecorder.isRecordingComplete {
                                    HStack(spacing: 8) {
                                        KeycapDisplay(hotkey: hotkeyRecorder.getRecordedKeysString())

                                        HStack(spacing: 4) {
                                            Button(action: {
                                                let (keyCode, modifiers) = hotkeyRecorder.getHotkeyConfiguration()
                                                settingsManager.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                                                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
                                                hotkeyRecorder.resetToDefaults()
                                                hotkeyRecorder.stopRecording()
                                            }) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 20, height: 20)
                                                    .background(Color.green)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.borderless)

                                            Button(action: {
                                                hotkeyRecorder.resetToDefaults()
                                                hotkeyRecorder.stopRecording()
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 20, height: 20)
                                                    .background(Color.red)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                } else {
                                    Text("Press keys...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            } else {
                                KeycapDisplay(hotkey: settingsManager.getHotkeyDisplayString())

                                Button(action: {
                                    hotkeyRecorder.startRecording()
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal, 24)

                // Developer Settings Section
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeveloperSettingsExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "wrench.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)

                            Text("Developer Settings")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Spacer()

                            Image(systemName: isDeveloperSettingsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    if isDeveloperSettingsExpanded {
                        VStack(alignment: .leading, spacing: 20) {
                            // Whisper sub-settings — only shown when Whisper provider is active
                            if settingsManager.transcriptionProviderID == "python.whisper" {
                                DeveloperSubsection(title: "Whisper Advanced", icon: "waveform") {
                                    VStack(spacing: 12) {
                                        SettingRow(label: "Model", description: "Whisper model size") {
                                            Picker("", selection: $settingsManager.pythonWhisper.model) {
                                                ForEach(["tiny", "base", "small", "medium", "large"], id: \.self) { m in
                                                    Text(m.capitalized).tag(m)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 120)
                                            .onChange(of: settingsManager.pythonWhisper.model) { _ in
                                                settingsManager.updateWhisperSettings()
                                            }
                                        }

                                        SettingRow(label: "Task", description: "Transcription task type") {
                                            Picker("", selection: $settingsManager.pythonWhisper.task) {
                                                ForEach(["transcribe", "translate"], id: \.self) { t in
                                                    Text(t.capitalized).tag(t)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 140)
                                            .onChange(of: settingsManager.pythonWhisper.task) { _ in
                                                settingsManager.updateWhisperSettings()
                                            }
                                        }

                                        SettingRow(label: "Language", description: "Audio language (auto-detect if not set)") {
                                            Picker("", selection: $settingsManager.pythonWhisper.language) {
                                                ForEach(["auto", "en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh"], id: \.self) { lang in
                                                    Text(languageDisplayName(lang)).tag(lang)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .frame(width: 140)
                                            .onChange(of: settingsManager.pythonWhisper.language) { _ in
                                                settingsManager.updateWhisperSettings()
                                            }
                                        }

                                        SettingRow(label: "Temperature", description: "Sampling temperature (0.0 to 1.0)") {
                                            HStack {
                                                Slider(value: $settingsManager.pythonWhisper.temperature, in: 0...1, step: 0.1)
                                                Text(String(format: "%.1f", settingsManager.pythonWhisper.temperature))
                                                    .font(.system(.body, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 30)
                                            }
                                            .onChange(of: settingsManager.pythonWhisper.temperature) { _ in
                                                settingsManager.updateWhisperSettings()
                                            }
                                        }
                                    }
                                }

                                DeveloperSubsection(title: "Server", icon: "server.rack") {
                                    VStack(spacing: 12) {
                                        SettingRow(label: "Host", description: "Server host address") {
                                            TextField("localhost", text: $settingsManager.pythonWhisper.serverHost)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 200)
                                        }

                                        SettingRow(label: "Port", description: "Server port number") {
                                            TextField("3001", value: $settingsManager.pythonWhisper.serverPort, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 100)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func languageDisplayName(_ code: String) -> String {
        switch code {
        case "auto": return "Auto-detect"
        case "en": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "ru": return "Russian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh": return "Chinese"
        default: return code.uppercased()
        }
    }
}

// MARK: - Helper Components

struct SettingRow<Content: View>: View {
    let label: String
    let description: String
    let content: Content

    init(label: String, description: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                content
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

struct DeveloperSubsection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding(.horizontal, 24)

            content
        }
    }
}

// MARK: - Keycap Display Component

struct KeycapDisplay: View {
    let hotkey: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(parseHotkeyComponents(hotkey), id: \.self) { component in
                KeycapView(symbol: component)
            }
        }
    }

    private func parseHotkeyComponents(_ hotkey: String) -> [String] {
        var components: [String] = []
        var currentComponent = ""

        for char in hotkey {
            if char.isLetter || char.isNumber {
                if !currentComponent.isEmpty {
                    components.append(currentComponent)
                    currentComponent = ""
                }
                components.append(String(char))
            } else {
                currentComponent += String(char)
            }
        }

        if !currentComponent.isEmpty {
            components.append(currentComponent)
        }

        return components
    }
}

struct KeycapView: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.9))
            .frame(minWidth: 32, minHeight: 32)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.3, green: 0.5, blue: 0.85),
                                    Color(red: 0.25, green: 0.45, blue: 0.8)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(-2)

                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.7, green: 0.85, blue: 0.95),
                                    Color(red: 0.6, green: 0.8, blue: 0.95)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.6),
                                    Color.white.opacity(0.0)
                                ]),
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

#Preview {
    SettingsTabView()
}
