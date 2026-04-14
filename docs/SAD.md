# NL Plan for Mac — 软件架构说明书（SAD）

> **文档编号**：NLPLAN-SAD-001  
> **产品名称**：NL Plan（暂定）  
> **文档版本**：v0.1  
> **日期**：2026-04-14  
> **作者**：架构团队  
> **状态**：草案

---

## 修订历史

| 版本 | 日期 | 修改人 | 修改内容 |
|------|------|--------|----------|
| v0.1 | 2026-04-14 | — | 初稿 |

---

## 1. 引言

### 1.1 编写目的

本文档面向开发团队，定义 NL Plan for Mac 的系统架构、模块划分、数据流、关键设计决策和技术选型。作为编码实现的顶层指导文件，确保团队成员对系统结构达成一致理解。

### 1.2 参考资料

- [NL Plan PRD v0.1](./PRD.md)
- [NL Plan SRS v0.1](./SRS.md)

### 1.3 术语

| 术语 | 定义 |
|------|------|
| Menu Bar Extra | macOS 菜单栏常驻组件 |
| Popover | 点击菜单栏图标弹出的面板 |
| Session | 一次任务计时的起止记录 |
| Pool | 任务池（想法池 / 必做项） |

---

## 2. 架构目标与约束

### 2.1 架构目标

| 目标 | 说明 |
|------|------|
| 简洁性 | 自用工具，避免过度设计，优先可维护性 |
| 可扩展性 | AI 服务层必须可替换，数据层与 UI 解耦 |
| 离线优先 | 本地计时、本地存储不依赖网络，仅 AI 解析需要联网 |
| 响应性 | UI 不阻塞，AI 调用异步执行 |
| 数据安全 | API Key 入 Keychain，数据全部本地持久化 |

### 2.2 架构约束

| 约束 | 说明 |
|------|------|
| 语言 | Swift 5.9+ |
| 最低版本 | macOS 14.0 (Sonoma) |
| UI 框架 | SwiftUI（Menu Bar Extra + Popover） |
| 数据持久化 | SwiftData（macOS 14+ 原生方案） |
| 并发模型 | Swift Structured Concurrency (async/await, Actor) |
| 分发 | Xcode 直接构建，不上架 App Store |

---

## 3. 系统架构总览

### 3.1 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                      Presentation Layer                      │
│                    (SwiftUI Views)                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │MenuBarView│  │PopoverView│  │SummaryView│  │HistoryView│  │SettingsView│  │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘   │
│        └──────────┬──┴──────────┬──┘              │         │
│                   ▼             ▼                 ▼         │
│              ┌─────────────────────────────────────────┐    │
│              │            ViewModel Layer               │    │
│              │   (ObservableObject / @Observable)       │    │
│              └────────────────┬────────────────────────┘    │
└───────────────────────────────┼─────────────────────────────┘
                                │
┌───────────────────────────────┼─────────────────────────────┐
│                      Domain Layer                            │
│                   (Business Logic)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ TaskManager  │  │ TimerEngine  │  │   DayManager    │  │
│  │  (Actor)     │  │  (Actor)     │  │                  │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                    │             │
│         └──────────┬──────┘                    │             │
│                    ▼                           ▼             │
│           ┌────────────────────────────────────────┐        │
│           │           AIServiceProtocol             │        │
│           │        (AI 服务抽象接口)                  │        │
│           └────────────────┬───────────────────────┘        │
└────────────────────────────┼────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────┐
│                    Data Layer                                 │
│                  (Persistence)                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ SwiftData    │  │ KeychainStore│  │ AppleNotesSync   │  │
│  │ Repository   │  │ (API Key)    │  │ (AppleScript)    │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 架构风格

采用 **分层架构 (Layered Architecture)** + **MVVM** 模式：

- **Presentation Layer**：纯 SwiftUI View，不包含业务逻辑
- **ViewModel Layer**：`@Observable` 类，持有 UI 状态，调用 Domain Layer
- **Domain Layer**：核心业务逻辑，使用 `Actor` 保证线程安全
- **Data Layer**：数据持久化、外部服务调用

**关键原则**：
1. **单向数据流**：ViewModel → Domain → Data，数据变更通过 Combine/回调通知 UI
2. **依赖倒置**：Domain Layer 通过 Protocol 依赖 Data Layer，不直接依赖具体实现
3. **Actor 隔离**：计时器和任务管理器用 Actor 封装，避免数据竞争

---

## 4. 模块设计

### 4.1 模块总览

```
NLPlan/
├── App/                          # 应用入口
│   ├── NLPlanApp.swift           # @main 入口，MenuBarExtra 配置
│   └── AppDelegate.swift         # 生命周期管理
│
├── Presentation/                 # 表现层 — SwiftUI Views
│   ├── MenuBar/
│   │   └── MenuBarView.swift     # 菜单栏常驻视图
│   ├── Popover/
│   │   ├── PopoverView.swift     # 主面板容器
│   │   ├── InputSection.swift    # 输入区
│   │   ├── IdeaPoolSection.swift # 想法池区域
│   │   └── MustDoSection.swift   # 必做项列表
│   ├── Summary/
│   │   └── SummaryView.swift     # 日终总结页
│   ├── History/
│   │   └── HistoryView.swift     # 历史日历视图（日历格，每格显示日期+评分）
│   └── Settings/
│       └── SettingsView.swift    # 设置页
│
├── ViewModel/                    # 视图模型层
│   ├── AppViewModel.swift        # 全局状态管理
│   ├── InputViewModel.swift      # 输入区状态
│   ├── IdeaPoolViewModel.swift   # 想法池状态
│   ├── MustDoViewModel.swift     # 必做项状态
│   ├── TimerViewModel.swift      # 计时器显示状态
│   ├── SummaryViewModel.swift    # 总结页状态
│   └── HistoryViewModel.swift    # 历史日历视图状态
│
├── Domain/                       # 领域层 — 核心业务逻辑
│   ├── Manager/
│   │   ├── TaskManager.swift     # 任务生命周期管理（Actor）
│   │   ├── TimerEngine.swift     # 计时引擎（Actor）
│   │   └── DayManager.swift      # 每日管理（评分、日切换）
│   ├── Model/
│   │   ├── Thought.swift         # 想法输入实体
│   │   ├── Task.swift            # 任务实体（含状态机）
│   │   ├── SessionLog.swift      # 计时记录实体
│   │   └── DailySummary.swift    # 日终总结实体
│   ├── Enum/
│   │   ├── TaskPool.swift        # 想法池 / 必做项
│   │   ├── TaskStatus.swift      # pending/running/paused/done
│   │   └── Grade.swift           # S/A/B/C/D
│   └── Service/
│       ├── AIServiceProtocol.swift      # AI 服务抽象协议
│       ├── AIRequest.swift              # 请求模型
│       └── AIResponse.swift             # 响应模型
│
├── Data/                         # 数据层 — 持久化与外部服务
│   ├── Persistence/
│   │   ├── SwiftDataContainer.swift     # SwiftData ModelContainer 配置
│   │   └── Repository/
│   │       ├── ThoughtRepository.swift  # 想法数据操作
│   │       ├── TaskRepository.swift     # 任务数据操作
│   │       ├── SessionLogRepository.swift
│   │       └── SummaryRepository.swift
│   ├── AI/
│   │   ├── ZhipuAIService.swift         # 智谱 GLM-5.1 实现
│   │   ├── ZhipuAPIModels.swift         # API 请求/响应 DTO
│   │   └── PromptTemplates.swift        # Prompt 模板管理
│   ├── Sync/
│   │   └── AppleNotesService.swift      # 备忘录同步（AppleScript）
│   └── Security/
│       └── KeychainStore.swift          # API Key 安全存储
│
├── Infrastructure/               # 基础设施
│   ├── Network/
│   │   └── NetworkMonitor.swift         # 网络状态监控
│   ├── Extensions/
│   │   ├── Date+Extension.swift
│   │   ├── String+Extension.swift
│   │   └── Color+Extension.swift
│   └── Constants/
│       └── AppConstants.swift           # 全局常量
│
└── Resources/                    # 资源文件
    ├── Assets.xcassets
    └── Localizable.strings        # 多语言（预留）
```

---

## 5. 核心模块详细设计

### 5.1 TaskManager（任务管理器）

**职责**：管理想法池和必做项的生命周期，协调 AI 解析和数据持久化。

```swift
actor TaskManager {
    
    // MARK: - 想法池操作
    
    /// 提交自然语言 → AI 解析 → 进入想法池
    func submitThought(rawText: String) async throws -> [Task]
    
    /// 从想法池中挑选任务加入必做项
    func promoteToMustDo(taskIds: [UUID]) async throws
    
    /// 将必做项移回想法池
    func demoteToIdeaPool(taskId: UUID) async throws
    
    /// 删除想法池中的任务
    func deleteFromIdeaPool(taskId: UUID) async throws
    
    // MARK: - 必做项操作
    
    /// 调整必做项顺序
    func reorderMustDo(taskId: UUID, to position: Int) async throws
    
    /// 标记任务完成
    func markComplete(taskId: UUID) async throws
    
    // MARK: - 查询
    
    /// 获取指定日期的想法池任务
    func fetchIdeaPool(date: Date) async -> [Task]
    
    /// 获取指定日期的必做项
    func fetchMustDo(date: Date) async -> [Task]
}
```

**关键设计决策**：
- 使用 `actor` 而非 `class`，确保任务状态变更的线程安全
- 所有写操作通过 actor isolation 串行化，避免竞态条件
- 内部依赖 `AIServiceProtocol` 和 `TaskRepository`

### 5.2 TimerEngine（计时引擎）

**职责**：管理任务的正计时，处理任务切换逻辑。

```swift
actor TimerEngine {
    
    /// 当前正在计时的任务 ID（支持多个，默认最多 1 个）
    private var activeTaskIds: Set<UUID> = []
    
    /// 计时开始时间记录
    private var startTimes: [UUID: Date] = [:]
    
    /// 是否允许并行计时
    private var allowParallel: Bool = false
    
    // MARK: - 计时控制
    
    /// 开始执行任务（如果并行关闭，先停止当前任务）
    func startTask(_ taskId: UUID) async throws -> SessionLog?
    // 返回被停止任务的 SessionLog（如有）
    
    /// 停止指定任务，返回 SessionLog
    func stopTask(_ taskId: UUID) async -> SessionLog?
    
    /// 停止所有运行中任务
    func stopAll() async -> [SessionLog]
    
    // MARK: - 查询
    
    /// 获取指定任务当前已计时的总秒数
    func elapsedSeconds(for taskId: UUID) async -> Int
    
    /// 获取当前活跃任务列表
    func activeTasks() async -> [UUID]
    
    /// 获取当前计时显示文本（如 "00:32:15"）
    func timerDisplay(for taskId: UUID) async -> String
}
```

**关键设计决策**：
- `startTask` 返回 `SessionLog?`，调用方（ViewModel）负责持久化
- 计时精度：基于 `Date` 差值计算，不依赖 Timer tick。UI 层每秒刷新显示即可
- 并行模式通过 `allowParallel` 控制，V1 默认 `false`

### 5.3 DayManager（每日管理器）

**职责**：管理"一天"的生命周期，触发日终评分，处理跨天逻辑。

```swift
actor DayManager {
    
    /// 结束今天：停止所有任务 → 生成统计 → 调用 AI 评分
    func endDay() async throws -> DailySummary
    
    /// 获取今日统计（不触发 AI 评分）
    func todayStats() async -> DayStats
    
    /// 检查是否需要触发昨日的自动评分
    func checkAndGradeYesterday() async -> DailySummary?
    
    /// 同步日终总结到备忘录
    func syncToNotes(summary: DailySummary) async throws
    
    /// 跨天迁移：将昨日未完成的必做项移回想法池
    /// - 已开始过的任务标记 `attempted = true`
    /// - 未开始的任务仅移动，不标记
    func migrateUnfinishedMustDo() async throws
    
    /// 驳斥评分：调用 AI 重新评分，每日最多 3 次
    /// - Returns: 新评分结果（含评分依据）
    /// - Throws: 超过 3 次限制时抛出错误
    func appealGrade(userFeedback: String) async throws -> DailyGrade
}
```

### 5.4 AI 服务抽象

```swift
/// AI 服务抽象协议 — 所有 AI 实现必须遵循
protocol AIServiceProtocol: Sendable {
    
    /// 解析自然语言为结构化任务列表
    /// - Parameters:
    ///   - input: 用户原始输入文本
    ///   - existingTasks: 想法池中已有任务（用于去重）
    /// - Returns: 解析后的任务列表
    func parseThoughts(
        input: String,
        existingTasks: [Task]
    ) async throws -> [ParsedTask]
    
    /// 日终评分
    /// - Parameter summaryInput: 当日任务完成数据
    /// - Returns: 评分结果
    func generateDailyGrade(
        summaryInput: DailySummaryInput
    ) async throws -> DailyGrade
    
    /// 驳斥评分：AI 根据用户反馈重新评分
    /// - Parameters:
    ///   - originalGrade: 原始评分结果
    ///   - originalInput: 原始评分输入数据
    ///   - userFeedback: 用户驳斥理由
    /// - Returns: 重新评分结果（含评分依据）
    func appealGrade(
        originalGrade: DailyGrade,
        originalInput: DailySummaryInput,
        userFeedback: String
    ) async throws -> DailyGrade
}

/// 解析后的任务模型（DTO，非持久化）
struct ParsedTask: Sendable {
    let title: String
    let category: String
    let estimatedMinutes: Int
    let priority: TaskPriority
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
struct TaskDetail: Sendable {
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
}

/// 评分统计数据
struct GradeStats: Sendable {
    let totalTasks: Int             // 必做项总数
    let completedTasks: Int         // 完成数
    let totalPlannedMinutes: Int    // 计划总时长
    let totalActualMinutes: Int     // 实际总时长
    let deviationRate: Double       // 时间偏差率
    let extraCompleted: Int         // 额外完成想法池任务数
}
```

### 5.5 智谱 AI 实现（ZhipuAIService）

```swift
/// 智谱 GLM-5.1 默认实现
final class ZhipuAIService: AIServiceProtocol, @unchecked Sendable {
    
    private let apiKey: String         // 从 Keychain 读取
    private let endpoint: URL
    private let urlSession: URLSession
    
    // MARK: - AIServiceProtocol
    
    func parseThoughts(input: String, existingTasks: [Task]) async throws -> [ParsedTask] {
        let prompt = PromptTemplates.parseThought(
            input: input,
            existingTasks: existingTasks
        )
        let response: ZhipuAPIResponse = try await sendRequest(prompt: prompt)
        return try parseTasksResponse(response)
    }
    
    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade {
        let prompt = PromptTemplates.dailyGrade(input: summaryInput)
        let response: ZhipuAPIResponse = try await sendRequest(prompt: prompt)
        return try parseGradeResponse(response)
    }
    
    func appealGrade(originalGrade: DailyGrade, originalInput: DailySummaryInput, userFeedback: String) async throws -> DailyGrade {
        let prompt = PromptTemplates.appealGrade(
            originalGrade: originalGrade,
            originalInput: originalInput,
            userFeedback: userFeedback
        )
        let response: ZhipuAPIResponse = try await sendRequest(prompt: prompt)
        return try parseGradeResponse(response)
    }
    
    // MARK: - Private
    
    private func sendRequest(prompt: String) async throws -> ZhipuAPIResponse {
        // 1. 构建请求体
        // 2. 设置 HTTP Header (Authorization: Bearer <apiKey>)
        // 3. 发送 POST 请求
        // 4. 解析 JSON 响应
        // 5. 超时 30s，失败重试最多 2 次
    }
}
```

**调用链路**：

```
ViewModel.submitThought()
    ↓
TaskManager.submitThought()          // actor 隔离
    ↓
AIServiceProtocol.parseThoughts()    // 协议调用，不依赖具体实现
    ↓
ZhipuAIService.sendRequest()         // 具体实现
    ↓ HTTPS POST
智谱 GLM-5.1 API
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
    var priority: String     // "high" / "medium" / "low"
    var aiRecommended: Bool
    var recommendationReason: String?
    var pool: String         // "idea_pool" / "must_do"
    var sortOrder: Int
    var status: String       // "pending" / "running" / "paused" / "done"
    var date: Date           // 任务所属日期
    var createdDate: Date    // 任务创建日期（跨天迁移后 date 变化但 createdDate 不变）
    var attempted: Bool      // 是否曾经尝试过（跨天迁移标记）
    
    @Relationship(deleteRule: .cascade)
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
    var date: Date           // 记录所属日期（同一任务可有多条记录，每天执行都会新增）
    
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
    var appealCount: Int     // 当日已使用驳斥次数（上限 3）
    var gradingBasis: String? // AI 评分依据（驳斥时展示给用户）
}
```

### 6.3 ModelContainer 配置

```swift
@main
struct NLPlanApp: App {
    
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
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .modelContainer(container)
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)  // 使用 .window 支持 Popover
    }
}
```

### 6.4 Repository 模式

每个实体对应一个 Repository，封装 SwiftData 操作：

```swift
protocol TaskRepositoryProtocol: Sendable {
    func create(_ task: TaskEntity) async throws
    func update(_ task: TaskEntity) async throws
    func delete(id: UUID) async throws
    func fetch(date: Date, pool: TaskPool) async throws -> [TaskEntity]
    func fetchById(_ id: UUID) async throws -> TaskEntity?
}
```

> **注意**：SwiftData 的 `ModelContext` 不是线程安全的，Repository 内部需通过 `@ModelActor` 或手动管理主线程调度。

---

## 7. 数据流设计

### 7.1 核心数据流 — 输入到执行

```
用户输入文本
     │
     ▼
InputViewModel.submit()
     │  1. 验证输入（非空、长度）
     │  2. 禁用提交按钮，显示加载状态
     │
     ▼
TaskManager.submitThought(rawText:)
     │  1. 保存 ThoughtEntity（processed=false）
     │  2. 调用 AIService.parseThoughts()
     │  3. 解析结果转为 TaskEntity，pool=ideaPool
     │  4. 批量保存到 SwiftData
     │  5. 标记 ThoughtEntity（processed=true）
     │
     ▼
返回 [Task] 给 ViewModel
     │
     ▼
IdeaPoolViewModel 刷新列表
     │  UI 自动更新（@Query 或手动刷新）
```

### 7.2 核心数据流 — 任务执行与切换

```
用户点击必做项
     │
     ▼
MustDoViewModel.startTask(id:)
     │
     ▼
TimerEngine.startTask(taskId)
     │  1. 如果 allowParallel == false
     │     → 遍历 activeTaskIds，逐个调用 stopTask()
     │     → 收集被停止任务的 SessionLog
     │  2. 记录 startTimes[taskId] = Date.now
     │  3. 将 taskId 加入 activeTaskIds
     │  4. 返回被停止任务的 SessionLog 列表
     │
     ▼
MustDoViewModel 收到返回的 SessionLog
     │  1. 持久化每条 SessionLog 到 SwiftData
     │  2. 更新 TaskEntity.status
     │  3. 刷新 UI
     │
     ▼
TimerViewModel 每秒刷新
     │  调用 TimerEngine.elapsedSeconds(for:)
     │  更新菜单栏显示文本
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
返回 DailySummary 给 ViewModel
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
    
    /// 当前是否有任务在计时（决定菜单栏显示）
    var isTimerRunning: Bool = false
    
    /// 当前计时显示文本（如 "00:32:15"）
    var timerDisplayText: String = ""
    
    /// 当前运行中的任务名称
    var currentTaskTitle: String = ""
    
    /// 当前日期
    var today: Date = .now
    
    /// 今日是否已评分
    var hasGradedToday: Bool = false
    
    /// AI 是否正在处理中
    var isAIProcessing: Bool = false
    
    /// 网络是否可用
    var isNetworkAvailable: Bool = true
}
```

### 8.2 ViewModel 层状态

每个 ViewModel 负责：
1. 持有 UI 需要的数据（从 Domain Layer 获取）
2. 处理用户交互（调用 Domain Layer）
3. 更新 UI 状态（loading / error / data）

```swift
/// 输入区 ViewModel 示例
@Observable
final class InputViewModel {
    
    var inputText: String = ""
    var isProcessing: Bool = false
    var errorMessage: String?
    
    private let taskManager: TaskManager
    
    func submit() async {
        // 1. 验证
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // 2. 状态更新
        isProcessing = true
        errorMessage = nil
        
        // 3. 调用 Domain
        do {
            _ = try await taskManager.submitThought(rawText: inputText)
            inputText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        
        // 4. 恢复状态
        isProcessing = false
    }
}
```

### 8.3 计时器刷新机制

```
┌──────────────┐     每秒 tick      ┌─────────────────┐
│  Timer       │ ──────────────────→ │  TimerViewModel │
│  (Timer.publish)                   │                 │
└──────────────┘                     │  调用 TimerEngine.elapsedSeconds()
                                     │  更新 timerDisplayText
                                     │  更新 currentTaskTitle
                                     │
                                     └──────┬──────────┘
                                            │ @Observable
                                            ▼
                                     ┌─────────────────┐
                                     │  MenuBarView    │
                                     │  显示 ⏱ 00:32:15 │
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
    private var cancellable: AnyCancellable?
    
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
                        // 从 TaskManager 获取任务标题
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
│  │ ZhipuAI      │                   │
│  │ Service      │  ← URLSession    │
│  │ (class)      │    异步网络请求    │
│  └──────────────┘                   │
│                                     │
│  ┌──────────────┐                   │
│  │ Repository   │  ← SwiftData     │
│  │ (Actor)      │    主线程写入     │
│  └──────────────┘                   │
└─────────────────────────────────────┘
```

**规则**：
1. UI 操作必须在 Main Thread
2. Actor 内部逻辑在 Cooperative Thread Pool 执行
3. SwiftData 写操作需要 dispatch 到 Main Thread（SwiftData 限制）
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
    
    // 网络错误
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入内容后再提交"
        case .aiServiceUnavailable:
            return "AI 服务暂时不可用，请稍后重试"
        case .aiRequestTimeout:
            return "AI 服务响应超时，请稍后重试"
        case .aiResponseParseError:
            return "AI 解析失败，请尝试重新描述"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接"
        // ...
        }
    }
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
| AI 服务不可用 | 提示用户，保留输入文本，允许重试 |
| 日终 AI 评分失败 | 使用基于规则的基础评分（仅按完成率计算等级） |
| 备忘录同步失败 | 提示用户重试，提供"复制到剪贴板"备选 |
| 网络断开 | 本地计时正常运行，暂存输入文本 |

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
| UI 流畅度 | AI 调用异步，不阻塞主线程 |
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
| ViewModel | 单元测试 | 状态变更、错误处理 | XCTest |
| UI | UI 测试 | 核心流程端到端 | XCUITest |

### 14.2 Mock 策略

```swift
/// AI 服务 Mock，用于 Domain/ViewModel 测试
final class MockAIService: AIServiceProtocol {
    var mockParsedTasks: [ParsedTask] = []
    var mockGrade: DailyGrade?
    var shouldThrow: Bool = false
    
    func parseThoughts(input: String, existingTasks: [Task]) async throws -> [ParsedTask] {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        return mockParsedTasks
    }
    
    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        return mockGrade!
    }
    
    func appealGrade(originalGrade: DailyGrade, originalInput: DailySummaryInput, userFeedback: String) async throws -> DailyGrade {
        if shouldThrow { throw NLPlanError.aiServiceUnavailable }
        // Mock: 返回提升一级的评分
        return mockGrade ?? DailyGrade(grade: .b, summary: "Mock appeal result", stats: GradeStats(totalTasks: 5, completedTasks: 4, totalPlannedMinutes: 240, totalActualMinutes: 265, deviationRate: 0.1, extraCompleted: 0), suggestion: "Keep going!")
    }
}
```

### 14.3 关键测试用例

| 用例 | 覆盖模块 | 描述 |
|------|----------|------|
| 输入空文本 → 不提交 | InputViewModel | 验证输入校验 |
| 输入有效文本 → AI 解析 → 进入想法池 | TaskManager | 验证完整解析流程 |
| AI 失败 → 保留输入 → 显示错误 | TaskManager + ViewModel | 验证降级策略 |
| 点击任务A → 点击任务B → A 停止，B 开始 | TimerEngine | 验证切换逻辑 |
| 点击任务A → A 开始 → 再点 A → 不变 | TimerEngine | 验证幂等性 |
| 结束今天 → 停止所有 → AI 评分 → 存储 | DayManager | 验证日终流程 |
| 并行关闭 → 同时只能一个任务 | TimerEngine | 验证串行模式 |

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
         └── 网络：HTTPS → 智谱 AI API
```

---

## 17. 后续演进预留

| 版本 | 架构调整 |
|------|----------|
| V1.1 | `AppleNotesService` 实现同步；Repository 增加导出方法 |
| V1.2 | `TimerEngine` 增加 `allowParallel` 配置项；ViewModel 增加并行 UI |
| V2.0 | 新增 `AIServiceFactory`，支持运行时切换 AI 服务；新增配置 UI |
| V2.0 | 新增 `ReportService`，周报/月报聚合；新增 `ReportView` |
