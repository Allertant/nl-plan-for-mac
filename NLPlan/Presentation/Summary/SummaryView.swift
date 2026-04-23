import SwiftUI

/// 日终总结页
struct SummaryView: View {
    @Bindable var viewModel: SummaryViewModel
    @Environment(AppState.self) private var appState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                BackButton(action: onDismiss)

                Text("今日总结")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Text("正在结算：\(viewModel.settlementDate.dateString)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if viewModel.isProcessing {
                // 评分中
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("AI 正在评分...")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Button("取消") {
                        viewModel.cancelEndDay()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary = viewModel.summary {
                // 评分结果
                ScrollView {
                    VStack(spacing: 20) {
                        // 等级大字展示
                        GradeDisplay(grade: summary.gradeEnum)

                        // 统计卡片
                        StatsGrid(summary: summary)

                        // AI 评价
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI 评价")
                                .font(.system(size: 14, weight: .semibold))
                            Text(summary.summary)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .cornerRadius(8)

                        // 明日建议
                        if let suggestion = summary.suggestion, !suggestion.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("明日建议")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(suggestion)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                            .cornerRadius(8)
                        }

                        // 评分依据（驳斥时展示）
                        if let basis = summary.gradingBasis, !basis.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("评分依据")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(basis)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                            .cornerRadius(8)
                        }

                        // 驳斥按钮
                        if viewModel.canAppeal {
                            if viewModel.showAppealInput {
                                VStack(spacing: 8) {
                                    TextField("告诉 AI 你的想法...", text: $viewModel.appealText, axis: .vertical)
                                        .textFieldStyle(.plain)
                                        .lineLimit(2...4)
                                        .font(.system(size: 12))
                                        .padding(8)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .cornerRadius(6)

                                    HStack {
                                        Button("取消") {
                                            viewModel.showAppealInput = false
                                            viewModel.appealText = ""
                                        }
                                        .font(.system(size: 12))

                                        Spacer()

                                        Button("提交申诉") {
                                            Task { await viewModel.appealGrade() }
                                        }
                                        .font(.system(size: 12))
                                        .buttonStyle(.borderedProminent)
                                        .disabled(viewModel.isAppealing || viewModel.appealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                            } else {
                                Button {
                                    viewModel.showAppealInput = true
                                } label: {
                                    Label("驳斥评分（剩余 \(viewModel.remainingAppeals) 次）", systemImage: "exclamationmark.bubble")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else if summary.appealCount >= AppConstants.maxAppealCount {
                            Text("今日申诉次数已用完")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        // 撤销评分
                        Button {
                            Task { await viewModel.undoEndDay() }
                        } label: {
                            Text("撤销评分")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            } else {
                // 未评分
                ScrollView {
                    VStack(spacing: 16) {
                    Text("该日期尚未结算")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    if !viewModel.incompleteTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("未完成必做项需要补充备注")
                                .font(.system(size: 13, weight: .semibold))
                            Text("备注会进入本次结算评分依据，用于说明阻塞、低估、调整或后续安排。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            ForEach(viewModel.incompleteTasks, id: \.id) { task in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    TextField(
                                        "补充未完成原因和后续安排...",
                                        text: Binding(
                                            get: { viewModel.incompleteNotes[task.id] ?? "" },
                                            set: { viewModel.incompleteNotes[task.id] = $0 }
                                        ),
                                        axis: .vertical
                                    )
                                    .textFieldStyle(.plain)
                                    .lineLimit(2...4)
                                    .font(.system(size: 12))
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        viewModel.endDay()
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color.red.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSettle)
                    .opacity(viewModel.canSettle ? 1 : 0.45)
                    .help("确认结算")
                }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 360, height: 520)
        .onAppear {
            Task { await viewModel.loadTodaySummary() }
        }
    }
}

/// 等级大字展示
struct GradeDisplay: View {
    let grade: Grade

    var gradeColor: Color {
        switch grade {
        case .S: return .purple
        case .A: return .blue
        case .B: return .cyan
        case .C: return .green
        case .D: return .yellow
        case .E: return .orange
        case .F: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(gradeColor.opacity(0.15))
                .frame(width: 100, height: 100)

            Text(grade.displayName)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(gradeColor)
        }
    }
}

/// 统计网格
struct StatsGrid: View {
    let summary: DailySummaryEntity

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(title: "完成", value: "\(summary.completedCount)/\(summary.totalCount)")
            StatCard(title: "计划时长", value: summary.totalPlannedMinutes.hourMinuteString)
            StatCard(title: "实际时长", value: summary.totalActualMinutes.hourMinuteString)
        }
    }
}

/// 统计卡片
struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}
