# NL Plan for Mac

一款基于 AI 的 macOS 菜单栏计划管理工具。用自然语言描述你的计划，AI 自动拆解为结构化任务，配合计时执行、项目管理和日终评分，形成完整的规划→执行→复盘闭环。

## 功能

### 核心流程

- **自然语言输入** — 一句话描述计划，AI 拆解为带分类和预估时长的任务
- **解析队列** — 非阻塞处理，提交后可继续输入，逐个解析展示实时状态
- **确认编辑** — 解析结果可逐条编辑，支持追加指令让 AI 重新调整
- **想法池** — 所有任务先进想法池，用户挑选后加入今日必做项
- **必做项计时** — 启动计时执行任务，菜单栏实时显示进度
- **日终评分** — AI 根据 A-F 评分、总结和改进建议，支持驳斥（最多 3 次）

### 项目管理

- **项目标记** — 想法可标记为项目，通过绑定必做项切片推进
- **项目详情** — 项目说明、规划背景、备注、活跃/归档推进记录
- **项目进度** — AI 分析绑定任务的完成情况，生成进度百分比和摘要
- **来源绑定** — 必做项可绑定到项目，实现长期任务追踪

### AI 推荐

- **快速模式** — 优先推荐普通想法，快速清理想法池
- **综合模式** — 平衡普通想法和项目，项目自动刷新状态摘要后参与推荐
- **项目切片** — 项目推荐时生成具体可执行的切片任务
- **容错机制** — 项目摘要生成失败不阻塞整轮推荐，所有 AI 调用支持自动重试

### 其他

- **AI 清理** — 分析想法池，推荐删除不合适的条目
- **历史记录** — 按月历查看每日评分，颜色标识等级
- **跨天处理** — 昨日未完成自动移回想法池，支持补结算

## 系统要求

- macOS 14.0 (Sonoma) 及以上
- Xcode 15.0 及以上

## 构建与运行

```bash
git clone https://github.com/Allertant/nl-plan-for-mac.git
cd nl-plan-for-mac

# 运行 package 单元测试
cd Packages/NLPlanKit
swift test

# 回到仓库根目录构建 macOS App
cd ../..
xcodebuild \
  -project NLPlan.xcodeproj \
  -scheme NLPlan \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .DerivedData/NLPlan \
  -clonedSourcePackagesDirPath .DerivedData/NLPlan/SourcePackages \
  build
```

构建完成后的应用产物位置：

- `.app` 包：
  - `.DerivedData/NLPlan/Build/Products/Debug/NLPlan.app`
- 可执行文件：
  - `.DerivedData/NLPlan/Build/Products/Debug/NLPlan.app/Contents/MacOS/NLPlan`

如果使用 Xcode，也可以直接打开 `NLPlan.xcodeproj`，选择 `NLPlan` scheme 运行。

## 配置

1. 点击菜单栏图标打开面板
2. 点击底部「设置」按钮
3. 输入你的 [DeepSeek API Key](https://platform.deepseek.com/) 并保存
4. 可选择 AI 模型、设置工作结束时间等

## 技术架构

| 领域 | 选型 |
|------|------|
| UI | SwiftUI + MenuBarExtra |
| 数据持久化 | SwiftData（自动轻量迁移） |
| AI 服务 | DeepSeek API（通过 AIServiceProtocol 抽象，可扩展） |
| 并发模型 | Swift Concurrency（async/await + actor） |
| 安全存储 | Keychain |

## 数据模型

| 实体 | 用途 |
|------|------|
| IdeaEntity | 想法池条目（普通想法 + 项目，共用一张表） |
| DailyTaskEntity | 今日必做项（活跃 + 已归档，共用一张表） |
| DailySummaryEntity | 日终评分记录 |
| SessionLogEntity | 计时记录 |
| ThoughtEntity | 用户原始输入文本 |
| ProjectNoteEntity | 项目备注 |

## 文档

| 文档 | 说明 |
|------|------|
| [docs/README.md](docs/README.md) | 文档目录索引 |
| [docs/spec/PRD.md](docs/spec/PRD.md) | 产品需求文档 |
| [docs/spec/SAD.md](docs/spec/SAD.md) | 软件架构文档 |
| [docs/spec/SRS.md](docs/spec/SRS.md) | 软件需求规格说明 |
| [docs/design/ai-recommendation-upgrade.md](docs/design/ai-recommendation-upgrade.md) | AI 推荐必做项流程升级设计 |
| [docs/design/settlement-scoring-upgrade.md](docs/design/settlement-scoring-upgrade.md) | 结算评分机制升级设计 |
| [docs/design/project-and-progress.md](docs/design/project-and-progress.md) | 想法池项目与 AI 进度设计 |
| [docs/guides/macos-app-local-package-migration-guide.md](docs/guides/macos-app-local-package-migration-guide.md) | macOS App + local package 通用改造指南 |

## License

MIT
