import Foundation

/// Prompt 模板管理
enum PromptTemplates {

    private static func formatToday() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: Date())
    }

    private static func formatWeekday() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private static func formatCurrentTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    // MARK: - 想法解析

    static func parseThought(input: String, existingTaskTitles: [String], availableTags: [String] = AppConstants.defaultTags) -> String {
        let tagList = availableTags.joined(separator: "/")
        let today = formatToday()
        let weekday = formatWeekday()
        let currentTime = formatCurrentTime()
        var prompt = """
        你是一个任务管理助手。将用户的想法整理为结构化任务列表。

        当前时间参考：\(today) \(weekday) \(currentTime)

        核心原则：按用户的意图粒度拆分，不按执行步骤拆分。

        规则优先级（从高到低）：
        1. 去重：重复任务直接跳过
        2. 不按执行步骤拆分
        3. 不合并不同独立事项
        4. title 保留用户原意，允许轻微规范化
        5. note 提取补充说明
        6. category 必须从 tagList 选择
        7. deadline 只提取用户明确表达的时间
        8. estimated_minutes 和 is_project 按规则判断
        9. 只输出严格 JSON

        详细规则：

        【title】
        - 保留用户原意和关键词，允许轻微规范化（去掉语气词、无意义连接词、明显时间表达）。
        - 如果存在备注信息（冒号后、括号中），title 保留核心事项，note 保存补充说明。
        - 不要过度改写（如"重启博客项目"不要改成"搭建个人知识管理与内容发布平台"）。

        【拆分边界】
        - 禁止将一个活动拆解为多个步骤（如"整理房间"不要拆成扫地、叠被子、洗衣服）。
        - 禁止合并不同事项（如"补电影A"和"补电影B"是两个独立任务）。
        - 多个对象共享同一个动作且用户表达为整体时，保留为一个任务（如"整理房间和书桌"不拆分）。
        - 如果 note 中的补充说明本身是一个独立事项（动作不同或目标不同），应拆成单独任务而不是放进 note。例如"看论文《XXX》，然后写一篇公众号文章"→ 拆成"看论文《XXX》"和"写一篇公众号文章"两个任务。

        【category】
        - 必须从以下分类中选择：\(tagList)。不得自创分类。
        - 没有明显合适分类时选择最接近的；如果列表中有"其他"且无更合适选项，选"其他"。

        【estimated_minutes】
        - 普通单次事项必须给出分钟数。参考范围：阅读文章5-15分钟，看一集剧30-60分钟，开会30-120分钟，写文档30-180分钟，出门办事30-120分钟，了解/调研/整理类任务30-90分钟。
        - 长期项目、系列计划、学习路线或无法整体一次完成的目标，estimated_minutes 设为 null。
        - "了解一下""研究一下""整理一下""调研一下""形成笔记""形成方案"等一次性任务，estimated_minutes 给出分钟数（通常30-90分钟）。

        【is_project】
        判断标准：该事项是否真的需要长期、持续、多阶段推进。不是看 title 中是否出现"项目""计划""系统""学习""搭建"等关键词。
        - is_project=true（仅限于明显无法一次完成、需持续推进的）：
          · 系列内容：追完整部剧、补完整个系列电影、跟完整门课程、读完整本书
          · 长期学习路线：学 Swift、系统学习机器学习、准备考研数学
          · 多阶段建设目标：开发完整 App、装修房子、搭建并长期维护个人博客
          · 持续运营目标：运营公众号、长期维护博客、做系列视频账号
        - is_project=false（默认，优先使用）：
          · 所有单次可完成的事项：整理房间、写一篇文章、修一个 bug、部署一次 Halo
          · 一次性了解/调研：了解 Halo 博客系统、调研 AI 食物识别方案、研究某个 GitHub 项目
          · 一次性整理/形成产物：整理 App 想法、整理 AI 食物卡路里 App 的想法
          · 学习的子集：学 Swift 闭包、看 CS193p 第一节、读一篇论文
          · 口语中的"项目"≠ 真正项目："重启博客项目""试试 Halo 项目"
        - 如果难以判断，默认 is_project=false。

        边界示例：
        · "重启博客项目，使用 Halo 项目" → title="重启博客项目", note="使用 Halo 项目", is_project=false, estimated_minutes=60
        · "部署 Halo 博客" → is_project=false, estimated_minutes=90
        · "搭建个人博客" → is_project=false, estimated_minutes=120（除非用户明确说"长期维护"）
        · "搭建并长期维护个人博客" → is_project=true, estimated_minutes=null
        · "学 Swift" → is_project=true, estimated_minutes=null
        · "学 Swift 闭包" → is_project=false, estimated_minutes=45
        · "跟完 CS193p" → is_project=true, estimated_minutes=null
        · "看 CS193p 第一节" → is_project=false, estimated_minutes=60
        · "做 AI 食物卡路里 App" → is_project=true, estimated_minutes=null
        · "整理 AI 食物卡路里 App 的想法" → is_project=false, estimated_minutes=60

        【deadline】
        - 只提取用户明确表达的时间，格式为 "M-d" 或 "M-d HH:mm" 或 "yyyy-M-d HH:mm"。
        - 所有相对时间基于当前时间 \(today) \(weekday) \(currentTime) 解析。"今天"=\(today)，"明天"=下一天，"周五前"=最近的周五。
        - 如果用户没有明确提及时间信息（如"有空""之后""待办"），deadline 设为 null。
        - 如果只提到时间没提到日期（如"下午3点前"），视为今天。
        - 年份由系统自动补充为当前年份，除非用户明确指定了年份。
        - 如果只有日期没有具体时间，只输出日期部分（如 "4-1"），不要编造时间（不要自作主张输出 "4-1 23:59"）。
        - 如果同时有日期和时间，输出日期和时间（如 "4-1 15:00"）。
        - 不要因为系统默认无 deadline 显示在今天，就自行编造时间。无明确时间 = null。

        【note】
        - 提取补充说明，可提取的形式包括：冒号后内容、括号中内容、"使用……""参考……""主要是……""重点看……""跟……课程""顺便做笔记""用……实现""基于……方案"。
        - 提取后 title 精简为核心事项。例如"重启博客：Halo 部署"→ title="重启博客", note="Halo 部署"；"学Swift（跟斯坦福CS193p课程）"→ title="学Swift", note="跟斯坦福CS193p课程"；"看论文《XXX》，做笔记"→ title="看论文《XXX》", note="做笔记"。
        - 如果补充说明本身是独立事项（动作不同或目标不同），不要放进 note，应拆成单独任务。
        - 无补充说明则 note 设为 null。

        【去重】
        - 与已有任务语义相同或高度相似（用词不同但指同一件事）→ 直接跳过。例如已有「搭建个人博客」时，用户再说「开始写技术博客」应跳过。
        - 但相关但不同的任务不应跳过。例如已有「了解 Halo 博客系统」时，用户说「部署 Halo 博客」不应跳过（同主题不同行动）。已有「搭建个人博客」时，用户说「写第一篇博客文章」不应跳过（新事项）。

        示例输入：「今天要把项目报告初稿写完，顺便整理工位，下午产品评审会」
        正确输出：3 个任务 — 「完成项目报告初稿」「整理工位」「产品评审会」
        错误输出：拆成「收集数据」「写大纲」「写正文」「整理文件」「清垃圾」等步骤

        输出要求：
        - 只输出严格 JSON，不要输出 Markdown 代码块、解释文字或多余字段。
        - 字段缺失时使用 null，不要省略字段。

        输出格式：
        {
          "tasks": [
            {
              "title": "任务名称",
              "category": "分类",
              "estimated_minutes": 60,
              "deadline": "M-d" 或 "M-d HH:mm" 或 null,
              "is_project": true 或 false,
              "note": "备注内容" 或 null
            }
          ]
        }
        """

        if !existingTaskTitles.isEmpty {
            let titles = existingTaskTitles.map { "- \($0)" }.joined(separator: "\n")
            prompt += "\n\n已有任务列表（重复的跳过，相关但不同的不跳过）：\n\(titles)"
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
            let deadlineText = t.deadlineDisplayString.map { "，截止:\($0)" } ?? ""
            let projectText = t.isProject == true ? "，项目" : ""
            let noteText = (t.note?.isEmpty == false) ? "，备注:\(t.note!)" : ""
            return "\(i + 1). 「\(t.title)」(\(t.category)，\(durationText)\(projectText)\(deadlineText)\(noteText))"
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
        deadline 格式为 "M-d" 或 "M-d HH:mm" 或 "yyyy-M-d HH:mm"，无截止时间则设为 null。如果用户修改要求中提到时间调整，相应更新 deadline。
        is_project：如果用户在修改要求中明确要求改变某个任务的项目/普通类型，按用户要求设置 is_project（true=项目，false=普通想法）。如果用户未提及类型变更，设为 null。
        note：保留原有备注内容。仅当用户明确要求修改备注时才更改，否则原样保留。新增任务设为 null。

        输出严格的 JSON：
        {
          "tasks": [
            {
              "title": "任务名称",
              "category": "分类",
              "estimated_minutes": 60,
              "deadline": "M-d" 或 "M-d HH:mm" 或 null,
              "is_project": true 或 false 或 null,
              "note": "备注内容" 或 null
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
        strategy: MustDoViewModel.RecommendationStrategy,
        extraContext: String? = nil
    ) -> String {
        let mustDoList = mustDoTasks.enumerated().map { i, t in
            "\(i + 1). \(t.title) - \((t.estimatedMinutes ?? 0))分钟 - \(t.status)"
        }.joined(separator: "\n")

        let ideaList = ideaPoolTasks.enumerated().map { i, t in
            let durationText = t.estimatedMinutes.map { "\($0)分钟" } ?? "无整体预估时长"
            let deadlineText = t.deadlineDisplay.map { " - 截止:\($0)" } ?? ""
            let base = "\(i + 1). [id: \(t.id.uuidString)] \(t.title) - \(durationText) - \(t.category)\(t.attempted ? " - 已尝试" : "")\(t.isProject ? " - 项目型想法" : "")\(deadlineText)"
            var details = ""
            if let note = t.note, !note.isEmpty {
                details += "\n   备注：\(note)"
            }
            if !t.projectNotes.isEmpty {
                details += "\n   项目备注：" + t.projectNotes.joined(separator: "；")
            }
            if let summary = t.projectRecommendationSummary, !summary.isEmpty {
                details += "\n   项目状态摘要：\(summary)"
            }
            if let background = t.planningBackground, !background.isEmpty {
                details += "\n   规划背景：\(background)"
            }
            if let desc = t.projectDescription, !desc.isEmpty {
                details += "\n   项目描述：\(desc)"
            }
            return "\(base)\(details)"
        }.joined(separator: "\n")

        let mustDoTotalMinutes = mustDoTasks.filter { !$0.status.hasPrefix("已完成") }.reduce(0) {
            $0 + max(0, ($1.estimatedMinutes ?? 0) - $1.elapsedMinutes)
        }
        let freeHours = max(0, remainingHours - Double(mustDoTotalMinutes) / 60.0)

        let strategyHint: String
        switch strategy {
        case .quick:
            strategyHint = "本轮是快速推荐模式，目标是优先清理想法池并快速形成完成感。默认优先考虑普通想法而非项目，倾向选择明确、低阻力、容易完成的事项。"
        case .comprehensive:
            strategyHint = "本轮是综合推荐模式，目标是在普通想法和项目之间综合权衡今天最值得推进的内容，不偏袒普通想法，也不默认偏袒项目。"
        }

        let extraSection: String
        if let extraContext, !extraContext.isEmpty {
            extraSection = "\n## 用户额外要求\n\(extraContext)\n"
        } else {
            extraSection = ""
        }

        return """
        你是一个任务管理助手。请根据用户今天的情况，从想法池中推荐最合适的任务加入今日必做项。

        ## 推荐策略
        \(strategyHint)
        \(extraSection)
        ## 当前时间
        今天是 \(formatToday())，剩余工作时间约 \(String(format: "%.1f", remainingHours)) 小时

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
        8. 有截止时间（deadline）的任务应优先考虑，截止时间越紧迫优先级越高
        9. 会议、活动、约见等事件类想法：重点参考备注和截止时间判断。如果截止时间就是今天，或备注说明需要提前准备，才推荐今天做；如果截止时间在未来且不需要提前准备，不要提前推荐（当天再推荐即可）

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
        你是一个任务管理助手。请判断下列想法中，哪些属于"项目型想法"。

        ## 判断原则

        核心判断：这个想法能否在今天内作为一个完整动作直接执行？
        - 如果能 → 普通想法（is_project: false）
        - 如果不能，需要拆解成多个独立步骤分多天推进 → 项目型想法（is_project: true）

        ## 项目型想法特征（满足任一即为项目）
        - 明确需要多个阶段/步骤才能完成，无法一次性做完
        - 涉及学习、研究、迭代等需要时间沉淀的过程
        - 最终交付物由多个可独立验收的部分组成
        - 电视剧、系列电影等需要长期追更的内容

        ## 普通想法特征
        - 有清晰的单一动作和完成标准，今天就能做完
        - 耗时在一天以内，且不需要分阶段推进
        - 单部电影、单篇文章等一次性可完成的内容

        ## 作品类判断规则
        遇到影视、书籍、课程、游戏等作品类想法时，不要仅依据标题文本中的关键词（如”系列”）判断，应结合你对作品的了解进行语义推理：该作品是单一单元（单部电影、单本书、单机短游戏）还是多单元（电视剧、系列丛书、多季番剧、多集纪录片、大型游戏）？多单元作品需要分多次消费，应判断为项目。
        例如”补《小兵张嘎》”——虽然标题没有”系列”二字，但这是一部电视剧（多集），需要分多次观看，应判断为项目。

        ## 判断示例

        是项目：
        - “搭建个人博客” → 需要选型、搭建、部署、调优等多个阶段
        - “学习 Swift” → 持续学习过程，无法一次性完成
        - “重构认证系统” → 涉及分析、设计、迁移、测试等多个步骤
        - “观看《速度与激情》系列” → 多部电影，需要分多次完成
        - “补《小兵张嘎》” → 电视剧（多集），需分多次观看

        不是项目：
        - “写一篇技术博客” → 单次写作任务
        - “修复登录页 bug” → 单一修复动作
        - “整理读书笔记” → 可在短时间内完成
        - “学习 SwiftUI 基础语法” → 有明确范围的单次学习
        - “阅读《设计模式》第 3 章” → 有明确边界的一次性动作
        - “观看《肖申克的救赎》” → 单部电影，一次看完

        ## 明确排除规则（以下情况一律为普通想法）
        - 标题含”了解”、”见抖音收藏”、”见相册”等浏览性描述 → 普通想法
        - 仅一个网址、平台名称、或”了解某段历史”等泛泛描述 → 普通想法
        - 没有具体行动计划的泛泛了解 → 普通想法
        - “了解 X 并形成推文/笔记/文章” → 了解+单次产出，整体可在一天内完成，属于普通想法
        - “深入了解 X” + 任何单次可交付的动作（写推文、写笔记、总结） → 普通想法

        ## 注意
        - 标题中包含”学习”、”了解”不一定是项目，要看是否有明确的单次完成边界
        - 标题中包含”完成”、”写”、”修复”等动词也不一定不是项目，要看整体复杂度
        - 单部电影 ≠ 项目，系列电影 = 项目，电视剧 = 项目
        - 有歧义时倾向判断为普通想法（is_project: false）

        想法列表：
        \(taskList)

        输出严格 JSON：
        {
          “items”: [
            {
              “idea_id”: “UUID”,
              “is_project”: true,
              “reason”: “判断理由”
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

    static func generateProjectRecommendationSummary(input: ProjectRecommendationSummaryInput) -> String {
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
        你是一个项目推荐状态摘要器。你的目标不是直接推荐任务，而是把一个项目当前的真实推进状态压缩成一段短摘要，供后续“AI 推荐必做项”使用。

        这段摘要必须帮助后续推荐 AI 快速理解：
        1. 这个项目当前大致处于哪个阶段
        2. 最近已经推进了什么
        3. 当前还有哪些未完成推进项或阻塞
        4. 下一步最适合承接的方向是什么

        输出要求：
        1. 输出简洁、稳定、信息密度高的中文摘要
        2. 不要复述所有细节，只保留最影响“下一步推荐”的内容
        3. 摘要控制在 2 到 4 句
        4. 不要输出 Markdown

        输出严格 JSON：
        {
          "summary": "项目当前状态摘要"
        }

        当前项目：
        - 标题：\(input.title)
        - 分类：\(input.category)

        项目描述：
        \(input.projectDescription?.isEmpty == false ? input.projectDescription! : "（无）")

        规划背景：
        \(input.planningBackground?.isEmpty == false ? input.planningBackground! : "（无）")

        当前进度摘要：
        \(input.projectProgressSummary?.isEmpty == false ? input.projectProgressSummary! : "（无）")

        最近项目备注：
        \(notesText)

        当前未归档推进任务：
        \(activeTasksText)

        已归档推进记录：
        \(settledTasksText)
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
