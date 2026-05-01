# 想法与项目分表重构方案

## 目标

将当前 `IdeaEntity + isProject` 的混合建模，重构为：

- 普通想法独立表
- 项目独立表
- 必做项来源关联显式区分“来自想法”还是“来自项目”
- 项目专属字段、项目专属流程、项目专属状态从普通想法语义中完全剥离

同时配套收紧产品规则：

- “是项目还是普通想法”必须在审核/确认阶段严格确定
- 入库后不再允许“普通想法 <-> 项目”互转
- 项目不再复用普通想法的 `attempted / completed` 状态语义

---

## 当前问题

当前实现以 `IdeaEntity` 为统一长期对象，通过 `isProject` 区分：

- 普通想法
- 项目

这导致了以下结构性问题：

1. 同一张表同时承载两种不同语义
   - 普通想法是“单体长期事项”
   - 项目是“可拆分、可推进、可挂安排/备注/规划背景的复杂对象”

2. 状态机语义冲突
   - 普通想法使用 `pending / in_progress / attempted / completed / archived`
   - 项目实际上并不适合 `attempted / completed`
   - 现在只能通过大量 `if idea.isProject` 做业务绕开

3. 项目字段污染普通想法模型
   - `projectDescription`
   - `planningBackground`
   - `projectProgress`
   - `projectRecommendationSummary`
   - 等等

4. 项目相关表的归属不清晰
   - `ProjectArrangementEntity.projectId`
   - `ProjectNoteEntity.ideaId`
   - 命名已经出现“项目”与“想法”混搭

5. 必做项来源关联不够强类型
   - `DailyTaskEntity.sourceIdeaId`
   - `DailyTaskEntity.sourceType`
   - 当前靠运行时判断来源类型，后续继续扩展会越来越脆

6. UI 和业务层长期被 `isProject` 条件分支污染
   - 想法池
   - 项目详情
   - 推荐链路
   - 日结
   - 历史详情

---

## 重构后的目标模型

### 1. 普通想法表：`IdeaEntity`

只保留普通想法需要的字段：

- `id`
- `title`
- `category`
- `estimatedMinutes`
- `priority`
- `aiRecommended`
- `recommendationReason`
- `sortOrder`
- `status`
- `createdDate`
- `updatedAt`
- `attempted`
- `note`
- `deadline`

普通想法状态机继续保留：

- `pending`
- `in_progress`
- `attempted`
- `completed`
- `archived`

### 2. 项目表：`ProjectEntity`

新增独立项目实体，承载全部项目专属字段：

- `id`
- `title`
- `category`
- `priority`
- `sortOrder`
- `status`
- `createdDate`
- `updatedAt`
- `projectDecisionSource`
- `projectProgress`
- `projectProgressSummary`
- `projectProgressUpdatedAt`
- `projectDescription`
- `planningBackground`
- `planningResearchPrompt`
- `planningResearchPromptReason`
- `projectRecommendationContextUpdatedAt`
- `projectRecommendationSummary`
- `projectRecommendationSummaryGeneratedAt`
- `projectRecommendationSummarySourceUpdatedAt`
- `deadline`

项目状态机建议单独定义：

- `pending`
- `active`
- `archived`

说明：

- 不再使用 `attempted`
- 不再使用 `completed`
- “项目完成”如果未来真要支持，应单独定义为项目域语义，而不是复用普通想法

### 3. 项目备注表：`ProjectNoteEntity`

将：

- `ideaId`

改为：

- `projectId`

### 4. 项目安排表：`ProjectArrangementEntity`

保留现有方向，但确保它明确依赖项目：

- `projectId`
- `content`
- `estimatedMinutes`
- `deadline`
- `status`
- `sortOrder`
- `createdAt`
- `updatedAt`

### 5. 必做项来源字段：`DailyTaskEntity`

当前：

- `sourceIdeaId`
- `sourceType`

重构后建议改成：

- `sourceIdeaId: UUID?`
- `sourceProjectId: UUID?`
- `arrangementId: UUID?`
- `sourceType`

约束：

- 普通想法来源：只写 `sourceIdeaId`
- 项目切片来源：只写 `sourceProjectId`
- 项目安排来源：写 `sourceProjectId + arrangementId`

这样可以避免“项目来源却塞进 sourceIdeaId”这类语义不清的问题。

---

## 产品规则调整

### 1. 审核阶段必须确定类型

在解析确认队列里：

- 用户或 AI 必须明确决定当前条目是“普通想法”还是“项目”
- 保存时直接进入对应实体

不再允许：

- 先落成普通想法，后面再切项目
- 先落成项目，后面再切普通想法

### 2. 移除想法池内“设为项目/设为普通想法”

当前入口：

- `IdeaPoolTaskRow`
- `IdeaPoolViewModel.updateProjectState(...)`

这套互转逻辑将被删除。

### 3. 项目不再显示普通想法状态文案

例如：

- 已尝试
- 完成

这些只属于普通想法。

项目使用：

- 进度
- 安排
- 备注
- 规划背景
- 项目推荐摘要

来表达推进状态。

---

## 总体迁移策略

本次重构采用“兼容式渐进迁移”，避免一次性切断所有链路。

### 原则

1. 先引入新实体和兼容层
2. 再逐步切读路径
3. 再逐步切写路径
4. 最后删除旧分支和旧字段

### 为什么不直接原地硬改

因为当前这些模块都依赖 `IdeaEntity`：

- 输入确认
- 想法池
- 项目详情
- 推荐
- 日结
- 历史详情
- 必做项来源弹层
- 项目进度分析
- 项目安排
- 项目备注

如果一次性硬切，风险太高，很容易出现：

- 页面全挂
- 旧数据读不出来
- 必做项来源丢失
- AI 推荐上下文损坏

---

## 分阶段方案

## 阶段 0：方案落地与约束冻结

### 目标

- 固化本方案
- 冻结“项目/想法互转将被删除”的方向
- 后续所有改动按阶段推进

### 产出

- 本文档

### 完成标记

- [x] 已完成

---

## 阶段 1：新增 `ProjectEntity` 与数据层兼容骨架

### 目标

新增项目独立实体，但暂时不切 UI，不切主流程。

### 工作项

1. 新增 `ProjectEntity`
2. 新增 `ProjectStatus`
3. 新增 `ProjectRepository`
4. 为 `NLPlanMenuBarScene` 的 SwiftData schema 注册 `ProjectEntity`
5. 保持现有 `IdeaEntity` 继续可用
6. 新增最小兼容查询接口：
   - `fetchVisibleIdeas()`
   - `fetchVisibleProjects()`
   - `fetchAllLongLivedItems()`（聚合层用）

### 要点

- 这一步不迁 UI
- 这一步不迁推荐
- 这一步不删 `isProject`

### 风险

- schema 增量引入后，必须确认现有数据库可正常启动

### 完成标记

- [x] 已完成
- 新增 `ProjectEntity`，包含全部项目专属字段（进度、描述、规划背景、推荐摘要等）
- 新增 `ProjectStatus` 枚举（pending / active / archived）
- 新增 `ProjectRepository`，提供 create、fetchById、fetchVisibleProjects、fetchRecommendationCandidates、update、touchRecommendationContext、delete
- `NLPlanMenuBarScene` 的 SwiftData schema 已注册 `ProjectEntity`
- 现有 `IdeaEntity` 继续可用，未做任何改动

---

## 阶段 2：审核/入库流程分流，禁止后续互转

### 目标

创建时就决定实体类型，入库后不再允许互转。

### 工作项

1. 修改解析确认流程
   - `ParsedTask`
   - `InputViewModel`
   - `TaskManager.saveParsedTasks`
   - `TaskManager.saveSingleParsedTask`

2. 保存逻辑分流：
   - 普通想法 -> `IdeaRepository.create(...)`
   - 项目 -> `ProjectRepository.create(...)`

3. 删除/下线：
   - `IdeaPoolViewModel.updateProjectState(...)`
   - `IdeaPoolTaskRow` 的“设为项目/设为普通想法”入口

### 风险

- 当前已有旧项目数据仍在 `IdeaEntity`
- 所以这一步只是”新数据入新表，旧数据继续兼容”

### 完成标记

- [x] 已完成
- `TaskManager` 新增 `projectRepo: ProjectRepository`，构造函数已更新
- `saveParsedTasks` 返回类型改为 `[UUID]`，内部按 `isProject` 分流：项目 → `ProjectRepository.create`，普通想法 → `IdeaRepository.create`
- `saveSingleParsedTask` 返回类型改为 `UUID`，同样分流
- `InputViewModel.confirmQueueItem` / `approveSingleTask` 适配新返回类型
- `AppState` / `SummaryContainerView` 的 TaskManager 实例化已补充 `projectRepo` 参数
- 删除 `IdeaPoolViewModel.updateProjectState` 方法
- 删除 `IdeaPoolTaskRow` 的互转菜单按钮（`onUpdateProjectState` 回调），保留项目标签静态展示
- 删除 `IdeaPoolSection` 中对应的回调接线

---

## 阶段 3：迁项目专属详情页与项目附属数据

### 目标

把项目详情页完全切到 `ProjectEntity`。

### 工作项

1. `ProjectDetailContainerView`
   - 输入改为 `ProjectEntity` 或 `ProjectDetailSnapshot(project:)`

2. 项目备注
   - `ProjectNoteEntity.ideaId -> projectId`
   - 相关仓库、ViewModel、TaskManager 接口统一改名

3. 项目安排
   - 保持 `projectId` 语义不变
   - 所有读取接口改为基于 `ProjectEntity`

4. 项目规划背景
   - `projectDescription`
   - `planningBackground`
   - `planningResearchPrompt`
   - `projectRecommendationSummary`

### 风险

- 这是第一次真正大规模切 UI
- 必须保证旧项目详情不会挂

### 完成标记

- [x] 已完成
- `ProjectNoteEntity` 新增 `projectId` 字段（保留 `ideaId` 兼容旧数据）
- `ProjectRepository` 新增备注 CRUD、项目字段更新方法
- `TaskManager` 新增项目查询/更新方法（`fetchProject`、`updateProjectTitle`、`updateProjectDescription`、`updatePlanningBackground`、`addProjectNote(projectId:)`、`fetchProjectNotesByProjectId`、`generatePlanningBackgroundPrompt(projectId:)`）
- `IdeaPoolViewModel` 新增 ProjectEntity 路径方法
- `ProjectDetailSnapshot` 新增 `init(project:)`，标记 `Source` 枚举区分来源
- `ProjectDetailContainerView` 改为接收 `projectId`，先查 `ProjectEntity` 再回退 `IdeaEntity`
- 所有编辑操作（标题、描述、规划背景、备注、安排、研究提示词）按来源分发到对应路径

---

## 阶段 4：必做项来源关联改造

### 目标

把必做项对长期对象的来源关联从“统一 sourceIdeaId”改为“想法/项目分离”。

### 工作项

1. `DailyTaskEntity`
   - 新增 `sourceProjectId`
   - 保留 `sourceIdeaId` 兼容旧数据

2. 所有来源判定逻辑重构
   - `DailyTaskSourceType`
   - `summarySourceType`
   - `rebindTaskSource`
   - 历史详情弹层
   - 今日必做项来源展示

3. 项目安排加入必做项时
   - 改写 `sourceProjectId`
   - 不再借道 `sourceIdeaId`

4. 项目切片必做项时
   - 使用 `sourceProjectId`

### 风险

- 这是关系层重构，必须小心回归
- 历史数据读取需要兼容老字段

### 完成标记

- [x] 已完成
- `DailyTaskEntity` 新增 `sourceProjectId: UUID?` 字段（保留 `sourceIdeaId` 兼容旧数据）
- `DailyTaskRepository.create` 新增 `sourceProjectId` 参数
- `TaskManager.promoteArrangementToMustDo` 改为先查 `ProjectEntity` 再回退 `IdeaEntity`，新项目写 `sourceProjectId`
- `TaskManager.dailyTaskSourceType` 增加对 `ProjectEntity` 的检查
- `DayManager.summarySourceType` 优先判断 `sourceProjectId`
- `HistoryDetailContainerView` 加载 `sourceProjects` 字典，展示 `sourceProjectId` 对应的项目链接

---

## 阶段 5：AI 推荐链路迁移

### 目标

将推荐链路中的项目输入全面改为 `ProjectEntity`。

### 工作项

1. 快速模式
   - 普通想法来自 `IdeaEntity`
   - 项目安排来自 `ProjectEntity + Arrangement`

2. 综合模式
   - 项目摘要生成输入改为 `ProjectEntity`
   - 项目选择
   - 项目切片生成

3. `TaskRecommendationInput` 的项目来源语义梳理

4. 项目摘要缓存与失效判断继续沿用，但以 `ProjectEntity` 为主

### 风险

- 推荐输入模型是多个阶段拼装的
- 一旦混着读旧 `IdeaEntity.isProject` 和新 `ProjectEntity`，很容易出重复候选

### 完成标记

- [ ] 已完成

---

## 阶段 6：想法池聚合视图重构

### 目标

让 UI 不再依赖“项目也是一种 IdeaEntity”。

### 工作项

1. 引入聚合展示模型，例如：
   - `IdeaPoolListItem`
   - `.idea(IdeaEntity)`
   - `.project(ProjectEntity)`

2. 想法池列表改为聚合渲染

3. 不同卡片类型拆分：
   - 普通想法行
   - 项目行

4. 删除 `isProject` 驱动的大量 UI 分支

### 风险

- 这是 UI 层清债阶段
- 要保证现有交互不倒退

### 完成标记

- [ ] 已完成

---

## 阶段 7：清理旧项目数据路径与迁移历史数据

### 目标

移除旧的“项目仍存在于 IdeaEntity”的路径。

### 工作项

1. 提供迁移脚本/迁移逻辑
   - 将 `IdeaEntity(isProject == true)` 转成 `ProjectEntity`
   - 将项目备注 `ideaId` 转成 `projectId`
   - 将必做项来源从 `sourceIdeaId` 迁到 `sourceProjectId`

2. 清理旧分支
   - `IdeaEntity.isProject`
   - 项目字段残留
   - `updateProjectState`
   - 相关 prompt / UI 分支

3. 只保留：
   - 普通想法表
   - 项目表

### 风险

- 这是最终清理阶段
- 必须在前面各阶段稳定后再做

### 完成标记

- [ ] 已完成

---

## 关键接口改造清单

### 数据层

- `IdeaEntity`
- `ProjectEntity`（新增）
- `ProjectNoteEntity`
- `ProjectArrangementEntity`
- `DailyTaskEntity`
- `IdeaRepository`
- `ProjectRepository`（新增）
- `DailyTaskRepository`

### 业务层

- `TaskManager`
- `DayManager`

### ViewModel

- `InputViewModel`
- `IdeaPoolViewModel`
- `MustDoViewModel`

### 页面

- `IdeaPoolTaskRow`
- `IdeaPoolSection`
- `MustDoSection`
- `ProjectDetailContainerView`
- `HistoryDetailContainerView`

### AI 输入输出模型

- `ParsedTask`
- `ProjectClassificationInput`
- `TaskRecommendationInput`
- `ProjectProgressInput`
- `ProjectRecommendationSummaryInput`

---

## 迁移期间的兼容原则

为了避免大迁移过程中出现“半新半旧读不出来”，迁移期间遵守以下规则：

1. 老数据继续可读
2. 新数据优先写入新模型
3. 聚合层允许同时读取：
   - `IdeaEntity` 中的普通想法
   - `ProjectEntity` 中的项目
4. 旧 `IdeaEntity.isProject == true` 在最终迁移前仍可兼容读取，但不再作为未来主路径

---

## 测试与验证重点

每阶段都至少验证：

1. 新建普通想法
2. 新建项目
3. 想法池展示
4. 项目详情页
5. 项目安排 -> 必做项
6. AI 快速推荐
7. AI 综合推荐
8. 日终结算
9. 历史详情页来源展示

---

## 提交策略

本次重构按关键点逐次提交，每次提交都必须：

1. 范围足够单一
2. 能独立构建
3. 不留下明显半残入口

建议提交粒度：

1. 设计文档
2. 新项目实体与仓库骨架
3. 审核入库分流 + 去掉互转入口
4. 项目详情与附属表迁移
5. 必做项来源改造
6. AI 推荐链路迁移
7. 想法池聚合重构
8. 历史数据迁移与旧分支清理

---

## 当前执行决定

### 当前建议立即开始的阶段

先执行：

- 阶段 1：新增 `ProjectEntity` 与数据层兼容骨架

原因：

- 风险最低
- 不会立刻打断现有 UI
- 可以为后面所有阶段提供稳定落点

---

## 执行记录

- [x] 阶段 0 已完成
- [x] 阶段 1 已完成
- [x] 阶段 2 已完成
- [x] 阶段 3 已完成
- [x] 阶段 4 已完成
- [ ] 阶段 5 已完成
- [ ] 阶段 6 已完成
- [ ] 阶段 7 已完成
