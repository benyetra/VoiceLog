import AppKit
import Foundation

// MARK: - NotionDatabase

struct NotionDatabase: Identifiable, Codable {
    let id: String
    let title: String
    let url: String?
}

// MARK: - NotionError

enum NotionError: LocalizedError {
    case notAuthenticated
    case invalidResponse(statusCode: Int)
    case rateLimited(retryAfter: TimeInterval)
    case tokenExchangeFailed(String)
    case schemaValidationFailed(String)
    case encodingFailed
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Notion. Please connect your account."
        case .invalidResponse(let statusCode):
            return "Notion API returned status code \(statusCode)."
        case .rateLimited(let retryAfter):
            return "Rate limited by Notion. Retry after \(Int(retryAfter)) seconds."
        case .tokenExchangeFailed(let reason):
            return "OAuth token exchange failed: \(reason)"
        case .schemaValidationFailed(let reason):
            return "Database schema validation failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode request body."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - NotionService

@MainActor
final class NotionService: ObservableObject {

    // MARK: - Published Properties

    @Published var isConnected: Bool = false
    @Published var workspaceName: String?

    // MARK: - Constants

    private static let baseURL = "https://api.notion.com/v1"
    private static let notionVersion = "2022-06-28"
    private static let clientId = "YOUR_NOTION_CLIENT_ID" // Replace with actual client ID
    private static let clientSecret = "YOUR_NOTION_CLIENT_SECRET" // Replace with actual client secret
    private static let redirectURI = "http://localhost:19284/notion/callback"

    private static let keychainTokenKey = "notion_access_token"
    private static let keychainWorkspaceKey = "notion_workspace_name"

    // MARK: - Private Properties

    private let session: URLSession
    private let keychain: KeychainService
    private var pendingSyncQueue: [MeetingRecord] = []

    private let maxRetries = 5
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Init

    init(session: URLSession = .shared, keychain: KeychainService = .shared) {
        self.session = session
        self.keychain = keychain

        // Restore connection state from Keychain
        if let token = keychain.retrieve(key: Self.keychainTokenKey), !token.isEmpty {
            self.isConnected = true
            self.workspaceName = keychain.retrieve(key: Self.keychainWorkspaceKey)
        }
    }

    // MARK: - OAuth

    /// Opens the Notion OAuth authorization URL in the default browser.
    func startOAuth() {
        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Exchanges an OAuth authorization code for an access token.
    func handleOAuthCallback(code: String) async throws {
        let url = URL(string: "\(Self.baseURL)/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Notion requires Basic auth with client_id:client_secret for token exchange
        let credentials = "\(Self.clientId):\(Self.clientSecret)"
        guard let credentialData = credentials.data(using: .utf8) else {
            throw NotionError.encodingFailed
        }
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NotionError.tokenExchangeFailed("Status \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NotionError.tokenExchangeFailed("Missing access_token in response")
        }

        let workspace = json["workspace_name"] as? String

        // Persist token and workspace name in Keychain
        keychain.save(key: Self.keychainTokenKey, value: accessToken)
        if let workspace {
            keychain.save(key: Self.keychainWorkspaceKey, value: workspace)
        }

        isConnected = true
        workspaceName = workspace
    }

    /// Disconnects from Notion by removing stored tokens.
    func disconnect() {
        keychain.delete(key: Self.keychainTokenKey)
        keychain.delete(key: Self.keychainWorkspaceKey)
        isConnected = false
        workspaceName = nil
    }

    // MARK: - Databases

    /// Lists all databases the integration has access to.
    func listDatabases() async throws -> [NotionDatabase] {
        let request = try authenticatedRequest(
            path: "/search",
            method: "POST",
            body: [
                "filter": ["value": "database", "property": "object"]
            ]
        )

        let (data, response) = try await performRequestWithRetry(request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { result in
            guard let id = result["id"] as? String else { return nil }

            // Extract title from the title array
            var title = "Untitled"
            if let titleArray = result["title"] as? [[String: Any]],
               let firstTitle = titleArray.first,
               let plainText = firstTitle["plain_text"] as? String {
                title = plainText
            }

            let url = result["url"] as? String
            return NotionDatabase(id: id, title: title, url: url)
        }
    }

    /// Creates a pre-configured "Meeting Log" database under the given parent page.
    func createMeetingDatabase(parentPageId: String?) async throws -> String {
        let pageId = parentPageId ?? "root"
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": pageId],
            "title": [
                ["type": "text", "text": ["content": "Meeting Log"]]
            ],
            "properties": [
                "Title": ["title": [String: Any]()],
                "Date": ["date": [String: Any]()],
                "Duration (min)": ["number": ["format": "number"]],
                "Summary": ["rich_text": [String: Any]()],
                "Status": [
                    "select": [
                        "options": [
                            ["name": "Draft", "color": "gray"],
                            ["name": "Reviewed", "color": "green"],
                            ["name": "Archived", "color": "blue"],
                        ]
                    ]
                ],
                "Whisper Model": [
                    "select": [
                        "options": [
                            ["name": "tiny", "color": "gray"],
                            ["name": "base", "color": "yellow"],
                            ["name": "small", "color": "orange"],
                            ["name": "medium", "color": "green"],
                            ["name": "large", "color": "blue"],
                        ]
                    ]
                ],
            ],
        ]

        let request = try authenticatedRequest(
            path: "/databases",
            method: "POST",
            body: body
        )

        let (data, response) = try await performRequestWithRetry(request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let databaseId = json["id"] as? String else {
            throw NotionError.invalidResponse(statusCode: 0)
        }

        return databaseId
    }

    /// Validates that a database has the required properties for meeting storage.
    func validateSchema(databaseId: String) async throws -> Bool {
        let request = try authenticatedRequest(
            path: "/databases/\(databaseId)",
            method: "GET"
        )

        let (data, response) = try await performRequestWithRetry(request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = json["properties"] as? [String: Any] else {
            throw NotionError.schemaValidationFailed("Could not read database properties")
        }

        // Check for required property types
        let requiredProperties: [String: String] = [
            "Title": "title",
            "Date": "date",
            "Duration (min)": "number",
            "Summary": "rich_text",
            "Status": "select",
            "Whisper Model": "select",
        ]

        for (name, expectedType) in requiredProperties {
            guard let property = properties[name] as? [String: Any],
                  let propertyType = property["type"] as? String,
                  propertyType == expectedType else {
                throw NotionError.schemaValidationFailed(
                    "Missing or incorrect property '\(name)' (expected type: \(expectedType))"
                )
            }
        }

        return true
    }

    // MARK: - Meeting Sync

    /// Creates a Notion page for a meeting record in the specified database.
    /// Returns the created page ID.
    func createMeetingPage(meeting: MeetingRecord, databaseId: String) async throws -> String {
        let durationMinutes = Int(meeting.duration / 60)

        // Build properties
        let properties: [String: Any] = [
            "Title": [
                "title": [
                    ["type": "text", "text": ["content": meeting.title]]
                ]
            ],
            "Date": [
                "date": ["start": ISO8601DateFormatter().string(from: meeting.date)]
            ],
            "Duration (min)": [
                "number": durationMinutes
            ],
            "Summary": [
                "rich_text": [
                    ["type": "text", "text": ["content": String((meeting.summary ?? "").prefix(2000))]]
                ]
            ],
            "Status": [
                "select": ["name": "Draft"]
            ],
            "Whisper Model": [
                "select": ["name": meeting.whisperModel.rawValue]
            ],
        ]

        // Build page body blocks
        var children: [[String: Any]] = []

        // Summary section
        children.append(headingBlock(text: "Summary", level: 2))
        children.append(paragraphBlock(text: meeting.summary ?? "No summary available."))

        // Action Items section
        children.append(headingBlock(text: "Action Items", level: 2))
        if let actionItems = meeting.actionItems, !actionItems.isEmpty {
            for item in actionItems {
                children.append(todoBlock(text: item, checked: false))
            }
        } else {
            children.append(paragraphBlock(text: "No action items identified."))
        }

        // Key Decisions section
        children.append(headingBlock(text: "Key Decisions", level: 2))
        if let decisions = meeting.keyDecisions, !decisions.isEmpty {
            for decision in decisions {
                children.append(bulletedListBlock(text: decision))
            }
        } else {
            children.append(paragraphBlock(text: "No key decisions identified."))
        }

        // Full Transcript as a toggle block
        children.append(toggleBlock(
            text: "Full Transcript",
            children: [paragraphBlock(text: meeting.transcript ?? "No transcript available.")]
        ))

        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties,
            "children": children,
        ]

        let request = try authenticatedRequest(
            path: "/pages",
            method: "POST",
            body: body
        )

        let (data, response) = try await performRequestWithRetry(request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageId = json["id"] as? String else {
            throw NotionError.invalidResponse(statusCode: 0)
        }

        return pageId
    }

    /// Queues a meeting for later sync (e.g., when offline).
    func queueForSync(_ meeting: MeetingRecord) {
        pendingSyncQueue.append(meeting)
    }

    /// Retries all queued meetings that failed to sync.
    func retryPendingSync() async {
        guard let databaseId = AppSettings.shared.notionDatabaseId else { return }

        var failedMeetings: [MeetingRecord] = []

        for meeting in pendingSyncQueue {
            do {
                _ = try await createMeetingPage(meeting: meeting, databaseId: databaseId)
            } catch {
                failedMeetings.append(meeting)
            }
        }

        pendingSyncQueue = failedMeetings
    }

    // MARK: - Block Builders

    private func headingBlock(text: String, level: Int) -> [String: Any] {
        let key: String
        switch level {
        case 1: key = "heading_1"
        case 3: key = "heading_3"
        default: key = "heading_2"
        }

        return [
            "object": "block",
            "type": key,
            key: [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ]
            ],
        ]
    }

    private func paragraphBlock(text: String) -> [String: Any] {
        // Notion blocks have a 2000-character limit per rich text element.
        // Split long text into multiple rich_text elements.
        let chunks = splitText(text, maxLength: 2000)
        let richTextElements: [[String: Any]] = chunks.map { chunk in
            ["type": "text", "text": ["content": chunk]]
        }

        return [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": richTextElements
            ],
        ]
    }

    private func todoBlock(text: String, checked: Bool) -> [String: Any] {
        return [
            "object": "block",
            "type": "to_do",
            "to_do": [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ],
                "checked": checked,
            ],
        ]
    }

    private func bulletedListBlock(text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ]
            ],
        ]
    }

    private func toggleBlock(text: String, children: [[String: Any]]) -> [String: Any] {
        return [
            "object": "block",
            "type": "toggle",
            "toggle": [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ],
                "children": children,
            ],
        ]
    }

    private func splitText(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }

        var chunks: [String] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: maxLength, limitedBy: remaining.endIndex)
                ?? remaining.endIndex
            chunks.append(String(remaining[remaining.startIndex..<end]))
            remaining = remaining[end...]
        }

        return chunks
    }

    // MARK: - Network Helpers

    /// Creates an authenticated URLRequest for the Notion API.
    private func authenticatedRequest(
        path: String,
        method: String,
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        guard let token = keychain.retrieve(key: Self.keychainTokenKey) else {
            throw NotionError.notAuthenticated
        }

        let url = URL(string: "\(Self.baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    /// Performs a URL request and returns the data and response.
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw NotionError.networkError(error)
        }
    }

    /// Performs a URL request with exponential backoff retry for rate limiting.
    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (data, response)
            }

            // Success or non-retryable error
            if httpResponse.statusCode != 429 {
                return (data, response)
            }

            // Rate limited - extract Retry-After header or use exponential backoff
            let retryAfter: TimeInterval
            if let retryHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let seconds = TimeInterval(retryHeader) {
                retryAfter = seconds
            } else {
                retryAfter = baseRetryDelay * pow(2.0, Double(attempt))
            }

            lastError = NotionError.rateLimited(retryAfter: retryAfter)

            // Wait before retrying
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
        }

        throw lastError ?? NotionError.rateLimited(retryAfter: 0)
    }

    /// Validates an HTTP response, throwing on error status codes.
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                // Token is invalid; mark as disconnected
                isConnected = false
                workspaceName = nil
                throw NotionError.notAuthenticated
            }
            throw NotionError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }
}
