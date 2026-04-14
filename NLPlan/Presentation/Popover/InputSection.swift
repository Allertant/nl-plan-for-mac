import SwiftUI

/// 输入区视图
struct InputSection: View {
    @Bindable var viewModel: InputViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                TextField("输入你的想法和计划...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                    .font(.system(size: 13))
                    .onSubmit {
                        Task { await viewModel.submit() }
                    }

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isProcessing || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)

            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 正在解析...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }
}
