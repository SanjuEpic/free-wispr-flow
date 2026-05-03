import Foundation

protocol TranscriptionProvider: AnyObject {
    /// Stable identifier used in settings persistence, e.g. "fluidaudio.parakeet.v3"
    var id: String { get }
    /// Human-readable name shown in the UI, e.g. "Parakeet v3 (multilingual)"
    var displayName: String { get }
    /// Called once at app launch or on provider change. Idempotent.
    func prepare() async throws
    /// Transcribe a WAV file at the recorder's native sample rate.
    func transcribe(audioFileURL: URL) async throws -> String
    /// Called when switching away from this provider. Releases models/processes.
    func teardown() async
}

enum TranscriptionProviderFactory {
    static func make(id: String, settings: SettingsManager) -> TranscriptionProvider {
        switch id {
        case "fluidaudio.parakeet.v3":
            return FluidAudioProvider(version: .v3)
        case "fluidaudio.parakeet.v2":
            return FluidAudioProvider(version: .v2)
        case "python.whisper":
            return PythonWhisperProvider(settings: settings)
        default:
            return FluidAudioProvider(version: .v3)
        }
    }
}
