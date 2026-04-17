import SwiftUI

/// 设置页
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: SettingsViewModel

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
                    SecureField("DeepSeek API Key", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    HStack {
                        Button("保存") {
                            viewModel.saveAPIKey()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSave)

                        Button(viewModel.isValidatingAPIKey ? "验证中..." : "验证") {
                            viewModel.validateAPIKey()
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canValidate)

                        if viewModel.showSaveSuccess {
                            Text("已保存 ✓")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }

                        if !viewModel.validationMessage.isEmpty {
                            Text(viewModel.validationMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(viewModel.validationMessage.hasPrefix("✅") ? .green : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                Text("功能设置")
                    .font(.system(size: 12, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("允许并行计时", isOn: $viewModel.allowParallel)
                        .font(.system(size: 12))

                    Toggle("开机自启", isOn: $viewModel.launchAtLogin)
                        .font(.system(size: 12))
                        .disabled(viewModel.isLaunchAtLoginDisabled)
                        .onChange(of: viewModel.launchAtLogin) { _, newValue in
                            viewModel.updateLaunchAtLogin(enabled: newValue)
                        }

                    Toggle("同步到备忘录", isOn: $viewModel.syncToNotes)
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

                Picker("选择模型", selection: $viewModel.selectedModel) {
                    ForEach(AppConstants.availableModels, id: \.id) { model in
                        Text("\(model.name) – \(model.description)")
                            .font(.system(size: 12))
                            .tag(model.id)
                    }
                }
                .font(.system(size: 12))
                .onChange(of: viewModel.selectedModel) { _, newValue in
                    viewModel.saveSelectedModel(newValue)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: 360, height: 520)
        .onAppear {
            viewModel.loadAll()
        }
    }
}
