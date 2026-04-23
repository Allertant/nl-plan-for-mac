import Foundation

/// Prompt 模板管理
enum PromptTemplates {

    // MARK: - 想法解析

    static func parseThought(input: String, existingTaskTitles: [String], availableTags: [String] = AppConstants.defaultTags) -> String {
        let tagList = availableTags.joined(separator: "/")
        var prompt = """
        你是一个任务管理助手。将用户的想法整理为结构化任务列表。

        核心原则：按用户的意图粒度拆分，不按执行步骤拆分。

        规则：
        1. 用户列出的每个独立事项 = 一个任务，原样保留用户的措辞
        2. 禁止将一个活动拆解为多个步骤（如"整理房间"不要拆成扫地、叠被子、洗衣服）
        3. 禁止合并不同事项（如"补电影A"和"补电影B"是两个独立任务）
        4. 为每个任务从以下分类中选择最合适的一个：\(tagList)。必须从中选择，不得自创分类。并预估时长（分钟）
        5. 推荐最应该今天完成的任务（recommended = true）

        示例输入：「今天要把项目报告初稿写完，顺便整理工位，下午产品评审会」
        正确输出：3 个任务 — 「完成项目报告初稿」「整理工位」「产品评审会」
        错误输出：拆成「收集数据」「写大纲」「写正文」「整理文件」「清垃圾」等步骤

        输出严格的 JSON：
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
        userInstruction: String,
        availableTags: [String] = AppConstants.defaultTags
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

        请根据用户的修改要求，调整任务列表（可以增删改）。

        核心原则：按用户的意图粒度拆分，不按执行步骤拆分。每个用户提到的独立事项 = 一个任务。

        分类必须从以下列表中选择：\(availableTags.joined(separator: "/"))，不得自创分类。

        输出严格的 JSON：
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
    }

    // MARK: - 想法池清理

    static func cleanupIdeaPool(tasks: [TaskRecommendationInput]) -> String {
        let taskList = tasks.enumerated().map { i, t in
            "\(i + 1). [id: \(t.id.uuidString)] \(t.title) - \(t.estimatedMinutes)分钟 - \(t.category)\(t.attempted ? " - 已尝试过" : "")"
        }.joined(separator: "\n")

        return """
        你是一个任务管理助手。请审查用户的想法池，找出应该清理的任务。

        清理标准（满足任一即可建议删除）：
        1. 内容过于模糊，无法执行（如单个词、缺少具体行动）
        2. 与其他任务高度重复
        3. 已尝试过但长期未转化为必做项（说明用户不真正想做）
        4. 内容不合理或不具可执行性

        不要删除：用户明确、具体、有意义的想法，即使暂时不会做。

        ## 想法池任务列表
        \(taskList)

        输出严格的 JSON：
        {
          "items": [
            { "task_id": "任务的 UUID", "reason": "建议删除的理由" }
          ],
          "overall_reason": "整体清理建议"
        }

        如果没有需要清理的任务，返回空列表并说明理由。
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
        - B：必做项完成 ≥90%
        - C：必做项完成 ≥80%
        - D：必做项完成 ≥60%
        - E：必做项完成 ≥40%
        - F：必做项完成 <40%

        要求：
        1. 给出等级和具体评价（2-3句）
        2. 指出做得好的地方
        3. 指出可以改进的地方
        4. 给出明日建议

        请在 grading_basis 字段中详细说明评分依据。

        输出严格的 JSON 格式：
        {
          "grade": "S|A|B|C|D|E|F",
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
            "\(i + 1). [id: \(t.id.uuidString)] \(t.title) - \(t.estimatedMinutes)分钟 - \(t.category)\(t.attempted ? " - 已尝试" : "")\(t.isProject ? " - 项目型想法" : "")"
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
        5. 如果某条想法是“项目型想法”，优先推荐一个今天可执行的小切片任务，而不是直接推荐整个项目标题
        6. 如果空余时间不够或没有合适的任务，返回空列表并说明理由

        输出严格的 JSON 格式：
        {
          "recommendations": [
            {
              "task_id": "若直接推荐已有想法，则填写想法池中任务 UUID；否则为 null",
              "source_idea_id": "若推荐项目切片，则填写来源想法 UUID；否则为 null",
              "title": "展示给用户的推荐标题",
              "category": "分类",
              "estimated_minutes": 60,
              "reason": "推荐理由"
            }
          ],
          "overall_reason": "整体推荐说明"
        }
        """
    }

    static func classifyProjects(tasks: [ProjectClassificationInput]) -> String {
        let taskList = tasks.enumerated().map { index, task in
            "\(index + 1). [id: \(task.id.uuidString)] \(task.title) - \(task.category) - \(task.estimatedMinutes)分钟"
        }.joined(separator: "\n")

        return """
        你是一个任务管理助手。请判断下列想法中，哪些属于“项目型想法”。

        项目型想法的标准：
        1. 明显跨多天推进，无法在一天内整体完成
        2. 更像长期目标，而不是单次动作
        3. 如果直接加入今日必做项，容易造成执行压力过大

        普通想法的标准：
        1. 可以在较短时间内直接执行
        2. 更像单个任务而不是长期项目

        想法列表：
        \(taskList)

        输出严格 JSON：
        {
          "items": [
            {
              "idea_id": "UUID",
              "is_project": true,
              "reason": "判断理由"
            }
          ]
        }
        """
    }

    static func analyzeProjectProgress(projects: [ProjectProgressInput]) -> String {
        let projectList = projects.enumerated().map { index, project in
            let completed = project.completedTasks.map {
                "- [已完成] \($0.title)（\($0.estimatedMinutes)分钟）"
            }.joined(separator: "\n")
            let pending = project.pendingTasks.map {
                "- [未完成] \($0.title)（\($0.estimatedMinutes)分钟）"
            }.joined(separator: "\n")

            return """
            \(index + 1). [idea_id: \(project.ideaId.uuidString)] \(project.title) - \(project.category)
            已完成绑定必做项：
            \(completed.isEmpty ? "（无）" : completed)
            未完成绑定必做项：
            \(pending.isEmpty ? "（无）" : pending)
            """
        }.joined(separator: "\n\n")

        return """
        你是一个任务管理助手。请根据每个项目已经完成和未完成的绑定必做项，评估其当前进度。

        规则：
        1. 只有已完成的绑定必做项可以直接计入进度
        2. 未完成的绑定必做项只作为上下文，不直接计入进度
        3. progress 返回 0 到 100 的数字
        4. summary 用一句简短的话概括当前推进情况
        5. 如果你判断项目已经完成，可以返回 100

        项目列表：
        \(projectList)

        输出严格 JSON：
        {
          "items": [
            {
              "idea_id": "UUID",
              "progress": 35,
              "summary": "已完成多次相关推进，正在稳定前进"
            }
          ]
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
          "grade": "S|A|B|C|D|E|F",
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
