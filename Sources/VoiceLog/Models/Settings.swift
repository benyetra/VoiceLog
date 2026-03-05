import Foundation

// MARK: - AppSettings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var whisperModelSize: WhisperModelSize {
        didSet { UserDefaults.standard.set(whisperModelSize.rawValue, forKey: "whisperModelSize") }
    }

    @Published var selectedAudioDeviceID: String? {
        didSet { UserDefaults.standard.set(selectedAudioDeviceID, forKey: "selectedAudioDeviceID") }
    }

    @Published var globalHotkey: String {
        didSet { UserDefaults.standard.set(globalHotkey, forKey: "globalHotkey") }
    }

    @Published var useLocalLLM: Bool {
        didSet { UserDefaults.standard.set(useLocalLLM, forKey: "useLocalLLM") }
    }

    @Published var openAIApiKey: String? {
        didSet {
            if let key = openAIApiKey {
                KeychainService.shared.save(key: "openai_api_key", value: key)
            }
        }
    }

    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel") }
    }

    @Published var localStoragePath: String {
        didSet { UserDefaults.standard.set(localStoragePath, forKey: "localStoragePath") }
    }

    @Published var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "retentionDays") }
    }

    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    @Published var notionDatabaseId: String? {
        didSet { UserDefaults.standard.set(notionDatabaseId, forKey: "notionDatabaseId") }
    }

    @Published var aiPostProcessingEnabled: Bool {
        didSet { UserDefaults.standard.set(aiPostProcessingEnabled, forKey: "aiPostProcessingEnabled") }
    }

    @Published var whisperLanguage: String? {
        didSet { UserDefaults.standard.set(whisperLanguage, forKey: "whisperLanguage") }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.whisperModelSize = WhisperModelSize(rawValue: defaults.string(forKey: "whisperModelSize") ?? "") ?? .medium
        self.selectedAudioDeviceID = defaults.string(forKey: "selectedAudioDeviceID")
        self.globalHotkey = defaults.string(forKey: "globalHotkey") ?? "\u{2303}\u{2325}R"
        self.useLocalLLM = defaults.object(forKey: "useLocalLLM") as? Bool ?? true
        self.openAIApiKey = KeychainService.shared.retrieve(key: "openai_api_key")
        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3"

        let defaultPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceLog").path
        self.localStoragePath = defaults.string(forKey: "localStoragePath") ?? defaultPath
        self.retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.notionDatabaseId = defaults.string(forKey: "notionDatabaseId")
        self.aiPostProcessingEnabled = defaults.object(forKey: "aiPostProcessingEnabled") as? Bool ?? true
        self.whisperLanguage = defaults.string(forKey: "whisperLanguage")
    }
}
