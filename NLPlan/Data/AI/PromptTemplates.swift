import Foundation

/// Prompt 模板管理
enum PromptTemplates {

    // MARK: - 想法解析

    static func parseThought(input: String, existingTaskTitles: [String]) -> String {
        var prompt = """
        你是一个任务管理助手。用户会用自然语言描述今天的想法和计划。
        请将用户的输入整理为结构化的任务列表。

        要求：
        1. 每个任务必须是可执行、可完成的具体行动
        2. 将内容相近的细碎事项合并为一个任务，保持每个任务有足够的体量（30-120 分钟）
        3. 为每个任务预估合理时长（分钟）
        4. 推荐其中最应该今天完成的任务（recommended = true）
        5. 为每个任务分类（工作/生活/学习/健康/其他）
        6. 生成 1-3 个任务即可，不要过度拆分

        输出严格的 JSON 格式：
        {
          "tasks": [
            {
              "title": "任务名称",
              "category": "分类",
              "estimated_minutes": 60,
              "recommended": true,
              "reason": "推荐理由"
            }
          ]
        }
        """

        if !existingTaskTitles.isEmpty {
            let titles = existingTaskTitles.map { "- \($0)" }.joined(separator: "\n")
            prompt += "\n\n用户已有的任务列表（请避免生成重复任务）：\n\(titles)"
        }

        prompt += "\n\n用户的输入：\n\(input)"
        return prompt
    }

    // MARK: - 修改解析结果

    static func refineParsedTasks(
        originalInput: String,
        currentTasks: [ParsedTask],
        userInstruction: String
    ) -> String {
        let taskList = currentTasks.enumerated().map { i, t in
            "\(i + 1). 「\(t.title)」(\(t.category)，\(t.estimatedMinutes)分钟)\(t.recommended ? " [推荐]" : "")\(t.reason.isEmpty ? "" : " —— \(t.reason)")"
        }.joined(separator: "\n")

        return """
        你是一个任务管理助手。用户之前输入了一段想法，你将其解析为了任务列表。现在用户希望调整结果。

        用户原始输入：
        \(originalInput)

        当前任务列表：
        \(taskList)

        用户的修改要求：
        \(userInstruction)

        请根据用户的修改要求，调整任务列表（可以增删改），输出严格的 JSON 格式：
        {
          "tasks": [
            {
              "title": "任务名称",
              "category": "分类",
              "estimated_minutes": 60,
              "recommended": true,
              "reason": "推荐理由"
            }
          ]
        }

        要求：
        1. 只输出修改后的完整任务列表
        2. 生成 1-3 个任务，不要过度拆分
        3. 每个任务 30-120 分钟
        """
    }

    // MARK: - 日终评分

    static func dailyGrade(input: DailySummaryInput) -> String {
        let taskDetailsText = input.taskDetails.map { task in
            "- \(task.title)：预估\(task.estimatedMinutes)分钟，实际\(task.actualMinutes)分钟，\(task.completed ? "已完成" : "未完成")"
        }.joined(separator: "\n")

        return """
        你是一个效率教练。根据用户今天的任务完成情况，给出评价和评分。

        评分标准：
        - S：必做项全部完成，时间偏差 ≤10%，额外完成想法池任务
        - A：必做项全部完成，时间偏差 ≤20%
        - B：必做项完成 ≥80%
        - C：必做项完成 ≥50%
        - D：必做项完成 <50%

        要求：
        1. 给出等级和具体评价（2-3句）
        2. 指出做得好的地方
        3. 指出可以改进的地方
        4. 给出明日建议

        请在 grading_basis 字段中详细说明评分依据。

        输出严格的 JSON 格式：
        {
          "grade": "S|A|B|C|D",
          "summary": "评价文本",
          "grading_basis": "评分依据和理由",
          "stats": {
            "total_tasks": \(input.totalTasks),
            "completed_tasks": \(input.completedTasks),
            "total_planned_minutes": \(input.totalPlannedMinutes),
            "total_actual_minutes": \(input.totalActualMinutes),
            "deviation_rate": \(input.deviationRate)
          },
          "suggestion": "明日建议"
        }

        今日任务数据：
        - 必做项总数：\(input.totalTasks)
        - 完成数：\(input.completedTasks)
        - 计划总时长：\(input.totalPlannedMinutes) 分钟
        - 实际总时长：\(input.totalActualMinutes) 分钟
        - 时间偏差率：\(String(format: "%.1f%%", input.deviationRate * 100))
        - 额外完成想法池任务：\(input.extraCompleted) 个

        任务详情：
        \(taskDetailsText)
        """
    }

    // MARK: - AI 推荐

    static func recommendTasks(
        ideaPoolTasks: [TaskRecommendationInput],
        mustDoTasks: [TaskRecommendationInput],
        remainingHours: Double,
        strategy: MustDoViewModel.RecommendationStrategy
    ) -> String {
        let mustDoList = mustDoTasks.enumerated().map { i, t in
            "\(i + 1). \(t.title) - \(t.estimatedMinutes)分钟 - \(t.status == "running" ? "进行中" : "待开始")"
        }.joined(separator: "\n")

        let ideaList = ideaPoolTasks.enumerated().map { i, t in
            "\(i + 1). [id: \(t.id.uuidString)] \(t.title) - \(t.estimatedMinutes)分钟 - \(t.category)\(t.attempted ? " - 已尝试" : "")"
        }.joined(separator: "\n")

        let mustDoTotalMinutes = mustDoTasks.reduce(0) { $0 + $1.estimatedMinutes }
        let freeHours = max(0, remainingHours - Double(mustDoTotalMinutes) / 60.0)

        let strategyHint: String
        switch strategy {
        case .quickWin:
            strategyHint = "优先推荐预估时间短、容易完成的任务，让用户快速积累完成感。按预估时间从短到长排列推荐结果。"
        case .hardFirst:
            strategyHint = "优先推荐预估时间长、挑战性高的任务，趁用户精力充沛时先完成困难事项。按预估时间从长到短排列推荐结果。"
        }

        return """
        你是一个任务管理助手。请根据用户今天的情况，从想法池中推荐最合适的任务加入今日必做项。

        ## 推荐策略
        \(strategyHint)

        ## 当前时间
        剩余工作时间约 \(String(format: "%.1f", remainingHours)) 小时

        ## 今日必做项（已有）
        \(mustDoTasks.isEmpty ? "（无）" : mustDoList)

        必做项预计总时长：\(mustDoTotalMinutes) 分钟

        ## 想法池（可选任务）
        \(ideaList)

        ## 剩余可用空余时间
        约 \(String(format: "%.1f", freeHours)) 小时

        ## 要求
        从想法池中选出 1-3 项最适合今天完成的任务，考虑：
        1. 剩余空余时间是否充足
        2. 已尝试过（attempted）的任务优先级适当降低
        3. 分类尽量分散
        4. 按推荐执行顺序排列（第一个最应该先做）
        5. 如果空余时间不够或没有合适的任务，返回空列表并说明理由

        输出严格的 JSON 格式：
        {
          "recommendations": [
            { "task_id": "想法池中任务的 UUID", "reason": "推荐理由" }
          ],
          "overall_reason": "整体推荐说明"
        }
        """
    }

    // MARK: - 驳斥评分

    static func appealGrade(
        originalGrade: DailyGrade,
        originalInput: DailySummaryInput,
        userFeedback: String
    ) -> String {
        return """
        你之前给用户的评分如下：
        - 等级：\(originalGrade.grade.rawValue)
        - 评价：\(originalGrade.summary)
        - 评分依据：\(originalGrade.gradingBasis)

        用户对评分提出了异议：
        "\(userFeedback)"

        请根据用户的反馈重新评估，输出严格的 JSON 格式：
        {
          "grade": "S|A|B|C|D",
          "summary": "重新评价文本",
          "grading_basis": "重新评分的依据，需回应用户的反馈",
          "stats": {
            "total_tasks": \(originalInput.totalTasks),
            "completed_tasks": \(originalInput.completedTasks),
            "total_planned_minutes": \(originalInput.totalPlannedMinutes),
            "total_actual_minutes": \(originalInput.totalActualMinutes),
            "deviation_rate": \(originalInput.deviationRate)
          },
          "suggestion": "明日建议"
        }
        """
    }
}
