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

// MARK: - Serialization schema (written to disk)

private struct SerializedAppConfig: Codable {
    var provider: String
    var fluidAudio: FluidAudioSettings
    var hotkey: HotkeyConfig

    enum CodingKeys: String, CodingKey {
        case provider
        case fluidAudio = "fluid_audio"
        case hotkey
    }
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
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {

    // MARK: - Published Properties

    @Published var transcriptionProviderID: String = "fluidaudio.parakeet.v3"
    @Published var fluidAudio: FluidAudioSettings = .init()

    @Published var hotkeyKeyCode: Int = 37  // L key
    @Published var hotkeyModifiers: [String] = ["option"]
    @Published var providerStatus: String = "Loading…"

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

    // MARK: - Utility

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
        guard let config = try? decoder.decode(SerializedAppConfig.self, from: yamlString) else {
            logger.log("Unrecognized settings format, applying defaults", level: .info)
            setDefaultSettings()
            return
        }
        transcriptionProviderID = config.provider
        fluidAudio = config.fluidAudio
        hotkeyKeyCode = config.hotkey.keyCode
        hotkeyModifiers = config.hotkey.modifiers
        if transcriptionProviderID == "python.whisper" {
            transcriptionProviderID = "fluidaudio.parakeet.v3"
            saveSettings()
        }
    }

    private func setDefaultSettings() {
        transcriptionProviderID = "fluidaudio.parakeet.v3"
        fluidAudio = FluidAudioSettings()
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

