# NL Plan for Mac — 软件架构说明书（SAD）

> **文档编号**：NLPLAN-SAD-001  
> **产品名称**：NL Plan（暂定）  
> **文档版本**：v0.2  
> **日期**：2026-04-16  
> **作者**：架构团队  
> **状态**：草案

---

## 修订历史

| 版本 | 日期 | 修改人 | 修改内容 |
|------|------|--------|----------|
| v0.1 | 2026-04-14 | — | 初稿 |
| v0.2 | 2026-04-16 | — | 更新 AI 服务为 DeepSeek；更新文件结构；新增解析队列架构；更新数据流；移除 Combine 引用；更新接口签名 |

---

## 1. 引言

### 1.1 编写目的

本文档面向开发团队，定义 NL Plan for Mac 的系统架构、模块划分、数据流、关键设计决策和技术选型。作为编码实现的顶层指导文件，确保团队成员对系统结构达成一致理解。

### 1.2 参考资料

- [NL Plan PRD v0.2](./PRD.md)
- [NL Plan SRS v0.2](./SRS.md)

### 1.3 术语

| 术语 | 定义 |
|------|------|
| Menu Bar Extra | macOS 菜单栏常驻组件 |
| Popover | 点击菜单栏图标弹出的面板 |
| Session | 一次任务计时的起止记录 |
| Pool | 任务池（想法池 / 必做项） |
| Parse Queue | 解析队列，用户输入的串行处理列表 |

---

## 2. 架构目标与约束

### 2.1 架构目标

| 目标 | 说明 |
|------|------|
| 简洁性 | 自用工具，避免过度设计，优先可维护性 |
| 可扩展性 | AI 服务层必须可替换，数据层与 UI 解耦 |
| 离线优先 | 本地计时、本地存储不依赖网络，仅 AI 解析需要联网 |
| 响应性 | UI 不阻塞，AI 调用异步执行，队列处理不阻塞输入 |
| 数据安全 | API Key 入 Keychain，数据全部本地持久化 |

### 2.2 架构约束

| 约束 | 说明 |
|------|------|
| 语言 | Swift 5.9+ |
| 最低版本 | macOS 14.0 (Sonoma) |
| UI 框架 | SwiftUI（Menu Bar Extra + Popover） |
| 数据持久化 | SwiftData（macOS 14+ 原生方案） |
| 并发模型 | Swift Structured Concurrency (async/await, Actor) |
| 状态管理 | @Observable（不使用 Combine） |
| 分发 | Xcode 直接构建，不上架 App Store |

---

## 3. 系统架构总览

### 3.1 分层架构

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         Presentation Layer                                 │
│                       (SwiftUI Views)                                      │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐  │
│  │MenuBarView│ │PopoverView│ │SummaryView│ │HistoryView│ │SettingsView│  │
│  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘  │
│        └──────────┬──┴──────────┬──┘              │              │         │
│                   ▼             ▼                 ▼              │         │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────────────┐ │
│  │ParseQueueSection│ │ QueueDetailView │ │     MainContentView         │ │
│  └─────────────────┘ └─────────────────┘ │  (Page 路由容器)             │ │
│                                           └─────────────────────────────┘ │
│              ┌─────────────────────────────────────────┐                   │
│              │            ViewModel Layer               │                   │
│              │         (@Observable classes)            │                   │
│              └────────────────┬────────────────────────┘                   │
└───────────────────────────────┼─────────────────────────────────────────────┘
                                │
┌───────────────────────────────┼─────────────────────────────────────────────┐
│                      Domain Layer                                            │
│                   (Business Logic)                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐                  │
│  │ TaskManager  │  │ TimerEngine  │  │   DayManager    │                  │
│  │  (Actor)     │  │  (Actor)     │  │                  │                  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘                  │
│         │                 │                    │                             │
│         └──────────┬──────┘                    │                             │
│                    ▼                           ▼                             │
│           ┌────────────────────────────────────────┐                        │
│           │           AIServiceProtocol             │                        │
│           │        (AI 服务抽象接口)                  │                        │
│           └────────────────┬───────────────────────┘                        │
└────────────────────────────┼────────────────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────────────────┐
│                    Data Layer                                                 │
│                  (Persistence)                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐                  │
│  │ SwiftData    │  │ KeychainStore│  │ AppleNotesSync   │                  │
│  │ Repository   │  │ (API Key)    │  │ (AppleScript)    │                  │
│  └──────────────┘  └──────────────┘  └──────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 架构风格

采用 **分层架构 (Layered Architecture)** + **MVVM** 模式：

- **Presentation Layer**：纯 SwiftUI View，不包含业务逻辑
- **ViewModel Layer**：`@Observable` 类，持有 UI 状态，调用 Domain Layer
- **Domain Layer**：核心业务逻辑，使用 `Actor` 保证线程安全
- **Data Layer**：数据持久化、外部服务调用

**关键原则**：
1. **单向数据流**：ViewModel → Domain → Data，数据变更通过回调通知 UI
2. **依赖倒置**：Domain Layer 通过 Protocol 依赖 Data Layer，不直接依赖具体实现
3. **Actor 隔离**：计时器和任务管理器用 Actor 封装，避免数据竞争

---

## 4. 模块设计

### 4.1 模块总览

```
NLPlan/
├── App/                          # 应用入口
│   ├── NLPlanApp.swift           # @main 入口，MenuBarExtra 配置
│   ├── AppDelegate.swift         # 生命周期管理（右键菜单）
│   └── MainContentView.swift     # 页面路由容器（AppState.Page 驱动）
│
├── Presentation/                 # 表现层 — SwiftUI Views
│   ├── MenuBar/
│   │   └── MenuBarLabelView.swift     # 菜单栏常驻视图
│   ├── Popover/
│   │   ├── PopoverView.swift          # 主面板容器
│   │   ├── InputSection.swift         # 输入区（含 ParsedTaskRow 组件）
│   │   ├── ParseQueueSection.swift    # 解析队列列表
│   │   ├── IdeaPoolSection.swift      # 想法池区域
│   │   └── MustDoSection.swift        # 必做项列表
│   ├── QueueDetail/
│   │   └── QueueDetailView.swift      # 队列项详情页（全屏确认）
│   ├── Summary/
│   │   └── SummaryView.swift          # 日终总结页
│   ├── History/
│   │   └── HistoryView.swift          # 历史日历视图
│   └── Settings/
│       └── SettingsView.swift         # 设置页（API Key、模型、外观）
│
├── ViewModel/                    # 视图模型层
│   ├── AppState.swift            # 全局状态（Page 路由、ViewModel 工厂）
│   ├── InputViewModel.swift      # 输入区 + 解析队列管理
│   ├── IdeaPoolViewModel.swift   # 想法池状态
│   ├── MustDoViewModel.swift     # 必做项状态
│   ├── SummaryViewModel.swift    # 总结页状态
│   ├── HistoryViewModel.swift    # 历史视图状态
│   └── TimerViewModel.swift      # 计时器显示状态
│
├── Domain/                       # 领域层 — 核心业务逻辑
│   ├── Manager/
│   │   ├── TaskManager.swift     # 任务生命周期管理（Actor）
│   │   ├── TimerEngine.swift     # 计时引擎（Actor）
│   │   └── DayManager.swift      # 每日管理（评分、日切换）
│   ├── Model/
│   │   ├── AIModels.swift        # ParsedTask、DailyGrade 等 DTO
│   │   ├── ParseQueueItem.swift  # 解析队列项（@Observable）
│   │   └── DayStats.swift        # 每日统计数据
│   ├── Enum/
│   │   ├── TaskPool.swift        # 想法池 / 必做项
│   │   ├── TaskStatus.swift      # pending/running/paused/done
│   │   ├── TaskPriority.swift    # high/medium/low（预留）
│   │   ├── Grade.swift           # S/A/B/C/D
│   │   └── NLPlanError.swift     # 错误域定义
│   └── Service/
│       └── AIServiceProtocol.swift      # AI 服务抽象协议
│
├── Data/                         # 数据层 — 持久化与外部服务
│   ├── Persistence/
│   │   ├── TaskEntity.swift            # 任务 SwiftData 实体
│   │   ├── ThoughtEntity.swift         # 想法 SwiftData 实体
│   │   ├── SessionLogEntity.swift      # 计时记录 SwiftData 实体
│   │   ├── DailySummaryEntity.swift    # 日终总结 SwiftData 实体
│   │   └── Repository/
│   │       ├── TaskRepository.swift
│   │       ├── ThoughtRepository.swift
│   │       ├── SessionLogRepository.swift
│   │       └── SummaryRepository.swift
│   ├── AI/
│   │   ├── DeepSeekAIService.swift     # DeepSeek API 实现
│   │   ├── DeepSeekAPIModels.swift     # API 请求/响应 DTO
│   │   └── PromptTemplates.swift       # Prompt 模板管理
│   ├── Sync/
│   │   └── AppleNotesService.swift     # 备忘录同步（AppleScript）
│   └── Security/
│       └── KeychainStore.swift         # API Key 安全存储
│
├── Infrastructure/               # 基础设施
│   ├── Extensions/
│   │   └── Date+Extension.swift        # Date/Int 扩展
│   └── Constants/
│       └── AppConstants.swift          # 全局常量
│
└── Resources/                    # 资源文件
    └── Assets.xcassets
```

---

## 5. 核心模块详细设计

### 5.1 TaskManager（任务管理器）

**职责**：管理想法池和必做项的生命周期，协调 AI 解析和数据持久化。

```swift
actor TaskManager {

    // MARK: - 想法池操作

    /// 仅调用 AI 解析，不保存（供确认流程使用）
    func parseThoughts(rawText: String, existingTaskTitles: [String]) async throws -> [ParsedTask]

    /// 根据用户指令修改已解析的任务（供确认流程使用）
    func refineParsedTasks(originalInput: String, currentTasks: [ParsedTask], userInstruction: String) async throws -> [ParsedTask]

    /// 将已解析的任务保存到想法池（供确认流程使用）
    func saveParsedTasks(parsedTasks: [ParsedTask], rawText: String) async throws -> [TaskEntity]

    /// 提交自然语言 → AI 解析 → 进入想法池（一步到位）
    func submitThought(rawText: String) async throws -> [TaskEntity]

    /// 从想法池中挑选任务加入必做项
    func promoteToMustDo(taskId: UUID) async throws

    /// 将必做项移回想法池
    func demoteToIdeaPool(taskId: UUID, markAttempted: Bool) async throws

    /// 删除想法池中的任务
    func deleteFromIdeaPool(taskId: UUID) async throws

    // MARK: - 必做项操作

    /// 开始执行任务
    func startTask(taskId: UUID) async throws

    /// 标记任务完成
    func markComplete(taskId: UUID) async throws

    // MARK: - 查询

    func fetchIdeaPool() async throws -> [TaskEntity]
    func fetchMustDo(date: Date) async throws -> [TaskEntity]
    func fetchRunningTasks() async throws -> [TaskEntity]
}
```

**关键设计决策**：
- 使用 `actor` 而非 `class`，确保任务状态变更的线程安全
- 所有写操作通过 actor isolation 串行化，避免竞态条件
- 内部依赖 `AIServiceProtocol` 和 `TaskRepository`
- `parseThoughts` / `refineParsedTasks` / `saveParsedTasks` 三步拆分，支持用户确认流程

### 5.2 TimerEngine（计时引擎）

**职责**：管理任务的正计时，处理任务切换逻辑。

```swift
actor TimerEngine {

    private var activeTaskIds: Set<UUID> = []
    private var startTimes: [UUID: Date] = [:]
    private var allowParallel: Bool = false

    // MARK: - 计时控制

    /// 开始执行任务（如果并行关闭，先停止当前任务）
    /// 返回被停止任务的信息列表
    func startTask(_ taskId: UUID) -> [(taskId: UUID, startedAt: Date)]

    /// 停止指定任务
    func stopTask(_ taskId: UUID) -> (taskId: UUID, startedAt: Date)?

    /// 停止所有运行中任务
    func stopAll() -> [(taskId: UUID, startedAt: Date)]

    // MARK: - 查询

    func elapsedSeconds(for taskId: UUID) -> Int
    func activeTasks() -> [UUID]
    func hasActiveTasks() -> Bool
    func timerDisplay(for taskId: UUID) -> String
    func primaryTimerDisplay() -> String
}
```

**关键设计决策**：
- `startTask` 返回被停止任务的信息，调用方（TaskManager/ViewModel）负责持久化 SessionLog
- 计时精度：基于 `Date` 差值计算，不依赖 Timer tick。UI 层每秒刷新显示即可
- 并行模式通过 `allowParallel` 控制，V1 默认 `false`

### 5.3 DayManager（每日管理器）

**职责**：管理"一天"的生命周期，触发日终评分，处理跨天逻辑。

```swift
actor DayManager {

    /// 结束今天：停止所有任务 → 生成统计 → 调用 AI 评分
    func endDay() async throws -> DailySummaryEntity

    /// 获取今日统计（不触发 AI 评分）
    func todayStats() async throws -> DayStats

    /// 检查是否需要触发昨日的自动评分
    func checkAndGradeYesterday() async throws -> DailySummaryEntity?

    /// 同步日终总结到备忘录
    func syncToNotes(summary: DailySummaryEntity) async throws

    /// 跨天迁移：将昨日未完成的必做项移回想法池
    func migrateUnfinishedMustDo() async throws -> [TaskEntity]

    /// 驳斥评分：调用 AI 重新评分，每日最多 3 次
    func appealGrade(date: Date, userFeedback: String) async throws -> DailySummaryEntity

    func fetchTodaySummary() async throws -> DailySummaryEntity?
    func fetchHistory(from: Date, to: Date) async throws -> [DailySummaryEntity]
}
```

### 5.4 AI 服务抽象

```swift
/// AI 服务抽象协议 — 所有 AI 实现必须遵循
protocol AIServiceProtocol: Sendable {

    /// 解析自然语言为结构化任务列表
    /// - Parameters:
    ///   - input: 用户原始输入文本
    ///   - existingTaskTitles: 想法池中已有任务标题（用于去重）
    /// - Returns: 解析后的任务列表
    func parseThoughts(
        input: String,
        existingTaskTitles: [String]
    ) async throws -> [ParsedTask]

    /// 根据用户修改指令调整已解析的任务
    /// - Parameters:
    ///   - originalInput: 用户原始输入
    ///   - currentTasks: 当前解析结果
    ///   - userInstruction: 用户修改指令
    /// - Returns: 修改后的完整任务列表
    func refineTasks(
        originalInput: String,
        currentTasks: [ParsedTask],
        userInstruction: String
    ) async throws -> [ParsedTask]

    /// 日终评分
    func generateDailyGrade(
        summaryInput: DailySummaryInput
    ) async throws -> DailyGrade

    /// 驳斥评分：AI 根据用户反馈重新评分
    func appealGrade(
        originalGrade: DailyGrade,
        originalInput: DailySummaryInput,
        userFeedback: String
    ) async throws -> DailyGrade
}

/// 解析后的任务模型（DTO，非持久化）
struct ParsedTask: Sendable, Identifiable {
    let id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    let recommended: Bool
    let reason: String
}

/// 日终评分输入
struct DailySummaryInput: Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double
    let extraCompleted: Int
    let taskDetails: [TaskDetail]
}

/// 单个任务的完成详情（用于 AI 评分输入）
struct TaskDetail: Sendable, Identifiable {
    let id: UUID
    let title: String
    let estimatedMinutes: Int
    let actualMinutes: Int
    let completed: Bool
}

/// 日终评分输出
struct DailyGrade: Sendable {
    let grade: Grade
    let summary: String
    let stats: GradeStats
    let suggestion: String
    let gradingBasis: String
}

/// 评分统计数据
struct GradeStats: Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double
    let extraCompleted: Int
}
```

### 5.5 DeepSeek AI 实现（DeepSeekAIService）

```swift
/// DeepSeek API 默认实现
/// 兼容 OpenAI 格式
final class DeepSeekAIService: AIServiceProtocol {

    private let apiKey: String         // 从 Keychain 读取
    private let endpoint: URL          // https://api.deepseek.com/chat/completions
    private let urlSession: URLSession
    private let model: String          // "deepseek-chat" / "deepseek-reasoner"

    // MARK: - AIServiceProtocol

    func parseThoughts(input: String, existingTaskTitles: [String]) async throws -> [ParsedTask] {
        let prompt = PromptTemplates.parseThought(input: input, existingTaskTitles: existingTaskTitles)
        let responseContent = try await sendRequest(systemPrompt: "...", userPrompt: prompt)
        let parsedResponse = try parseJSON(responseContent, as: ParsedTasksResponse.self)
        return parsedResponse.tasks.map { ... }
    }

    func refineTasks(originalInput: String, currentTasks: [ParsedTask], userInstruction: String) async throws -> [ParsedTask] {
        let prompt = PromptTemplates.refineParsedTasks(...)
        let responseContent = try await sendRequest(...)
        return ...
    }

    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade { ... }
    func appealGrade(...) async throws -> DailyGrade { ... }

    // MARK: - Private

    private func sendRequest(systemPrompt: String, userPrompt: String) async throws -> String {
        // 1. 构建请求体（OpenAI 兼容格式）
        // 2. 设置 HTTP Header (Authorization: Bearer <apiKey>)
        // 3. 发送 POST 请求
        // 4. 解析 JSON 响应
        // 5. 超时（chat: 30s, reasoner: 更长），失败重试最多 2 次
    }
}
```

**调用链路**：

```
InputViewModel.submit()
    ↓
InputViewModel.processNextInQueue()      // 串行队列处理
    ↓
TaskManager.parseThoughts()              // actor 隔离
    ↓
AIServiceProtocol.parseThoughts()        // 协议调用，不依赖具体实现
    ↓
DeepSeekAIService.sendRequest()          // 具体实现
    ↓ HTTPS POST
DeepSeek API
```

---

## 6. 数据持久化设计

### 6.1 技术选型：SwiftData

**选择理由**：
- macOS 14+ 原生方案，与 SwiftUI 深度集成
- 无需手动管理 CoreData Stack
- 声明式模型定义，代码量少
- 自用工具，不需要跨平台兼容

### 6.2 模型定义

```swift
/// 想法输入
@Model
final class ThoughtEntity {
    @Attribute(.unique) var id: UUID
    var rawText: String
    var createdAt: Date
    var processed: Bool

    @Relationship(deleteRule: .cascade)
    var tasks: [TaskEntity] = []
}

/// 任务
@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    var aiRecommended: Bool
    var recommendationReason: String?
    var pool: String         // "idea_pool" / "must_do"
    var sortOrder: Int
    var status: String       // "pending" / "running" / "paused" / "done"
    var date: Date           // 任务所属日期
    var createdDate: Date    // 任务创建日期（跨天迁移后 date 变化但 createdDate 不变）
    var attempted: Bool      // 是否曾经尝试过（跨天迁移标记）

    @Relationship(deleteRule: .cascade, inverse: \SessionLogEntity.task)
    var sessionLogs: [SessionLogEntity] = []

    @Transient
    var totalElapsedSeconds: Int {
        sessionLogs.reduce(0) { $0 + $1.durationSeconds }
    }
}

/// 计时记录
@Model
final class SessionLogEntity {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var date: Date           // 记录所属日期

    var task: TaskEntity?
}

/// 日终总结
@Model
final class DailySummaryEntity {
    @Attribute(.unique) var id: UUID
    var date: Date
    var grade: String        // "S" / "A" / "B" / "C" / "D"
    var summary: String
    var suggestion: String?
    var totalPlannedMinutes: Int
    var totalActualMinutes: Int
    var completedCount: Int
    var totalCount: Int
    var syncedToNotes: Bool
    var createdAt: Date
    var appealCount: Int
    var gradingBasis: String?
}
```

### 6.3 ModelContainer 配置

```swift
@main
struct NLPlanApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                ThoughtEntity.self,
                TaskEntity.self,
                SessionLogEntity.self,
                DailySummaryEntity.self
            ])
            let config = ModelConfiguration(schema: schema)
            let mc = try ModelContainer(for: schema, configurations: [config])
            container = mc

            let engine = TimerEngine()
            _appState = State(initialValue: AppState(modelContainer: mc, timerEngine: engine))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MainContentView()
                .modelContainer(container)
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### 6.4 Repository 模式

每个实体对应一个 Repository，封装 SwiftData 操作：

```swift
class TaskRepository {
    func create(title:category:estimatedMinutes:...) throws -> TaskEntity
    func update(_ task: TaskEntity) throws
    func delete(_ task: TaskEntity) throws
    func fetchById(_ id: UUID) throws -> TaskEntity?
    func fetchTasks(date: Date, pool: TaskPool) throws -> [TaskEntity]
    func fetchAllIdeaPoolTasks() throws -> [TaskEntity]
    func fetchActiveRunningTasks() throws -> [TaskEntity]
    func moveToMustDo(_ task: TaskEntity) throws
    func moveToIdeaPool(_ task: TaskEntity, markAttempted: Bool) throws
    func markComplete(_ task: TaskEntity) throws
    func updateStatus(_ task: TaskEntity, status: TaskStatus) throws
    func migrateUnfinishedMustDo() throws
}
```

> **注意**：SwiftData 的 `ModelContext` 不是线程安全的，Repository 操作在主线程执行。

---

## 7. 数据流设计

### 7.1 核心数据流 — 输入到想法池（队列模式）

```
用户输入文本
     │
     ▼
InputViewModel.submit()
     │  1. 验证输入（非空、长度）
     │  2. 创建 ParseQueueItem(.waiting)
     │  3. 追加到 queueItems 数组
     │  4. 清空输入框（立即可用）
     │  5. 调用 processNextInQueue()
     │
     ▼
InputViewModel.processNextInQueue()      // 串行递归处理
     │  1. 检查是否有 .processing 项 → 有则 return
     │  2. 取第一个 .waiting 项 → 设为 .processing
     │  3. await TaskManager.parseThoughts()
     │  4. 成功 → 设为 .completed，存储 parsedTasks
     │     失败 → 设为 .failed，存储 errorMessage
     │  5. 递归调用 processNextInQueue()
     │
     ▼
队列列表 UI 更新（ParseQueueSection）
     │  用户点击已完成项
     │
     ▼
AppState.currentPage = .queueDetail(itemID)
     │  路由到 QueueDetailView
     │
     ▼
用户在详情页确认/编辑/与 AI 对话
     │
     ▼
InputViewModel.confirmQueueItem(id:)
     │  1. await TaskManager.saveParsedTasks()
     │  2. 移除队列项
     │  3. 调用 onSubmitSuccess 回调
     │
     ▼
IdeaPoolViewModel.refresh()  → UI 自动更新
```

### 7.2 核心数据流 — 任务执行与切换

```
用户点击必做项
     │
     ▼
MustDoViewModel.startTask(id:)
     │
     ▼
TaskManager.startTask(taskId)
     │  1. 验证任务存在且在 must_do 池
     │  2. await TimerEngine.startTask(taskId)
     │     → 如果 allowParallel == false，停止当前任务
     │     → 返回被停止任务信息
     │  3. 持久化被停止任务的 SessionLog
     │  4. 为新任务创建 open session
     │  5. 更新 TaskEntity.status
     │
     ▼
AppState 更新计时显示
     │  菜单栏每秒刷新
     │
     ▼
TimerViewModel / MenuBarLabelView
     │  调用 TimerEngine.elapsedSeconds(for:)
     │  更新显示文本
```

### 7.3 核心数据流 — 日终评分

```
用户点击"结束今天"
     │
     ▼
SummaryViewModel.endDay()
     │
     ▼
DayManager.endDay()
     │  1. 调用 TimerEngine.stopAll()
     │  2. 持久化所有未关闭的 SessionLog
     │  3. 汇总今日统计（完成数、总时长、偏差率）
     │  4. 构造 DailySummaryInput
     │  5. 调用 AIService.generateDailyGrade()
     │  6. 保存 DailySummaryEntity
     │
     ▼
返回 DailySummaryEntity 给 ViewModel
     │
     ▼
SummaryView 展示评分结果
     │  用户可选择"同步到备忘录"
```

---

## 8. 状态管理设计

### 8.1 应用级状态

```swift
/// 全局应用状态
@Observable
final class AppState {

    enum AppearanceMode: String, CaseIterable {
        case system, light, dark
    }

    enum Page: Equatable {
        case main
        case summary
        case history
        case settings
        case queueDetail(UUID)    // 关联队列项 ID
    }

    // MARK: - Dependencies
    let modelContainer: ModelContainer
    let timerEngine: TimerEngine

    // MARK: - Timer Display
    var isTimerRunning: Bool = false
    var timerDisplayText: String = ""
    var currentTaskTitle: String = ""

    // MARK: - Navigation
    var currentPage: Page = .main
    var appearanceMode: AppearanceMode = .system

    // MARK: - ViewModels（全局持有，避免面板关闭后重建丢失状态）
    var inputViewModel: InputViewModel?
    var ideaPoolViewModel: IdeaPoolViewModel?
    var mustDoViewModel: MustDoViewModel?

    // MARK: - API Key
    var isAPIKeyConfigured: Bool = false

    // MARK: - Factory
    func makeAIService() -> AIServiceProtocol
}
```

### 8.2 页面路由

`MainContentView` 根据 `appState.currentPage` 切换显示不同容器视图：

| Page 值 | 容器视图 |
|---------|---------|
| `.main` | PopoverContainerView |
| `.summary` | SummaryContainerView |
| `.history` | HistoryContainerView |
| `.settings` | SettingsContainerView |
| `.queueDetail(UUID)` | QueueDetailContainerView |

### 8.3 ViewModel 层状态

```swift
/// 输入区 ViewModel（队列模式）
@Observable
final class InputViewModel {

    var inputText: String = ""
    var errorMessage: String?
    var successMessage: String?

    /// 解析队列
    var queueItems: [ParseQueueItem] = []

    /// 当前正在 AI 调整的队列项 ID
    var activeDetailItemID: UUID?

    /// 对话输入（详情页用）
    var chatInput: String = ""

    /// 提交成功回调
    var onSubmitSuccess: (([UUID]) async -> Void)?

    // MARK: - 队列操作

    /// 提交 → 入队 → 触发串行处理
    func submit() async

    /// 确认队列项 → 保存到想法池 → 移除
    func confirmQueueItem(id: UUID) async

    /// 取消队列项 → 移除（不可取消 processing 项）
    func cancelQueueItem(id: UUID)

    /// 重试失败项
    func retryQueueItem(id: UUID) async

    /// 与 AI 对话修改解析结果
    func sendModification(queueItemID: UUID) async

    /// 编辑/删除解析结果中的单个任务
    func updateParsedTask(queueItemID:taskIndex:title:category:estimatedMinutes:)
    func removeParsedTask(queueItemID:taskIndex:)

    /// 判断指定队列项是否正在 AI 调整中
    func isItemChatProcessing(id: UUID) -> Bool
}
```

### 8.4 计时器刷新机制

```
┌──────────────┐     每秒 tick      ┌─────────────────┐
│  Timer       │ ──────────────────→ │  TimerViewModel │
│  (Timer      │                     │                 │
│   .publish)  │                     │  await engine   │
└──────────────┘                     │  .elapsedSeconds│
                                     │  更新 display   │
                                     └──────┬──────────┘
                                            │ @Observable
                                            ▼
                                     ┌─────────────────┐
                                     │ MenuBarLabelView │
                                     │ 显示 ⏱ 00:32:15 │
                                     └─────────────────┘
```

**实现**：

```swift
/// 菜单栏计时显示 ViewModel
@Observable
final class TimerViewModel {

    var displayText: String = ""
    var taskTitle: String = ""

    private let timerEngine: TimerEngine

    init(timerEngine: TimerEngine) {
        self.timerEngine = timerEngine
        startTicker()
    }

    private func startTicker() {
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    guard let self else { return }
                    let activeIds = await self.timerEngine.activeTasks()
                    if let firstId = activeIds.first {
                        self.displayText = await self.timerEngine.timerDisplay(for: firstId)
                    } else {
                        self.displayText = ""
                        self.taskTitle = ""
                    }
                }
            }
            .store(in: &cancellables)
    }
}
```

> 注：TimerViewModel 内部使用 Combine 的 `Timer.publish` + `sink` 作为定时器源，但外部状态管理使用 `@Observable`，不对外暴露 Combine。

---

## 9. 关键设计决策

### 9.1 为什么选 SwiftData 而非 CoreData？

| 维度 | SwiftData | CoreData |
|------|-----------|----------|
| 最低版本 | macOS 14+（本项目已要求） | macOS 10.12+ |
| 代码量 | `@Model` 宏，极少样板代码 | 需手动配置 NSManagedObjectModel |
| SwiftUI 集成 | `@Query` 原生支持 | 需要FetchRequest |
| 学习曲线 | 低 | 高 |
| 结论 | ✅ 选用 | — |

### 9.2 为什么用 Actor 而非 Lock/Queue？

| 维度 | Actor | NSLock / DispatchQueue |
|------|-------|------------------------|
| 安全性 | 编译期保证数据隔离 | 运行时可能死锁 |
| 可读性 | async/await 自然表达 | 嵌套回调或 lock/unlock |
| 性能 | 无竞争时不阻塞 | 锁竞争时阻塞线程 |
| 结论 | ✅ 选用（Swift 原生并发模型） | — |

### 9.3 为什么计时用 Date 差值而非累加？

| 方案 | 说明 | 问题 |
|------|------|------|
| ❌ 累加 tick | 每次 timer tick +1 秒 | 应用暂停/后台时丢失计时 |
| ✅ Date 差值 | 记录 startTime，实时计算 Date.now - startTime | 准确，不受后台影响 |

### 9.4 为什么 MenuBarExtra 用 `.window` 样式？

| 样式 | 说明 | 选择 |
|------|------|------|
| `.menu` | 下拉菜单样式，不支持复杂 UI | ❌ |
| ✅ `.window` | 独立窗口样式，支持完整 SwiftUI 视图 | ✅ 适合 Popover 交互 |

### 9.5 为什么解析队列用递归而非 AsyncStream？

| 方案 | 说明 | 问题 |
|------|------|------|
| ❌ AsyncStream | 需要维护流的生命周期，增加复杂度 | 过度设计 |
| ✅ 递归 processNextInQueue | 简单直观，await 挂起时不阻塞 MainActor | 代码少，易维护 |

### 9.6 为什么详情页用全屏 Popover 而非 Sheet？

MenuBarExtra 的 `.window` 样式下，Sheet 弹窗可能导致焦点问题和层级异常。全屏替换 Popover 内容（通过 `AppState.Page` 路由）更稳定可靠。

---

## 10. 并发与线程模型

```
┌─────────────────────────────────────┐
│           Main Thread               │
│  SwiftUI Views / @Observable VMs    │
│  UI 更新、用户交互响应               │
└──────────────┬──────────────────────┘
               │ async call
               ▼
┌─────────────────────────────────────┐
│     Swift Concurrency Pool          │
│                                     │
│  ┌──────────────┐  ┌─────────────┐ │
│  │ TaskManager   │  │ TimerEngine │ │
│  │ (Actor)       │  │ (Actor)     │ │
│  └──────┬───────┘  └─────────────┘ │
│         │                           │
│         │ async call                │
│         ▼                           │
│  ┌──────────────┐                   │
│  │ DeepSeekAI   │                   │
│  │ Service      │  ← URLSession    │
│  │ (class)      │    异步网络请求    │
│  └──────────────┘                   │
│                                     │
│  ┌──────────────┐                   │
│  │ Repository   │  ← SwiftData     │
│  │ (class)      │    主线程写入     │
│  └──────────────┘                   │
└─────────────────────────────────────┘
```

**规则**：
1. UI 操作必须在 Main Thread
2. Actor 内部逻辑在 Cooperative Thread Pool 执行
3. SwiftData 写操作在 Main Thread（SwiftData 限制）
4. 网络请求在 URLSession 的后台线程

---

## 11. 错误处理策略

### 11.1 错误域定义

```swift
enum NLPlanError: LocalizedError {
    // 输入错误
    case emptyInput
    case inputTooLong(max: Int)

    // AI 服务错误
    case aiServiceUnavailable
    case aiRequestTimeout
    case aiResponseParseError
    case aiAPIError(statusCode: Int, message: String)

    // 数据错误
    case dataSaveFailed(underlying: Error)
    case dataNotFound(entity: String, id: UUID)

    // 同步错误
    case notesSyncFailed(underlying: Error)

    // 业务错误
    case appealLimitExceeded
    case taskNotInExpectedPool(expected: TaskPool, actual: TaskPool)
    case apiKeyNotConfigured

    // 网络错误
    case networkUnavailable
}
```

### 11.2 错误传播链路

```
Data Layer (throw NLPlanError)
    ↓ throws
Domain Layer (try/catch + 业务逻辑判断)
    ↓ throws
ViewModel (try/catch → 更新 errorMessage 状态)
    ↓ @Observable
View (显示错误提示)
```

### 11.3 降级策略

| 场景 | 降级方案 |
|------|----------|
| AI 服务不可用 | 队列项标记 failed，可重试，不影响其他队列项 |
| 日终 AI 评分失败 | 使用基于规则的基础评分（仅按完成率计算等级） |
| 备忘录同步失败 | 提示用户重试，提供"复制到剪贴板"备选 |
| 网络断开 | 本地计时正常运行，队列项等待重试 |

---

## 12. 安全设计

| 项目 | 方案 |
|------|------|
| API Key 存储 | `KeychainStore` 封装，使用 macOS Keychain Services |
| 网络传输 | HTTPS (TLS 1.2+)，URLSession 默认行为 |
| 本地数据 | SwiftData 默认存储在 Application Support，受 macOS 沙盒保护 |
| 敏感日志 | Release 构建不输出 API Key 和用户输入内容 |

---

## 13. 性能设计

| 关注点 | 方案 |
|--------|------|
| 冷启动 | MenuBarExtra 轻量初始化，SwiftData lazy load |
| 计时精度 | 基于 Date 差值，非累加 tick |
| UI 流畅度 | AI 调用异步，不阻塞主线程；队列处理不阻塞输入 |
| 内存 | 无大量图片/缓存，预计 < 50MB |
| 查询性能 | SwiftData 按日期 + pool 建索引 |

### 13.1 SwiftData 索引

```swift
@Model
final class TaskEntity {
    // ...

    #Index<TaskEntity>([\.date, \.pool], [\.status], [\.date])
}
```

---

## 14. 测试策略

### 14.1 测试分层

| 层级 | 测试类型 | 目标 | 工具 |
|------|----------|------|------|
| Data | 单元测试 | Repository CRUD、AI 响应解析 | XCTest |
| Domain | 单元测试 | TaskManager 逻辑、TimerEngine 切换、评分规则 | XCTest |
| ViewModel | 单元测试 | 状态变更、错误处理、队列处理 | XCTest |
| UI | UI 测试 | 核心流程端到端 | XCUITest |

### 14.2 Mock 策略

```swift
/// AI 服务 Mock，用于 Domain/ViewModel 测试
final class MockAIService: AIServiceProtocol {
    var mockParsedTasks: [ParsedTask] = []
    var mockGrade: DailyGrade?
    var shouldThrow: Bool = false

    func parseThoughts(input: String, existingTaskTitles: [String]) async throws -> [ParsedTask] {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        return mockParsedTasks
    }

    func refineTasks(originalInput: String, currentTasks: [ParsedTask], userInstruction: String) async throws -> [ParsedTask] {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        return currentTasks
    }

    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        return mockGrade!
    }

    func appealGrade(originalGrade: DailyGrade, originalInput: DailySummaryInput, userFeedback: String) async throws -> DailyGrade {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        return mockGrade ?? DailyGrade(grade: .b, summary: "Mock", stats: GradeStats(...), suggestion: "Mock", gradingBasis: "Mock")
    }
}
```

### 14.3 关键测试用例

| 用例 | 覆盖模块 | 描述 |
|------|----------|------|
| 输入空文本 → 不提交 | InputViewModel | 验证输入校验 |
| 输入有效文本 → 入队 → AI 解析 → 用户确认 → 进入想法池 | TaskManager + InputViewModel | 验证完整队列流程 |
| AI 失败 → 队列项标记 failed → 重试 | InputViewModel | 验证降级策略 |
| 连续输入 3 次 → 队列串行处理 | InputViewModel | 验证串行队列机制 |
| 点击任务A → 点击任务B → A 停止，B 开始 | TimerEngine | 验证切换逻辑 |
| 结束今天 → 停止所有 → AI 评分 → 存储 | DayManager | 验证日终流程 |

---

## 15. 依赖管理

### 15.1 外部依赖

V1 不引入任何第三方依赖。

| 需求 | 方案 |
|------|------|
| HTTP 请求 | URLSession（系统原生） |
| JSON 解析 | Foundation Codable |
| 数据库 | SwiftData（系统原生） |
| Keychain | Security framework（系统原生） |
| 定时器 | Foundation Timer |
| AppleScript | Process / NSAppleScript |

### 15.2 零依赖的理由

- 功能范围明确，系统框架完全覆盖
- 自用工具，无需跨平台
- 避免依赖版本管理和维护负担
- 减少构建复杂度

---

## 16. 部署架构

```
开发者 Mac
    │
    ├── Xcode 构建 NLPlan.app
    │
    ├── 签名：Ad Hoc / Developer ID（不上架 App Store）
    │
    ├── 安装：拖入 /Applications 或直接运行
    │
    └── 运行时：
         ├── 本地：SwiftData 数据库（~/Library/Application Support/NLPlan/）
         ├── Keychain：API Key
         └── 网络：HTTPS → DeepSeek API
```

---

## 17. 后续演进预留

| 版本 | 架构调整 |
|------|----------|
| V1.1 | `AppleNotesService` 实现同步；Repository 增加导出方法 |
| V1.2 | `TimerEngine` 增加 `allowParallel` 配置项；ViewModel 增加并行 UI |
| V2.0 | 新增 `AIServiceFactory`，支持运行时切换 AI 服务；新增配置 UI |
| V2.0 | 新增 `ReportService`，周报/月报聚合；新增 `ReportView` |
