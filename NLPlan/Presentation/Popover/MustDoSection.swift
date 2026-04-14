import SwiftUI

/// 必做项列表区域
struct MustDoSection: View {
    @Bindable var viewModel: MustDoViewModel
    let timerEngine: TimerEngine

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("必做项")
                    .font(.system(size: 13, weight: .semibold))
                if !viewModel.tasks.isEmpty {
                    Text("\(viewModel.completedTasks.count)/\(viewModel.tasks.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if viewModel.tasks.isEmpty {
                Text("还没有必做项")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                // 未完成任务
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.pendingTasks, id: \.id) { task in
                        MustDoTaskRow(
                            task: task,
                            timerEngine: timerEngine,
                            onStart: { Task { await viewModel.startTask(taskId: task.id) } },
                            onComplete: { Task { await viewModel.markComplete(taskId: task.id) } },
                            onDemote: { Task { await viewModel.demoteToIdeaPool(taskId: task.id) } }
                        )
                    }
                }
                .padding(.horizontal, 8)

                // 已完成任务
                if !viewModel.completedTasks.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.completedTasks, id: \.id) { task in
                            CompletedTaskRow(task: task)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

/// 必做项任务卡片
struct MustDoTaskRow: View {
    let task: TaskEntity
    let timerEngine: TimerEngine
    let onStart: () -> Void
    let onComplete: () -> Void
    let onDemote: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 状态图标
            Image(systemName: task.taskStatus.iconName)
                .font(.system(size: 16))
                .foregroundStyle(task.status == TaskStatus.running.rawValue ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("预计\(task.estimatedMinutes)分钟", systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if task.status == TaskStatus.running.rawValue {
                        RunningTimerView(taskId: task.id, timerEngine: timerEngine)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if task.status != TaskStatus.running.rawValue {
                    Button {
                        onStart()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("开始执行")
                }

                Button {
                    onComplete()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("标记完成")

                Button {
                    onDemote()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移回想法池")
            }
        }
        .padding(8)
        .background(
            task.status == TaskStatus.running.rawValue
            ? Color.green.opacity(0.08)
            : Color(nsColor: .textBackgroundColor)
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(task.status == TaskStatus.running.rawValue ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

/// 运行中的计时器显示
struct RunningTimerView: View {
    let taskId: UUID
    let timerEngine: TimerEngine

    @State private var displayText: String = "00:00:00"
    @State private var timer: Timer?

    var body: some View {
        Text(displayText)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.green)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                timer?.invalidate()
            }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task {
                let seconds = await timerEngine.elapsedSeconds(for: taskId)
                let hours = seconds / 3600
                let minutes = (seconds % 3600) / 60
                let secs = seconds % 60
                await MainActor.run {
                    self.displayText = String(format: "%02d:%02d:%02d", hours, minutes, secs)
                }
            }
        }
    }
}

/// 已完成任务卡片
struct CompletedTaskRow: View {
    let task: TaskEntity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            Text(task.title)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .strikethrough()

            Spacer()

            let minutes = task.totalElapsedSeconds / 60
            Text("\(minutes)分钟")
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}
