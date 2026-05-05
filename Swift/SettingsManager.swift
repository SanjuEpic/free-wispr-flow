import Foundation
import SwiftUI
import Yams
import Carbon

// MARK: - New settings structs

struct FluidAudioSettings: Codable {
    var modelVersion: String = "v3"

    enum CodingKeys: String, CodingKey {
        case modelVersion = "model_version"
    }
}

struct PythonWhisperSettings: Codable {
    var model: String = "small"
    var task: String = "transcribe"
    var language: String = "auto"
    var temperature: Float = 0.0
    var serverHost: String = "localhost"
    var serverPort: Int = 3001
    var uvPath: String = "/opt/homebrew/bin/uv"

    enum CodingKeys: String, CodingKey {
        case model, task, language, temperature
        case serverHost = "server_host"
        case serverPort = "server_port"
        case uvPath = "uv_path"
    }
}

// MARK: - Serialization schema (written to disk)

private struct SerializedAppConfig: Codable {
    var provider: String
    var fluidAudio: FluidAudioSettings
    var pythonWhisper: PythonWhisperSettings
    var hotkey: HotkeyConfig

    enum CodingKeys: String, CodingKey {
        case provider
        case fluidAudio = "fluid_audio"
        case pythonWhisper = "python_whisper"
        case hotkey
    }
}

// MARK: - Legacy schema (migration only)

private struct LegacyHotkeyConfig: Codable {
    var keyCode: Int
    var modifiers: [String]

    enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case modifiers
    }
}

private struct LegacyWhisperConfig: Codable {
    var model: String
    var task: String
    var language: String
    var temperature: Float
}

private struct LegacyServerConfig: Codable {
    var host: String
    var port: Int
    var uvPath: String?

    enum CodingKeys: String, CodingKey {
        case host, port
        case uvPath = "uv_path"
    }
}

private struct LegacyAppConfig: Codable {
    var whisper: LegacyWhisperConfig
    var hotkey: LegacyHotkeyConfig
    var server: LegacyServerConfig?
}

// MARK: - Hotkey config (shared schema)

struct HotkeyConfig: Codable {
    var keyCode: Int
    var modifiers: [String]

    enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case modifiers
    }
}

// MARK: - Settings Change Notifications

extension Notification.Name {
    static let transcriptionProviderChanged = Notification.Name("transcriptionProviderChanged")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
    // Legacy names kept so existing callers still compile during transition
    static let whisperModelChanged = Notification.Name("whisperModelChanged")
    static let whisperSettingsChanged = Notification.Name("whisperSettingsChanged")
    static let serverSettingsChanged = Notification.Name("serverSettingsChanged")
    static let whisperModelReloaded = Notification.Name("whisperModelReloaded")
    static let sttProviderChanged = Notification.Name("sttProviderChanged")
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {

    // MARK: - Published Properties

    @Published var transcriptionProviderID: String = "fluidaudio.parakeet.v3"
    @Published var fluidAudio: FluidAudioSettings = .init()
    @Published var pythonWhisper: PythonWhisperSettings = .init()

    @Published var hotkeyKeyCode: Int = 37  // L key
    @Published var hotkeyModifiers: [String] = ["option"]
    @Published var providerStatus: String = "Loading…"

    // MARK: - Derived accessors used by TranscriptionServer

    var serverHost: String {
        get { pythonWhisper.serverHost }
        set { pythonWhisper.serverHost = newValue }
    }
    var serverPort: Int {
        get { pythonWhisper.serverPort }
        set { pythonWhisper.serverPort = newValue }
    }
    var uvPath: String {
        get { pythonWhisper.uvPath }
        set { pythonWhisper.uvPath = newValue }
    }

    // MARK: - Properties

    let configFileURL: URL
    private let logger = Logger()

    // MARK: - Initialization

    init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("uttr")
        configFileURL = appSupportURL.appendingPathComponent("settings.yaml")
        logger.log("Using config file at: \(configFileURL.path)", level: .debug)
        loadSettings()
    }

    // MARK: - Load / Save

    func loadSettings() {
        logger.log("Loading settings from: \(configFileURL.path)", level: .debug)

        if FileManager.default.fileExists(atPath: configFileURL.path) {
            do {
                let data = try Data(contentsOf: configFileURL)
                if let yamlString = String(data: data, encoding: .utf8) {
                    try parseYAMLSettings(yamlString)
                    logger.log("Settings loaded successfully", level: .debug)
                }
            } catch {
                logger.logError(error, context: "Failed to load settings")
                setDefaultSettings()
            }
        } else {
            logger.log("No settings file found, creating defaults", level: .debug)
            setDefaultSettings()
            saveSettings()
        }
    }

    func saveSettings() {
        logger.log("Saving settings to: \(configFileURL.path)", level: .debug)

        do {
            let config = SerializedAppConfig(
                provider: transcriptionProviderID,
                fluidAudio: fluidAudio,
                pythonWhisper: pythonWhisper,
                hotkey: HotkeyConfig(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
            )

            let encoder = YAMLEncoder()
            let yamlContent = try encoder.encode(config)

            let configDir = configFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            try yamlContent.write(to: configFileURL, atomically: true, encoding: .utf8)
            logger.log("Settings saved successfully", level: .info)
        } catch {
            logger.logError(error, context: "Failed to save settings")
        }
    }

    // MARK: - Update Methods

    func updateTranscriptionProvider(_ providerID: String) {
        transcriptionProviderID = providerID
        NotificationCenter.default.post(name: .transcriptionProviderChanged, object: self)
        logger.log("Transcription provider changed to: \(providerID)", level: .info)
        saveSettings()
    }

    func updateHotkey(keyCode: Int, modifiers: [String]) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        NotificationCenter.default.post(name: .hotkeyChanged, object: self)
        logger.log("Hotkey changed", level: .info)
        saveSettings()
    }

    func updateWhisperSettings() {
        NotificationCenter.default.post(name: .transcriptionProviderChanged, object: self)
        saveSettings()
    }

    // MARK: - Utility

    func getServerURL() -> String {
        "http://\(pythonWhisper.serverHost):\(pythonWhisper.serverPort)"
    }

    func getHotkeyDisplayString() -> String {
        var display = ""
        if hotkeyModifiers.contains("command") { display += "⌘" }
        if hotkeyModifiers.contains("shift")   { display += "⇧" }
        if hotkeyModifiers.contains("option")  { display += "⌥" }
        if hotkeyModifiers.contains("control") { display += "⌃" }
        display += keyCodeToCharacter(hotkeyKeyCode)
        return display
    }

    // MARK: - Private

    private func parseYAMLSettings(_ yamlString: String) throws {
        let decoder = YAMLDecoder()

        // Try new schema first (recognised by presence of `provider:` key)
        if let newConfig = try? decoder.decode(SerializedAppConfig.self, from: yamlString) {
            transcriptionProviderID = newConfig.provider
            fluidAudio = newConfig.fluidAudio
            pythonWhisper = newConfig.pythonWhisper
            hotkeyKeyCode = newConfig.hotkey.keyCode
            hotkeyModifiers = newConfig.hotkey.modifiers
            return
        }

        // Legacy schema: migrate and write new shape
        if let legacy = try? decoder.decode(LegacyAppConfig.self, from: yamlString) {
            logger.log("Migrating legacy settings to new schema", level: .info)
            transcriptionProviderID = "fluidaudio.parakeet.v3"
            fluidAudio = FluidAudioSettings()
            pythonWhisper = PythonWhisperSettings(
                model: legacy.whisper.model,
                task: legacy.whisper.task,
                language: legacy.whisper.language,
                temperature: legacy.whisper.temperature,
                serverHost: legacy.server?.host ?? "localhost",
                serverPort: legacy.server?.port ?? 3001,
                uvPath: legacy.server?.uvPath ?? "/opt/homebrew/bin/uv"
            )
            hotkeyKeyCode = legacy.hotkey.keyCode
            hotkeyModifiers = legacy.hotkey.modifiers
            saveSettings()
            return
        }

        throw SettingsLoadError.unrecognizedFormat
    }

    private func setDefaultSettings() {
        transcriptionProviderID = "fluidaudio.parakeet.v3"
        fluidAudio = FluidAudioSettings()
        pythonWhisper = PythonWhisperSettings()
        hotkeyKeyCode = 37
        hotkeyModifiers = ["option"]
        logger.log("Default settings applied", level: .info)
    }

    private func keyCodeToCharacter(_ keyCode: Int) -> String {
        switch keyCode {
        case 0: return "A";  case 1: return "S";  case 2: return "D";  case 3: return "F"
        case 4: return "H";  case 5: return "G";  case 6: return "Z";  case 7: return "X"
        case 8: return "C";  case 9: return "V";  case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
        case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
        case 45: return "N"; case 46: return "M"
        case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
        case 22: return "6"; case 23: return "5"; case 25: return "9"; case 26: return "7"
        case 28: return "8"; case 29: return "0"
        case 24: return "="; case 27: return "-"; case 30: return "]"; case 33: return "["
        case 39: return "'"; case 41: return ";"; case 42: return "\\"
        case 43: return ","; case 44: return "/"; case 47: return "."; case 50: return "`"
        case 49: return "Space"; case 36: return "↵"; case 48: return "⇥"
        case 51: return "⌫";    case 53: return "⎋"; case 117: return "⌦"
        default: return "?"
        }
    }
}

enum SettingsLoadError: Error {
    case unrecognizedFormat
}
