import Foundation

/// 备忘录同步服务（AppleScript）
final class AppleNotesService: Sendable {

    /// 同步日终总结到备忘录
    func syncToNotes(summary: DailySummaryEntity) async throws {
        let content = formatSummary(summary)

        let script = """
        tell application "Notes"
            tell account "iCloud"
                make new note at folder "Notes" with properties {name:"NL Plan - \(formatDate(summary.date))", body:"\(escapeForAppleScript(content))"}
            end tell
        end tell
        """

        try await runAppleScript(script)
        print("✅ 成功同步到备忘录")
    }

    // MARK: - Private

    private func formatSummary(_ summary: DailySummaryEntity) -> String {
        var lines: [String] = []
        lines.append("<h1>📊 今日总结 - \(formatDate(summary.date))</h1>")
        lines.append("<h2>评分：\(summary.grade)</h2>")
        lines.append("<p><b>AI 评价：</b>\(summary.summary)</p>")

        if let suggestion = summary.suggestion, !suggestion.isEmpty {
            lines.append("<p><b>明日建议：</b>\(suggestion)</p>")
        }

        lines.append("<h3>统计数据</h3>")
        lines.append("<ul>")
        lines.append("<li>完成任务：\(summary.completedCount) / \(summary.totalCount)</li>")
        lines.append("<li>计划总时长：\(summary.totalPlannedMinutes) 分钟</li>")
        lines.append("<li>实际总时长：\(summary.totalActualMinutes) 分钟</li>")
        if let basis = summary.gradingBasis {
            lines.append("<li>评分依据：\(basis)</li>")
        }
        lines.append("</ul>")

        return lines.joined(separator: "\n")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func runAppleScript(_ source: String) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]

        let pipe = Pipe()
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NLPlanError.notesSyncFailed(underlying: NSError(
                domain: "AppleNotesService",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
        }
    }
}
