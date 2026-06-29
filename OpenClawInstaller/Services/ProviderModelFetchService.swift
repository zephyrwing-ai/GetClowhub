import Foundation

struct ProviderModelFetchService {
    enum FetchError: LocalizedError {
        case invalidBaseURL
        case requestFailed(Int)
        case invalidResponse
        case noModels

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "Invalid provider base URL."
            case .requestFailed(let statusCode):
                return "Provider returned HTTP \(statusCode)."
            case .invalidResponse:
                return "Provider did not return an OpenAI-compatible model list."
            case .noModels:
                return "Provider returned no models."
            }
        }
    }

    func fetchModels(baseURL: String, apiKey: String) async throws -> [PresetModel] {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedBaseURL), components.scheme != nil else {
            throw FetchError.invalidBaseURL
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/v1") {
            path += "/models"
        } else if path.hasSuffix("/v1/models") {
            // Keep the path as-is.
        } else {
            path += "/v1/models"
        }
        components.path = path
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw FetchError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedApiKey.isEmpty {
            request.setValue("Bearer \(trimmedApiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.requestFailed(http.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]] else {
            throw FetchError.invalidResponse
        }

        let models = rows.compactMap { row -> PresetModel? in
            guard let id = row["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return PresetModel(
                id: id,
                name: id,
                reasoning: false,
                input: ["text"],
                cost: PresetModelCost(),
                contextWindow: 128000,
                maxTokens: 8192
            )
        }

        guard !models.isEmpty else {
            throw FetchError.noModels
        }
        return models
    }
}
