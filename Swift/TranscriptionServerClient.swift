import Foundation

enum TranscriptionServerError: Error, LocalizedError {
    case serverNotRunning
    case invalidResponse
    case networkError(Error)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Transcription server is not running"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

class TranscriptionServerClient {
    
    // MARK: - Properties
    private let settingsManager: SettingsManager
    private let logger = Logger(componentName: "TranscriptionServerClient")
    private let session = URLSession.shared
    private let timeoutInterval: TimeInterval = 30.0
    
    // MARK: - Initialization
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }
    
    // MARK: - Public Methods
    
    /// Switch the STT provider on the server
    func switchProvider(_ provider: String, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.log("Switching STT provider to: \(provider)", level: .info)
        
        let baseURL = settingsManager.getServerURL()
        guard let url = URL(string: "\(baseURL)/switch_provider") else {
            completion(.failure(TranscriptionServerError.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        
        let requestBody = ["provider": provider]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(TranscriptionServerError.networkError(error)))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(TranscriptionServerError.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(TranscriptionServerError.invalidResponse))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let errorMessage = json?["error"] as? String {
                    completion(.failure(TranscriptionServerError.serverError(errorMessage)))
                    return
                }
                
                self.logger.log("Successfully switched to provider: \(provider)", level: .info)
                completion(.success(()))
            } catch {
                completion(.failure(TranscriptionServerError.invalidResponse))
            }
        }
        task.resume()
    }
    
    func transcribeAudio(_ audioFileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        logger.log("Starting transcription for: \(audioFileURL.path)", level: .info)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            completion(.failure(TranscriptionServerError.serverError("Audio file not found")))
            return
        }
        
        // Create request using settings
        let baseURL = settingsManager.getServerURL()
        guard let url = URL(string: "\(baseURL)/transcribe") else {
            completion(.failure(TranscriptionServerError.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        
        // Create request body
        let requestBody = ["audio_path": audioFileURL.path]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(TranscriptionServerError.networkError(error)))
            return
        }
        
        // Make request (assume server was started by ServerManager; errors will surface here)
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(TranscriptionServerError.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(TranscriptionServerError.invalidResponse))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let errorMessage = json?["error"] as? String {
                    completion(.failure(TranscriptionServerError.serverError(errorMessage)))
                    return
                }
                
                if let transcription = json?["transcription"] as? String {
                    self.logger.log("Transcription successful: \(transcription)", level: .info)
                    completion(.success(transcription))
                } else {
                    completion(.failure(TranscriptionServerError.invalidResponse))
                }
            } catch {
                completion(.failure(TranscriptionServerError.invalidResponse))
            }
        }
        task.resume()
    }
} 