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
    var workEndHour: Double = AppConstants.defaultWorkEndHour

    // MARK: - 标签管理

    var tags: [String] = AppConstants.defaultTags
    var newTagText: String = ""

    func loadTags() {
        tags = UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
    }

    func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTagText = ""
        saveTags()
    }

    func removeTag(at index: Int) {
        guard tags.count > 1 else { return }
        tags.remove(at: index)
        saveTags()
    }

    private func saveTags() {
        UserDefaults.standard.set(tags, forKey: AppConstants.tagsKey)
    }

    /// 根据当前时间计算剩余工作小时数
    var remainingWorkHours: Double {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = Double(calendar.component(.hour, from: now))
        let currentMinute = Double(calendar.component(.minute, from: now)) / 60.0
        let currentTime = currentHour + currentMinute
        return max(0, workEndHour - currentTime)
    }

    /// 今天工作时间是否已结束
    var isWorkTimeEnded: Bool {
        remainingWorkHours <= 0
    }

    // MARK: - 工作结束时间

    func loadWorkEndTime() {
        workEndHour = UserDefaults.standard.double(forKey: AppConstants.workEndTimeKey)
        if workEndHour == 0 {
            workEndHour = AppConstants.defaultWorkEndHour
        }
    }

    func saveWorkEndTime(_ hour: Double) {
        workEndHour = hour
        UserDefaults.standard.set(hour, forKey: AppConstants.workEndTimeKey)
    }

    // MARK: - 开机自启

    var launchAtLogin: Bool = false
    private var isUpdatingLaunchAtLogin: Bool = false

    var isLaunchAtLoginDisabled: Bool {
        isUpdatingLaunchAtLogin
    }

    // MARK: - 模型选择

    var selectedModel: String = AppConstants.defaultModel

    // MARK: - Dependencies

    weak var appState: AppState?

    init() {
        loadAPIKey()
        loadSelectedModel()
        loadWorkEndTime()
        loadTags()
    }

    // MARK: - Lifecycle

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
        Task.detached {
            let enabled = SMAppService.mainApp.status == .enabled
            await MainActor.run { [weak self] in
                self?.launchAtLogin = enabled
            }
        }
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
