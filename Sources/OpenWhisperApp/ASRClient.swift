import Foundation

final class ASRClient {
    private let endpoint: URL
    private let session: URLSession

    init(endpoint: URL? = nil) {
        if let endpoint {
            self.endpoint = endpoint
        } else if let env = ProcessInfo.processInfo.environment["DICTATION_ASR_ENDPOINT"], let url = URL(string: env) {
            self.endpoint = url
        } else {
            self.endpoint = URL(string: "http://127.0.0.1:8765/transcribe")!
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    private struct Response: Decodable {
        let text: String
    }

    func transcribe(audioFileURL: URL, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try buildBody(audioFileURL: audioFileURL, boundary: boundary)
        } catch {
            completion(.failure(error))
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(domain: "ASRClient", code: -1)))
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                completion(.failure(NSError(domain: "ASRClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                completion(.success(decoded.text))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    private func buildBody(audioFileURL: URL, boundary: String) throws -> Data {
        let audioData = try Data(contentsOf: audioFileURL)
        let filename = audioFileURL.lastPathComponent

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
