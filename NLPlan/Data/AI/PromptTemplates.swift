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
        4. 为每个任务从以下分类中选择最合适的一个：\(tagList)。必须从中选择，不得自创分类。
        5. 如果任务是普通单次事项，estimated_minutes 必须给出分钟数。
        6. 如果任务明显是长期项目、系列计划、学习路线或无法整体一次完成的目标，不要给整项预估时长，estimated_minutes 设为 null。
        7. 推荐最应该今天完成的任务（recommended = true）

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
            let durationText = t.estimatedMinutes.map { "\($0)分钟" } ?? "无整体预估时长"
            return "\(i + 1). 「\(t.title)」(\(t.category)，\(durationText))\(t.recommended ? " [推荐]" : "")\(t.reason.isEmpty ? "" : " —— \(t.reason)")"
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
        普通单次事项必须填写 estimated_minutes；长期项目、系列计划、学习路线等整体不可一次完成的条目，estimated_minutes 设为 null。

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
            let durationText = t.estimatedMinutes.map { "\($0)分钟" } ?? "无整体预估时长"
            return "\(i + 1). [id: \(t.id.uuidString)] \(t.title) - \(durationText) - \(t.category)\(t.attempted ? " - 已尝试过" : "")"
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
            let noteText = task.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (noteText?.isEmpty == false) ? (noteText ?? "无") : "无"
            return "- \(task.title)：来源=\(task.sourceType)，优先级=\(task.priority)，预估\(task.estimatedMinutes)分钟，实际\(task.actualMinutes)分钟，\(task.completed ? "已完成" : "未完成")，备注=\(note)"
        }.joined(separator: "\n")

        return """
        你是一个效率教练。请根据用户在结算日的整体工作情况，给出稳定、可复现的综合评分。

        ## 核心评分原则
        评分不是完成率排名。完成率只是参考指标之一，不能作为唯一或主要评分依据。

        请综合考虑：
        - 任务量：当天安排的任务数量和总预计时长是否合理。
        - 任务难度：是否需要深度思考、创造、沟通、决策或复杂执行。
        - 任务复杂度：是否包含多步骤、依赖关系、不确定性和上下文切换。
        - 推进价值：即使没有完全完成，是否产生了实质推进。
        - 完成情况：完成/未完成比例和关键任务完成情况。
        - 守信程度：计划了但没有完成，说明没有完全兑现承诺，应适当扣分。
        - 未完成解释：备注是否说明了阻塞、低估、调整或后续安排。
        - 时间偏差：实际耗时与预估耗时的偏离程度。
        - 项目推进：项目相关任务重点看长期项目推进价值，而不是只看单项是否完成。

        ## 等级尺度
        - S：任务量、难度、完成质量和推进价值都很高，且计划兑现非常好。
        - A：高质量完成了有价值的计划，或在高难任务上取得明显成果。
        - B：整体执行良好，有一定未完成或偏差，但推进价值明确。
        - C：有有效推进，但计划兑现、任务量、备注质量或时间控制存在明显不足。
        - D：执行结果偏弱，未完成较多，或计划明显失真。
        - E：大部分计划没有兑现，且解释不足，推进价值有限。
        - F：几乎没有有效推进，或计划严重失信且缺少解释。

        ## 重要约束
        - 完成率较低但任务难度高、推进价值大、备注说明充分时，不应自动给低分。
        - 完成率很高但任务量很低、任务简单、计划保守时，不应自动给高分。
        - 计划了没完成且没有充分说明时，应明显扣守信分。
        - 同样的输入应给出稳定一致的评分，避免随机波动。
        - 不要为了鼓励用户而虚高评分，也不要机械惩罚所有未完成任务。

        ## 示例尺度
        示例 1：少量高难任务，完成率一般但推进明显
        - 计划 2 个任务，完成 1 个；另一个复杂项目任务未完成，但备注说明完成了关键调研、技术路径验证和下一步安排。
        - 建议评分：B 或 C。
        - 原因：完成率不高，但任务难度和推进价值较高，且未完成说明充分。

        示例 2：大量简单任务全部完成
        - 计划 8 个低难度任务并全部完成，但任务价值较低、计划保守。
        - 建议评分：B。
        - 原因：执行稳定，但不应仅因完成率 100% 自动给 A 或 S。

        示例 3：计划过载且备注不足
        - 计划 10 个任务，只完成 3 个，多数未完成任务没有清楚说明。
        - 建议评分：D 或 E。
        - 原因：计划明显过载，守信程度不足，复盘信息不足。

        示例 4：合理计划但遇到客观阻塞
        - 计划 4 个任务，完成 2 个，未完成项备注说明依赖外部反馈或技术阻塞，并给出后续安排。
        - 建议评分：C。
        - 原因：完成率一般，但阻塞合理且复盘清楚。

        示例 5：项目任务有实质推进
        - 项目相关必做项未完成，但备注显示完成了关键拆解、验证或方案设计。
        - 建议评分：B。
        - 原因：虽然单项未完成，但对长期项目有实际推进价值。

        示例 6：无备注未完成
        - 多个必做项未完成，且没有有效备注解释。
        - 建议评分：E 或 F。
        - 原因：计划未兑现且缺少说明，守信程度明显不足。

        ## 输出要求
        1. 给出等级和具体评价（2-3句）。
        2. 指出做得好的地方。
        3. 指出可以改进的地方。
        4. 给出明日建议。
        5. grading_basis 必须说明任务量、难度/复杂度、推进价值、完成情况、守信程度、备注质量和时间偏差如何共同影响评分。

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

        结算任务数据：
        - 结算日期：\(input.settlementDate.isEmpty ? "未指定" : input.settlementDate)
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
            "\(i + 1). \(t.title) - \((t.estimatedMinutes ?? 0))分钟 - \(t.status == "running" ? "进行中" : "待开始")"
        }.joined(separator: "\n")

        let ideaList = ideaPoolTasks.enumerated().map { i, t in
            let durationText = t.estimatedMinutes.map { "\($0)分钟" } ?? "无整体预估时长"
            let base = "\(i + 1). [id: \(t.id.uuidString)] \(t.title) - \(durationText) - \(t.category)\(t.attempted ? " - 已尝试" : "")\(t.isProject ? " - 项目型想法" : "")"
            if let background = t.planningBackground, !background.isEmpty {
                return "\(base)\n   规划背景：\(background)"
            }
            if let desc = t.projectDescription, !desc.isEmpty {
                return "\(base)\n   项目描述：\(desc)"
            }
            return base
        }.joined(separator: "\n")

        let mustDoTotalMinutes = mustDoTasks.reduce(0) { $0 + ($1.estimatedMinutes ?? 0) }
        let freeHours = max(0, remainingHours - Double(mustDoTotalMinutes) / 60.0)

        let strategyHint: String
        switch strategy {
        case .quick:
            strategyHint = "本轮是快速推荐模式，目标是优先清理想法池并快速形成完成感。默认优先考虑普通想法而非项目，倾向选择明确、低阻力、容易完成的事项。"
        case .comprehensive:
            strategyHint = "本轮是综合推荐模式，目标是在普通想法和项目之间综合权衡今天最值得推进的内容，不偏袒普通想法，也不默认偏袒项目。"
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
        5. 若候选中包含项目型想法，优先推荐一个今天可执行的小切片任务，而不是直接推荐整个项目标题
        6. 快速模式下应明显偏向普通想法的清理与消化；综合模式下允许普通想法和项目同时竞争
        7. 如果空余时间不够或没有合适的任务，返回空列表并说明理由

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
            "\(index + 1). [id: \(task.id.uuidString)] \(task.title) - \(task.category)"
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

    static func generatePlanningBackgroundPrompt(input: PlanningBackgroundPromptInput) -> String {
        let notesText = input.notes.isEmpty ? "（无）" : input.notes.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }.joined(separator: "\n")
        let activeTasksText = input.activeTasks.isEmpty ? "（无）" : input.activeTasks.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }.joined(separator: "\n")
        let settledTasksText = input.settledTasks.isEmpty ? "（无）" : input.settledTasks.enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }.joined(separator: "\n")

        return """
        你是一个“项目规划背景研究提示词生成器”。你的工作不是直接写规划背景，而是生成一段给外部联网 AI 使用的完整提示词。

        目标：
        1. 帮用户补足内部推荐 AI 缺少的外部知识。
        2. 让外部 AI 返回一份结构化《规划背景》模板，而不是自由散文。
        3. 让这份规划背景直接服务于后续必做项推荐、阶段拆分和时间估算。

        你输出的 research_prompt 必须要求外部 AI：
        1. 先联网搜索最新可信信息，并明确以当前日期为准。
        2. 输出结构化《规划背景》，而不是泛泛介绍。
        3. 重点回答“这个项目如何拆解、如何安排阶段、单次行动做什么”。
        4. 如果缺少用户偏好或前置信息，必须列出“不确定项 / 待确认项”。
        5. 必须给出“可信来源”。

        外部 AI 返回的《规划背景》应尽量包含这些栏目：
        - 项目主题
        - 项目目标
        - 关键客观事实
        - 常见推进路径
        - 推荐学习/执行方式
        - 用户偏好与限制
        - 可拆分阶段
        - 单次行动建议
        - 时间估算依据
        - 可信来源
        - 不确定项 / 待确认项

        请输出严格 JSON：
        {
          "reason": "为什么这个项目需要补充规划背景，指出内部 AI 当前缺少什么外部知识",
          "research_prompt": "给外部联网 AI 的完整提示词"
        }

        当前项目：
        - 标题：\(input.title)
        - 分类：\(input.category)
        - 预估时长：\(input.estimatedMinutes.map { "\($0) 分钟" } ?? "未提供 / 不适用")
        - 是否已尝试过：\(input.attempted ? "是" : "否")

        已有项目描述：
        \(input.projectDescription?.isEmpty == false ? input.projectDescription! : "（无）")

        已有规划背景：
        \(input.planningBackground?.isEmpty == false ? input.planningBackground! : "（无）")

        项目备注：
        \(notesText)

        当前推进任务：
        \(activeTasksText)

        已归档推进记录：
        \(settledTasksText)
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
