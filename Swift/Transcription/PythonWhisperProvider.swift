import Foundation

class PythonWhisperProvider: TranscriptionProvider {
    private let settings: SettingsManager
    private var server: TranscriptionServer?
    private let logger = Logger(componentName: "PythonWhisperProvider")
    private let session = URLSession.shared
    private let timeoutInterval: TimeInterval = 30.0

    var id: String { "python.whisper" }
    var displayName: String { "Whisper (Python)" }

    init(settings: SettingsManager) {
        self.settings = settings
    }

    func prepare() async throws {
        logger.log("Starting Python Whisper server…", level: .info)
        let server = TranscriptionServer(settingsManager: settings)
        self.server = server
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.startServer { success in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PythonWhisperProviderError.serverFailedToStart)
                }
            }
        }
        logger.log("Python Whisper server ready", level: .info)
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw PythonWhisperProviderError.audioFileNotFound
        }

        let baseURL = settings.getServerURL()
        guard let url = URL(string: "\(baseURL)/transcribe") else {
            throw PythonWhisperProviderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        request.httpBody = try JSONSerialization.data(withJSONObject: ["audio_path": audioFileURL.path])

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PythonWhisperProviderError.invalidResponse
        }
        if let errorMessage = json["error"] as? String {
            throw PythonWhisperProviderError.serverError(errorMessage)
        }
        guard let transcription = json["transcription"] as? String else {
            throw PythonWhisperProviderError.invalidResponse
        }
        return transcription
    }

    func teardown() async {
        server?.stopServer()
        server = nil
        logger.log("Python Whisper server stopped", level: .info)
    }
}

enum PythonWhisperProviderError: Error, LocalizedError {
    case serverFailedToStart
    case audioFileNotFound
    case invalidURL
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverFailedToStart: return "Python transcription server failed to start"
        case .audioFileNotFound:   return "Audio file not found"
        case .invalidURL:          return "Invalid server URL"
        case .invalidResponse:     return "Invalid response from transcription server"
        case .serverError(let m):  return "Server error: \(m)"
        }
    }
}
