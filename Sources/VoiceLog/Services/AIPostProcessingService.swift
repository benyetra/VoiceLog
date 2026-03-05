import Foundation

// MARK: - ProcessingResult

/// The structured output from AI post-processing of a meeting transcript.
struct ProcessingResult: Codable, Equatable {
    let summary: String
    let actionItems: [String]
    let keyDecisions: [String]
    let suggestedTitle: String
}

// MARK: - AIPostProcessingError

enum AIPostProcessingError: LocalizedError {
    case ollamaUnavailable
    case openAIKeyMissing
    case requestFailed(String)
    case invalidResponse(String)
    case jsonParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .ollamaUnavailable:
            return "Ollama is not running. Start it with `ollama serve` or install from https://ollama.ai"
        case .openAIKeyMissing:
            return "OpenAI API key is not configured."
        case .requestFailed(let reason):
            return "AI processing request failed: \(reason)"
        case .invalidResponse(let detail):
            return "Invalid response from AI service: \(detail)"
        case .jsonParsingFailed(let detail):
            return "Failed to parse AI response as structured data: \(detail)"
        }
    }
}

// MARK: - AIPostProcessingService

final class AIPostProcessingService: ObservableObject {

    // MARK: - Configuration

    /// The Ollama model to use for local inference.
    var ollamaModel: String = "llama3.1"

    /// The OpenAI model to use for cloud inference.
    var openAIModel: String = "gpt-4o-mini"

    /// The user's OpenAI API key. Must be set before calling cloud processing.
    var openAIAPIKey: String?

    /// Base URL for the Ollama API.
    var ollamaBaseURL: String = "http://localhost:11434"

    /// Request timeout in seconds.
    var requestTimeout: TimeInterval = 300

    // MARK: - Prompt

    private func buildPrompt(transcript: String) -> String {
        """
        You are a meeting notes assistant. Given the following meeting transcript, extract:
        1. A concise 3-5 sentence summary
        2. A list of action items with implied owners
        3. Key decisions made
        4. A concise meeting title (5-8 words)

        Respond ONLY in JSON format with these exact keys: title, summary, action_items (array of strings), key_decisions (array of strings).

        Do not include any text before or after the JSON object.

        Transcript:
        \(transcript)
        """
    }

    // MARK: - Ollama Availability

    /// Checks if the Ollama server is running and reachable.
    func isOllamaAvailable() async -> Bool {
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Process Transcript

    /// Processes a meeting transcript through either a local LLM (Ollama) or OpenAI's API.
    /// - Parameters:
    ///   - transcript: The full meeting transcript text.
    ///   - useLocalLLM: If true, uses Ollama locally. If false, uses OpenAI API.
    /// - Returns: A structured ProcessingResult with summary, action items, decisions, and title.
    func processTranscript(_ transcript: String, useLocalLLM: Bool) async throws -> ProcessingResult {
        let prompt = buildPrompt(transcript: transcript)
        let rawJSON: String

        if useLocalLLM {
            rawJSON = try await callOllama(prompt: prompt)
        } else {
            rawJSON = try await callOpenAI(prompt: prompt)
        }

        return try parseResponse(rawJSON)
    }

    // MARK: - Ollama API

    private func callOllama(prompt: String) async throws -> String {
        guard await isOllamaAvailable() else {
            throw AIPostProcessingError.ollamaUnavailable
        }

        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else {
            throw AIPostProcessingError.requestFailed("Invalid Ollama URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        let body: [String: Any] = [
            "model": ollamaModel,
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": [
                "temperature": 0.3,
                "num_predict": 2048,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIPostProcessingError.requestFailed("No HTTP response received.")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            throw AIPostProcessingError.requestFailed(
                "Ollama returned status \(httpResponse.statusCode): \(responseBody)"
            )
        }

        // Ollama's non-streaming response has a "response" field with the generated text
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String
        else {
            throw AIPostProcessingError.invalidResponse(
                "Could not extract 'response' field from Ollama output."
            )
        }

        return responseText
    }

    // MARK: - OpenAI API

    private func callOpenAI(prompt: String) async throws -> String {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            throw AIPostProcessingError.openAIKeyMissing
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIPostProcessingError.requestFailed("Invalid OpenAI URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = requestTimeout

        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a meeting notes assistant. Always respond with valid JSON only.",
                ],
                [
                    "role": "user",
                    "content": prompt,
                ],
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
            "response_format": ["type": "json_object"],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIPostProcessingError.requestFailed("No HTTP response received.")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            throw AIPostProcessingError.requestFailed(
                "OpenAI returned status \(httpResponse.statusCode): \(responseBody)"
            )
        }

        // Parse the ChatCompletion response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw AIPostProcessingError.invalidResponse(
                "Could not extract message content from OpenAI response."
            )
        }

        return content
    }

    // MARK: - Response Parsing

    /// Parses the raw JSON string from the LLM into a structured ProcessingResult.
    private func parseResponse(_ rawJSON: String) throws -> ProcessingResult {
        // The LLM may wrap JSON in markdown code fences; strip them
        let cleaned = stripCodeFences(rawJSON)

        guard let data = cleaned.data(using: .utf8) else {
            throw AIPostProcessingError.jsonParsingFailed("Could not encode response as UTF-8.")
        }

        // Try to parse with exact field names first
        do {
            let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
            return ProcessingResult(
                summary: decoded.summary,
                actionItems: decoded.actionItems,
                keyDecisions: decoded.keyDecisions,
                suggestedTitle: decoded.title
            )
        } catch {
            // Fallback: try manual JSON parsing for flexibility with key naming
            return try parseResponseManually(data: data, rawJSON: cleaned)
        }
    }

    /// Manual JSON parsing as a fallback when strict Codable decoding fails.
    private func parseResponseManually(data: Data, rawJSON: String) throws -> ProcessingResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIPostProcessingError.jsonParsingFailed(
                "Response is not valid JSON. Raw: \(rawJSON.prefix(500))"
            )
        }

        let title = json["title"] as? String
            ?? json["suggested_title"] as? String
            ?? "Untitled Meeting"

        let summary = json["summary"] as? String
            ?? "No summary available."

        let actionItems = json["action_items"] as? [String]
            ?? json["actionItems"] as? [String]
            ?? []

        let keyDecisions = json["key_decisions"] as? [String]
            ?? json["keyDecisions"] as? [String]
            ?? []

        return ProcessingResult(
            summary: summary,
            actionItems: actionItems,
            keyDecisions: keyDecisions,
            suggestedTitle: title
        )
    }

    /// Strips markdown code fences (```json ... ```) from LLM output.
    private func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading ```json or ```
        if result.hasPrefix("```json") {
            result = String(result.dropFirst(7))
        } else if result.hasPrefix("```") {
            result = String(result.dropFirst(3))
        }

        // Remove trailing ```
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - LLMResponse (Codable)

/// Internal Codable model matching the expected JSON structure from the LLM.
private struct LLMResponse: Codable {
    let title: String
    let summary: String
    let actionItems: [String]
    let keyDecisions: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case actionItems = "action_items"
        case keyDecisions = "key_decisions"
    }
}
