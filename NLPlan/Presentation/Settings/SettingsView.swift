import SwiftUI

/// 设置页
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey: String = ""
    @State private var allowParallel: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var syncToNotes: Bool = true
    @State private var showSaveSuccess: Bool = false
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

            Form {
                // API Key
                Section {
                    SecureField("智谱 AI API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    HStack {
                        Button("保存") {
                            saveAPIKey()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.borderedProminent)

                        if showSaveSuccess {
                            Text("已保存 ✓")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }

                        Spacer()

                        if !apiKey.isEmpty {
                            Button("清除") {
                                clearAPIKey()
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("AI 服务配置")
                        .font(.system(size: 12, weight: .semibold))
                }

                // 功能开关
                Section {
                    Toggle("允许并行计时", isOn: $allowParallel)
                        .font(.system(size: 12))

                    Toggle("开机自启", isOn: $launchAtLogin)
                        .font(.system(size: 12))
                        .disabled(true) // V1 暂不实现

                    Toggle("同步到备忘录", isOn: $syncToNotes)
                        .font(.system(size: 12))
                } header: {
                    Text("功能设置")
                        .font(.system(size: 12, weight: .semibold))
                }

                // AI 模型选择
                Section {
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
                    }
                } header: {
                    Text("AI 模型")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 360, height: 420)
        .onAppear {
            loadAPIKey()
            loadSelectedModel()
        }
    }

    private func loadAPIKey() {
        if let key = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) {
            apiKey = key
        }
    }

    private func saveAPIKey() {
        do {
            if apiKey.isEmpty {
                try KeychainStore.shared.delete(key: AppConstants.apiKeyKeychainKey)
            } else {
                try KeychainStore.shared.save(key: AppConstants.apiKeyKeychainKey, value: apiKey)
            }
            appState.refreshAPIKeyStatus()
            showSaveSuccess = true
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

    private func clearAPIKey() {
        apiKey = ""
        do {
            try KeychainStore.shared.delete(key: AppConstants.apiKeyKeychainKey)
            appState.refreshAPIKeyStatus()
        } catch {
            // 静默失败
        }
    }
}
