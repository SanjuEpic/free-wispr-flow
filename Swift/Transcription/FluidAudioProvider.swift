import Foundation
import FluidAudio

enum ParakeetVersion {
    case v2, v3

    var asrVersion: AsrModelVersion {
        switch self {
        case .v2: return .v2
        case .v3: return .v3
        }
    }

    var displayName: String {
        switch self {
        case .v2: return "Parakeet v2 (English)"
        case .v3: return "Parakeet v3 (multilingual)"
        }
    }
}

class FluidAudioProvider: TranscriptionProvider {
    private let version: ParakeetVersion
    private var asr: AsrManager?
    private let logger = Logger(componentName: "FluidAudioProvider")

    var id: String {
        switch version {
        case .v2: return "fluidaudio.parakeet.v2"
        case .v3: return "fluidaudio.parakeet.v3"
        }
    }

    var displayName: String { version.displayName }

    init(version: ParakeetVersion) {
        self.version = version
    }

    func prepare() async throws {
        logger.log("Downloading/loading \(version.displayName) models…", level: .info)
        let models = try await AsrModels.downloadAndLoad(version: version.asrVersion)
        asr = AsrManager(config: .default, models: models)
        logger.log("\(displayName) ready", level: .info)
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        guard let asr else {
            throw FluidAudioProviderError.notPrepared
        }
        var decoderState = TdtDecoderState.make()
        let result = try await asr.transcribe(audioFileURL, decoderState: &decoderState)
        return result.text
    }

    func teardown() async {
        if let asr {
            await asr.cleanup()
        }
        asr = nil
        logger.log("\(displayName) torn down", level: .info)
    }
}

enum FluidAudioProviderError: Error, LocalizedError {
    case notPrepared

    var errorDescription: String? {
        "FluidAudio provider is not prepared — call prepare() first."
    }
}
