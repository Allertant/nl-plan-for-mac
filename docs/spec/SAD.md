# NL Plan for Mac — 软件架构文档

## 1. 架构概览

应用采用分层架构，从上到下分为四层：

```
┌─────────────────────────────────────┐
│           Presentation              │  SwiftUI Views
├─────────────────────────────────────┤
│           ViewModel                 │  @Observable ViewModels
├─────────────────────────────────────┤
│           Domain                    │  Managers + AI Coordinator
├─────────────────────────────────────┤
│           Data                      │  Repositories + SwiftData
└─────────────────────────────────────┘
```

## 2. 各层职责

### 2.1 Presentation（视图层）

SwiftUI 视图，纯 UI 展示和用户交互。每个视图绑定对应的 ViewModel，不直接访问数据层。

主要视图：

| 视图 | 职责 |
|------|------|
| PopoverView | 主工作区：输入区 + 解析队列 + 必做项列表 |
| IdeaPoolPageView | 想法池管理：搜索、过滤、项目详情 |
| SummaryView | 日终评分：统计、评分、驳斥 |
| HistoryView | 历史记录：月历 + 每日详情 |
| SettingsView | 设置：API Key、模型选择、工作时间等 |
| QueueDetailView | 解析确认：编辑和确认 AI 解析结果 |

### 2.2 ViewModel（视图模型层）

`@Observable` 类，管理视图状态和业务逻辑调用。

| ViewModel | 管理范围 |
|-----------|----------|
| InputViewModel | 输入队列、解析状态、确认流程 |
| MustDoViewModel | 必做项列表、计时、AI 推荐 |
| IdeaPoolViewModel | 想法池列表、项目管理、AI 清理 |
| DaySummaryViewModel | 日终评分、驳斥、统计 |

ViewModel 持有 `TaskManager` 或 `DayManager` 的引用，通过它们操作数据。AI 服务在 ViewModel 中按需创建（因为 API Key 可能随时变更）。

### 2.3 Domain（领域层）

| 组件 | 职责 |
|------|------|
| TaskManager | 任务全生命周期：想法解析、保存、提升、退回、开始执行、完成、来源绑定、项目备注 |
| DayManager | 一天的生命周期：评分、结算归档、跨天迁移、驳斥 |
| AIExecutionCoordinator | AI 调用的统一重试组件（actor），封装重试策略和错误分类 |
| TimerEngine | 计时引擎（actor），管理单任务/并行计时切换 |

### 2.4 Data（数据层）

| 组件 | 职责 |
|------|------|
| IdeaRepository | IdeaEntity + ProjectNoteEntity 的 CRUD |
| DailyTaskRepository | DailyTaskEntity 的 CRUD，含活跃/归档查询 |
| SessionLogRepository | SessionLogEntity 的 CRUD，含计时统计 |
| SummaryRepository | DailySummaryEntity 的 CRUD |
| ThoughtRepository | ThoughtEntity 的 CRUD |
| DeepSeekAIService | DeepSeek API 调用实现，PromptTemplates 管理 prompt 构造 |

## 3. 数据模型

### 3.1 IdeaEntity（想法池条目）

普通想法和项目共用一张表，通过 `isProject` 字段区分。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 标题 |
| category | String | 分类标签 |
| estimatedMinutes | Int? | 预估时长（项目为 nil） |
| priority | String | 优先级（high/medium/low） |
| status | String | 状态（pending/in_progress/attempted/completed/archived） |
| aiRecommended | Bool | 是否由 AI 推荐 |
| recommendationReason | String? | AI 推荐理由 |
| attempted | Bool | 是否尝试过 |
| note | String? | 备注 |
| isProject | Bool | 是否为项目 |
| projectDescription | String? | 项目说明 |
| planningBackground | String? | 规划背景 |
| planningResearchPrompt | String? | AI 生成的规划研究提示词 |
| projectProgress | Double? | 项目进度百分比 |
| projectProgressSummary | String? | AI 生成的进度摘要 |
| projectRecommendationContextUpdatedAt | Date? | 推荐上下文最后更新时间 |
| projectRecommendationSummary | String? | 推荐用状态摘要 |
| projectRecommendationSummarySourceUpdatedAt | Date? | 摘要对应的上下文快照时间 |

### 3.2 DailyTaskEntity（必做项）

活跃必做项和归档记录共用一张表，通过 `isSettled` 字段区分。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 标题 |
| category | String | 分类 |
| estimatedMinutes | Int | 预估时长 |
| priority | String | 优先级 |
| status | String | 状态（pending/running/done） |
| date | Date | 所属日期 |
| sourceIdeaId | UUID? | 来源想法 ID |
| sourceType | String | 来源类型（idea/project/none） |
| aiRecommended | Bool | 是否由 AI 推荐 |
| recommendationReason | String? | AI 推荐理由 |
| note | String? | 任务备注 |
| isSettled | Bool | 是否已归档（默认 false） |
| settledAt | Date? | 归档时间 |
| actualMinutes | Int? | 实际耗时（归档时计算） |
| settlementNote | String? | 结算备注 |

### 3.3 其他实体

| 实体 | 说明 |
|------|------|
| DailySummaryEntity | 日终评分：日期、等级(A-F)、总结、建议、统计数据、驳斥次数 |
| SessionLogEntity | 计时记录：开始/结束时间、持续秒数、关联任务 |
| ThoughtEntity | 原始输入：用户提交的原始文本，标记是否已处理 |
| ProjectNoteEntity | 项目备注：内容、创建/更新时间、关联项目 |

## 4. 核心流程

### 4.1 任务输入流程

```
用户输入文本
  → InputViewModel 提交到解析队列
  → TaskManager.parseThoughts (AI 解析)
  → 用户在 QueueDetailView 预览/编辑
  → 用户可追加指令 → TaskManager.refineParsedTasks (AI 修改)
  → TaskManager.classifyProjects (AI 判断是否项目)
  → TaskManager.saveParsedTasks → IdeaRepository + ThoughtRepository
```

### 4.2 AI 推荐流程

```
用户点击推荐按钮（选择快速/综合）
  → MustDoViewModel.fetchRecommendations
  → [综合模式] prepareComprehensiveCandidates
    → 检查每个候选项目的摘要是否过期
    → 对过期项目并行生成摘要（AIExecutionCoordinator 重试）
    → 摘要写回 IdeaEntity
  → 组装输入 → AIExecutionCoordinator.run → DeepSeekAIService.recommendTasks
  → 校验推荐合法性 → 按顺序分配优先级
  → 用户逐条/批量接受
    → applyRecommendation → promoteToMustDo 或 createMustDoTask
```

### 4.3 日终结算流程

```
用户点击结束今天
  → DayManager.settleDay
  → 用户填写未完成任务备注
  → DayManager.gradeWithFallback (AI 评分，失败降级为基础评分)
  → 停止所有运行中任务
  → 保存评分到 DailySummaryEntity
  → archiveAndClearSettledTasks
    → 遍历所有必做项：标记 isSettled=true，计算实际耗时，写入结算备注
    → 更新来源想法状态（完成→completed，未完成→attempted）
    → 刷新项目推荐上下文时间
    → 项目无活跃任务时回退到 pending
```

### 4.4 项目推荐上下文刷新机制

以下操作会触发 `touchProjectRecommendationContext`，更新项目的推荐上下文时间：

- 项目标题、分类、描述、规划背景被编辑
- 项目备注新增或修改
- 绑定必做项的新增、解绑、标题变化
- 必做项状态变化（开始、完成、切换）
- 日终结算归档
- 必做项来源重新绑定
- 项目类型切换

## 5. AI 服务架构

### 5.1 服务抽象

```
AIServiceProtocol (协议)
  └── DeepSeekAIService (实现)
```

ViewModel 和 Manager 通过 `AIServiceProtocol` 调用 AI，实际实现为 DeepSeek API。

### 5.2 统一重试

所有 AI 调用都经过 `AIExecutionCoordinator`（actor）：

- 标准策略：最多 2 次尝试，间隔 1 秒
- 可重试错误：超时、网络不可用、HTTP 408/429/500/502/503/504
- 其他错误直接抛出，不重试

### 5.3 Prompt 管理

所有 prompt 集中在 `PromptTemplates`，包括：

| 方法 | 用途 |
|------|------|
| parseThoughts | 自然语言→结构化任务 |
| refineTasks | 根据用户指令修改解析结果 |
| classifyProjects | 判断任务是否为项目 |
| recommendTasks | 推荐必做项（快速/综合两种提示） |
| generateProjectRecommendationSummary | 生成项目推荐状态摘要 |
| generatePlanningBackgroundPrompt | 生成规划研究提示词 |
| analyzeProjectProgress | 分析项目进度 |
| cleanupIdeaPool | 清理建议 |
| generateDailyGrade | 日终评分 |
| appealGrade | 评分驳斥 |

## 6. 技术选型

| 领域 | 选型 | 说明 |
|------|------|------|
| UI 框架 | SwiftUI + MenuBarExtra | macOS 原生菜单栏应用 |
| 数据持久化 | SwiftData | 自动轻量迁移，Schema 驱动 |
| AI 服务 | DeepSeek API | 通过协议抽象，可扩展其他提供商 |
| 安全存储 | KeychainStore | API Key 存储在 Keychain |
| 并发模型 | Swift Concurrency | async/await + actor + TaskGroup |
| 计时引擎 | TimerEngine (actor) | 单任务/并行计时，状态隔离 |
