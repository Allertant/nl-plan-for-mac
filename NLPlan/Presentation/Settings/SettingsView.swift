import ServiceManagement
import SwiftUI

/// 设置页
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey: String = ""
    @State private var savedAPIKey: String = ""
    @State private var allowParallel: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var isUpdatingLaunchAtLogin: Bool = false
    @State private var syncToNotes: Bool = true
    @State private var showSaveSuccess: Bool = false
    @State private var validationMessage: String = ""
    @State private var isValidatingAPIKey: Bool = false
    @State private var selectedModel: String = AppConstants.defaultModel

    /// 关闭回调
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("AI 服务配置")
                    .font(.system(size: 12, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("DeepSeek API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    HStack {
                        Button("保存") {
                            saveAPIKey()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey == savedAPIKey)

                        Button(isValidatingAPIKey ? "验证中..." : "验证") {
                            validateAPIKey()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.bordered)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingAPIKey)

                        if showSaveSuccess {
                            Text("已保存 ✓")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }

                        if !validationMessage.isEmpty {
                            Text(validationMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(validationMessage.hasPrefix("✅") ? .green : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                Text("功能设置")
                    .font(.system(size: 12, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("允许并行计时", isOn: $allowParallel)
                        .font(.system(size: 12))

                    Toggle("开机自启", isOn: $launchAtLogin)
                        .font(.system(size: 12))
                        .disabled(isUpdatingLaunchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(enabled: newValue)
                        }

                    Toggle("同步到备忘录", isOn: $syncToNotes)
                        .font(.system(size: 12))
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                Text("外观")
                    .font(.system(size: 12, weight: .semibold))

                Picker(
                    "外观模式",
                    selection: Binding(
                        get: { appState.appearanceMode },
                        set: { appState.updateAppearanceMode($0) }
                    )
                ) {
                    ForEach(AppState.AppearanceMode.allCases) { mode in
                        Text(mode.displayName)
                            .font(.system(size: 12))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("AI 模型")
                    .font(.system(size: 12, weight: .semibold))

                Picker("选择模型", selection: $selectedModel) {
                    ForEach(AppConstants.availableModels, id: \.id) { model in
                        Text("\(model.name) – \(model.description)")
                            .font(.system(size: 12))
                            .tag(model.id)
                    }
                }
                .font(.system(size: 12))
                .onChange(of: selectedModel) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: AppConstants.selectedModelKey)
                    validationMessage = ""
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: 360, height: 520)
        .onAppear {
            loadAPIKey()
            loadSelectedModel()
            loadLaunchAtLoginState()
        }
        .onChange(of: apiKey) { _, _ in
            validationMessage = ""
            showSaveSuccess = false
        }
    }

    private func loadAPIKey() {
        if let key = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) {
            apiKey = key
            savedAPIKey = key
        }
    }

    private func saveAPIKey() {
        do {
            try KeychainStore.shared.save(key: AppConstants.apiKeyKeychainKey, value: apiKey)
            savedAPIKey = apiKey
            appState.refreshAPIKeyStatus()
            showSaveSuccess = true
            validationMessage = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSaveSuccess = false
            }
        } catch {
            // 静默失败
        }
    }

    private func loadSelectedModel() {
        selectedModel = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
    }

    private func loadLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }

        isUpdatingLaunchAtLogin = true

        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }

                await MainActor.run {
                    isUpdatingLaunchAtLogin = false
                    launchAtLogin = enabled
                }
            } catch {
                await MainActor.run {
                    isUpdatingLaunchAtLogin = false
                    launchAtLogin.toggle()
                }
            }
        }
    }

    private func validateAPIKey() {
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

                await MainActor.run {
                    isValidatingAPIKey = false
                    validationMessage = "✅ API Key 有效"
                }
            } catch let error as NLPlanError {
                await MainActor.run {
                    isValidatingAPIKey = false
                    switch error {
                    case .aiAPIError(let statusCode, _):
                        if statusCode == 401 {
                            validationMessage = "❌ API Key 无效"
                        } else if statusCode == 429 {
                            validationMessage = "⚠️ 请求频率超限，请稍后再试"
                        } else {
                            validationMessage = "❌ 验证失败：HTTP \(statusCode)"
                        }
                    case .aiRequestTimeout:
                        validationMessage = "⚠️ 验证超时，请稍后重试"
                    default:
                        validationMessage = "❌ 验证失败"
                    }
                }
            } catch {
                await MainActor.run {
                    isValidatingAPIKey = false
                    validationMessage = "❌ 验证失败"
                }
            }
        }
    }
}
