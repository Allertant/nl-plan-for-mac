import Foundation
import ServiceManagement

/// 设置页 ViewModel
@Observable
final class SettingsViewModel {

    // MARK: - API Key

    var apiKey: String = "" {
        didSet {
            validationMessage = ""
            showSaveSuccess = false
        }
    }

    private(set) var savedAPIKey: String = ""

    var showSaveSuccess: Bool = false
    var validationMessage: String = ""
    var isValidatingAPIKey: Bool = false

    var canSave: Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && apiKey != savedAPIKey
    }

    var canValidate: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidatingAPIKey
    }

    // MARK: - 功能设置

    var allowParallel: Bool = false
    var syncToNotes: Bool = true

    // MARK: - 开机自启

    var launchAtLogin: Bool = false
    private var isUpdatingLaunchAtLogin: Bool = false

    var isLaunchAtLoginDisabled: Bool {
        isUpdatingLaunchAtLogin
    }

    // MARK: - 模型选择

    var selectedModel: String = AppConstants.defaultModel

    // MARK: - Dependencies

    private weak var appState: AppState?

    init(appState: AppState?) {
        self.appState = appState
    }

    // MARK: - Lifecycle

    func loadAll() {
        loadAPIKey()
        loadSelectedModel()
        loadLaunchAtLoginState()
    }

    // MARK: - API Key

    func loadAPIKey() {
        if let key = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) {
            apiKey = key
            savedAPIKey = key
        }
    }

    func saveAPIKey() {
        do {
            try KeychainStore.shared.save(key: AppConstants.apiKeyKeychainKey, value: apiKey)
            savedAPIKey = apiKey
            appState?.refreshAPIKeyStatus()
            showSaveSuccess = true
            validationMessage = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showSaveSuccess = false
            }
        } catch {
            // 静默失败
        }
    }

    func validateAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            validationMessage = "请输入 API Key"
            return
        }

        isValidatingAPIKey = true
        validationMessage = ""

        Task {
            let service = DeepSeekAIService(apiKey: trimmedKey, model: selectedModel)

            do {
                _ = try await service.parseThoughts(
                    input: "请返回一个简单任务",
                    existingTaskTitles: []
                )

                await MainActor.run { [weak self] in
                    self?.isValidatingAPIKey = false
                    self?.validationMessage = "✅ API Key 有效"
                }
            } catch let error as NLPlanError {
                await MainActor.run { [weak self] in
                    self?.isValidatingAPIKey = false
                    switch error {
                    case .aiAPIError(let statusCode, _):
                        if statusCode == 401 {
                            self?.validationMessage = "❌ API Key 无效"
                        } else if statusCode == 429 {
                            self?.validationMessage = "⚠️ 请求频率超限，请稍后再试"
                        } else {
                            self?.validationMessage = "❌ 验证失败：HTTP \(statusCode)"
                        }
                    case .aiRequestTimeout:
                        self?.validationMessage = "⚠️ 验证超时，请稍后重试"
                    default:
                        self?.validationMessage = "❌ 验证失败"
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isValidatingAPIKey = false
                    self?.validationMessage = "❌ 验证失败"
                }
            }
        }
    }

    // MARK: - 模型选择

    func loadSelectedModel() {
        selectedModel = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
    }

    func saveSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: AppConstants.selectedModelKey)
        validationMessage = ""
    }

    // MARK: - 开机自启

    func loadLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func updateLaunchAtLogin(enabled: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }

        isUpdatingLaunchAtLogin = true

        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }

                await MainActor.run { [weak self] in
                    self?.isUpdatingLaunchAtLogin = false
                    self?.launchAtLogin = enabled
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isUpdatingLaunchAtLogin = false
                    self?.launchAtLogin.toggle()
                }
            }
        }
    }
}
