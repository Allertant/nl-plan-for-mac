# NL Plan for Mac — 软件需求说明书（SRS）

> **文档编号**：NLPLAN-SRS-001  
> **产品名称**：NL Plan（暂定）  
> **文档版本**：v0.1  
> **日期**：2026-04-14  
> **作者**：产品团队  
> **状态**：草案

---

## 修订历史

| 版本 | 日期 | 修改人 | 修改内容 |
|------|------|--------|----------|
| v0.1 | 2026-04-14 | — | 初稿 |

---

## 1. 引言

### 1.1 编写目的

本需求说明书面向开发团队，详细定义 NL Plan for Mac 的功能需求、非功能需求、接口规范和约束条件，作为系统设计、开发、测试的基准文件。

### 1.2 项目背景

用户在日常工作和生活中会产生大量零散的想法和待办事项，传统的任务管理工具需要用户手动拆分、分类、排序，操作摩擦大，导致"想法很多但执行很少"的问题。NL Plan 通过 AI 将自然语言自动转化为结构化任务流，配合被动计时和游戏化评分，降低"从想法到行动"的门槛。

### 1.3 术语定义

| 术语 | 定义 |
|------|------|
| 想法池 | Idea Pool，所有经 AI 解析后的任务暂存区，任务的唯一入口 |
| 必做项 | Must-Do，用户确定今日要完成的任务，来源于 AI 推荐和用户从想法池手动挑选 |
| 正计时 | Count-up Timer，从 00:00:00 开始累计的计时方式 |
| 日终评分 | Daily Grade，AI 根据当日任务完成情况给出的 S/A/B/C/D 等级评价 |
| Session | 一次任务计时的起止记录 |
| Popover | macOS 菜单栏应用的弹出面板 |

### 1.4 参考资料

- [NL Plan PRD v0.1](./PRD.md)
- Apple Human Interface Guidelines — Menu Bar Extras
- Apple SwiftUI Documentation
- 智谱 AI GLM API Documentation

---

## 2. 总体描述

### 2.1 产品视角

NL Plan 是一款独立的 macOS 桌面应用，以菜单栏工具（Menu Bar Extra）形态运行，不依赖其他软件。通过互联网调用 AI 服务（智谱 GLM-5.1）进行自然语言处理。

**系统边界图**：

```
┌─────────────────────────────────────────────────────┐
│                    macOS 系统                        │
│                                                     │
│  ┌───────────┐    ┌──────────────┐                  │
│  │  NL Plan   │───→│  备忘录 App   │                  │
│  │  (菜单栏)  │    │  Apple Notes │                  │
│  └─────┬─────┘    └──────────────┘                  │
│        │                                             │
│        │ 本地存储（SwiftData）                          │
│        ▼                                             │
│  ┌───────────┐                                      │
│  │ SwiftData │                                      │
│  └───────────┘                                      │
│                                                     │
└─────────────────────┬───────────────────────────────┘
                      │ HTTPS
                      ▼
              ┌──────────────┐
              │  智谱 AI API  │
              │  GLM-5.1     │
              └──────────────┘
```

### 2.2 用户特征

| 特征 | 描述 |
|------|------|
| 用户类型 | 个人用户（产品作者本人） |
| 技术水平 | 具备基本软件使用能力 |
| 使用频率 | 每日多次，贯穿全天 |
| 使用场景 | 办公、居家、随时记录 |

### 2.3 运行环境

| 项目 | 要求 |
|------|------|
| 操作系统 | macOS 14.0 (Sonoma) 及以上 |
| 硬件 | Apple Silicon (M1+) 或 Intel Mac |
| 网络 | AI 功能需联网，本地计时功能离线可用 |
| 磁盘空间 | ≤ 50MB |

### 2.4 设计与实现约束

| 约束 | 说明 |
|------|------|
| 开发语言 | Swift |
| UI 框架 | SwiftUI |
| 数据存储 | SwiftData（macOS 14+ 原生方案） |
| AI 服务 | 智谱 GLM-5.1，通过 HTTPS API 调用 |
| 架构要求 | AI 服务层必须抽象为接口，预留扩展其他模型的可能性（但 V1 不实现具体扩展代码和配置界面） |
| 分发方式 | Xcode 直接构建安装，不上架 App Store |

---

## 3. 功能需求

### 3.1 自然语言输入（FR-INPUT）

#### 3.1.1 文本输入框

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-INPUT-001 | 提供文本输入框，支持多行输入 | P0 |
| FR-INPUT-002 | 按回车键（或点击提交按钮）提交文本 | P0 |
| FR-INPUT-003 | 提交后清空输入框 | P0 |
| FR-INPUT-004 | 提交后显示 AI 正在解析的加载状态 | P0 |
| FR-INPUT-005 | 支持随时多次追加输入 | P0 |
| FR-INPUT-006 | 输入框应支持中文和英文 | P0 |

#### 3.1.2 输入验证

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-INPUT-010 | 空文本不可提交 | P0 |
| FR-INPUT-011 | 纯空格/换行不可提交 | P0 |
| FR-INPUT-012 | 单次输入长度上限 2000 字符 | P1 |

---

### 3.2 AI 解析服务（FR-AI）

#### 3.2.1 想法解析

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-AI-001 | 接收用户自然语言文本，调用 AI 服务解析为结构化任务列表 | P0 |
| FR-AI-002 | 每个解析结果包含：任务标题、分类、预估时长、优先级、是否推荐为必做、推荐理由 | P0 |
| FR-AI-003 | 解析结果自动进入想法池 | P0 |
| FR-AI-004 | 解析时应考虑想法池中已有任务，避免生成重复任务 | P1 |
| FR-AI-005 | AI 调用失败时，向用户显示错误提示，不丢失原始输入文本 | P0 |
| FR-AI-006 | AI 调用超时阈值为 30 秒 | P1 |

#### 3.2.2 必做项推荐

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-AI-010 | AI 在解析时同时判断哪些任务应推荐为今日必做 | P0 |
| FR-AI-011 | 被推荐的任务在想法池中标记为"AI 推荐"并附推荐理由 | P0 |
| FR-AI-012 | AI 推荐仅作为建议，不影响用户手动选择权 | P0 |

#### 3.2.3 日终评分

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-AI-020 | 日终评分时调用 AI 服务，输入当日任务完成数据，输出 S/A/B/C/D 等级 | P0 |
| FR-AI-021 | 评分输出包含：等级、评价文本、统计数据、明日建议 | P0 |
| FR-AI-022 | 评分维度至少包括：必做项完成率、时间偏差率、额外完成项 | P0 |

#### 3.2.4 AI 服务接口（扩展性预留）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-AI-030 | AI 服务层抽象为 Protocol/Interface | P0 |
| FR-AI-031 | 默认实现为智谱 GLM-5.1 | P0 |
| FR-AI-032 | 预留扩展其他 AI 服务的可能性（V1 不实现具体扩展和配置） | P1 |

---

### 3.3 想法池（FR-POOL）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-POOL-001 | 想法池展示所有经 AI 解析的任务 | P0 |
| FR-POOL-002 | 每个任务显示：标题、分类、预估时长、优先级标签 | P0 |
| FR-POOL-003 | AI 推荐的任务显示推荐标记和理由 | P0 |
| FR-POOL-004 | 用户可从想法池手动将任务加入必做项（加入后从想法池消失） | P0 |
| FR-POOL-005 | 任务加入必做项后从想法池中移除，两个池互不重叠 | P0 |
| FR-POOL-006 | 用户可删除想法池中的任务 | P1 |
| FR-POOL-007 | 想法池在主面板中默认折叠，点击可展开 | P0 |
| FR-POOL-008 | 所有任务必须先进入想法池，不存在直接创建必做项的路径 | P0 |
| FR-POOL-009 | 想法池跨天保留，不自动清空 | P0 |
| FR-POOL-010 | 每个任务卡片显示创建日期，用于区分不同天的想法 | P1 |
| FR-POOL-011 | 次日启动时，未完成的必做项自动移回想法池 | P0 |
| FR-POOL-012 | 被移回想法池的任务，若之前已开始执行过，标记"已尝试" | P0 |

---

### 3.4 必做项（FR-MUSTDO）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-MUSTDO-001 | 必做项列表展示用户确定今日要完成的任务 | P0 |
| FR-MUSTDO-002 | 来源：AI 推荐自动加入 + 用户从想法池手动挑选加入 | P0 |
| FR-MUSTDO-003 | 用户可调整必做项的顺序（拖拽或上下移动） | P1 |
| FR-MUSTDO-004 | 用户可将必做项移回想法池（重新出现在想法池中） | P1 |
| FR-MUSTDO-005 | 用户可标记必做项为"已完成" | P0 |
| FR-MUSTDO-006 | 每个必做项显示：标题、预估时长、当前状态、已用时长 | P0 |
| FR-MUSTDO-007 | 已完成的必做项显示为灰色划线，自动移到列表底部 | P1 |

---

### 3.5 任务执行与计时（FR-TIMER）

#### 3.5.1 正计时

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-TIMER-001 | 点击必做项开始执行，启动正计时（从 00:00:00 累计） | P0 |
| FR-TIMER-002 | 计时精确到秒 | P0 |
| FR-TIMER-003 | 计时在应用被隐藏/最小化后仍持续运行 | P0 |
| FR-TIMER-004 | 应用重启后，未结束的计时任务自动恢复（基于持久化的开始时间） | P1 |

#### 3.5.2 任务切换

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-TIMER-010 | 点击另一个必做项时，自动停止当前任务的计时，启动新任务的计时 | P0 |
| FR-TIMER-011 | 停止当前任务时，自动记录一条 SessionLog（包含起止时间和时长） | P0 |
| FR-TIMER-011a | 一个任务可对应多条 SessionLog，每次执行新增一条记录 | P0 |
| FR-TIMER-012 | 支持按顺序执行，也支持跳着执行（用户点击任意必做项即可切换） | P0 |

#### 3.5.3 并行任务

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-TIMER-020 | 默认模式：同一时间只有一个任务在计时 | P0 |
| FR-TIMER-021 | 提供设置项：允许同时运行多个任务计时 | P2 |
| FR-TIMER-022 | 多任务模式下，切换不自动停止其他任务 | P2 |

#### 3.5.4 菜单栏显示

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-TIMER-030 | 菜单栏常驻显示：正计时时间 + 当前任务名（例如 "⏱ 00:32:15 写需求文档"） | P0 |
| FR-TIMER-031 | 无任务运行时，菜单栏显示应用图标（无计时信息） | P0 |
| FR-TIMER-033 | 未配置 API Key 时，菜单栏显示"请配置 API"（替代图标） | P0 |
| FR-TIMER-032 | 菜单栏文字过长时截断并显示省略号 | P1 |

---

### 3.6 日终评分（FR-GRADING）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-GRADING-001 | 用户点击"结束今天"按钮触发日终评分 | P0 |
| FR-GRADING-002 | 评分页面展示：等级（大字）、评价文本、统计数据、明日建议 | P0 |
| FR-GRADING-003 | 统计数据包括：必做项完成数/总数、计划总时长、实际总时长、偏差率 | P0 |
| FR-GRADING-004 | 评分结果持久化存储 | P0 |
| FR-GRADING-005 | 评分页面提供"同步到备忘录"按钮 | P1 |
| FR-GRADING-006 | 评分调用 AI 失败时，展示基于规则的基础统计（降级方案） | P1 |
| FR-GRADING-007 | 次日启动时自动检查昨日是否有评分，若无则自动触发补评 | P0 |
| FR-GRADING-008 | 评分页面提供"驳斥"按钮，用户可对评分提出异议 | P0 |
| FR-GRADING-009 | 点击驳斥后，AI 展示本次评分的理由和依据 | P0 |
| FR-GRADING-010 | 用户可在驳斥框内输入自己的想法，AI 根据反馈重新评分 | P0 |
| FR-GRADING-011 | 每日申诉次数限制为 3 次，用完后驳斥按钮变灰不可点 | P0 |

**评分等级标准**：

| 等级 | 必做项完成率 | 时间偏差率 | 额外加分 |
|------|-------------|-----------|---------|
| S | 100% | ≤ 10% | 完成想法池额外任务 |
| A | 100% | ≤ 20% | — |
| B | ≥ 80% | — | — |
| C | ≥ 50% | — | — |
| D | < 50% | — | — |

> 注：最终评分由 AI 综合判断，上表为参考基准。AI 可根据具体情况调整等级。

---

### 3.7 同步到备忘录（FR-SYNC）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-SYNC-001 | 支持将日终评分结果同步到 macOS 备忘录（Apple Notes） | P1 |
| FR-SYNC-002 | 同步内容包含：日期、等级、统计数据、AI 评价、任务明细 | P1 |
| FR-SYNC-003 | 同步成功后标记为"已同步" | P1 |
| FR-SYNC-004 | 同步失败时提示用户，允许重试 | P1 |
| FR-SYNC-005 | 同步方式：V1 通过 AppleScript 实现 | P1 |

---

### 3.8 应用生命周期（FR-APP）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-APP-001 | 应用启动后自动在菜单栏常驻，不显示 Dock 图标 | P0 |
| FR-APP-002 | 应用随系统登录自动启动（可配置） | P2 |
| FR-APP-003 | 冷启动时间 < 2 秒 | P1 |
| FR-APP-004 | 应用关闭时（Cmd+Q）若有正在计时的任务，提示用户确认 | P2 |
| FR-APP-005 | 次日启动时，自动将昨日未完成的必做项移回想法池 | P0 |
| FR-APP-006 | 移回想法池的任务若之前已开始执行过，标记"已尝试" | P0 |

### 3.9 历史记录（FR-HISTORY）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-HISTORY-001 | 提供日历视图展示历史评分记录 | P1 |
| FR-HISTORY-002 | 日历每格显示日期 + 当天评分等级（S/A/B/C/D） | P1 |
| FR-HISTORY-003 | 未评分的天显示"—" | P1 |
| FR-HISTORY-004 | 点击某天可查看该天的详细日终总结 | P1 |

### 3.10 API Key 配置（FR-CONFIG）

| 编号 | 需求 | 优先级 |
|------|------|--------|
| FR-CONFIG-001 | 设置页提供 API Key 输入框，用于配置智谱 AI 认证信息 | P0 |
| FR-CONFIG-002 | API Key 存储于 macOS Keychain | P0 |
| FR-CONFIG-003 | 未配置 API Key 时，菜单栏显示"请配置 API" | P0 |

---

### 4.1 界面结构

#### 4.1.1 菜单栏常驻区

- **位置**：macOS 菜单栏右侧
- **内容**：
  - 无任务运行时：应用图标
  - 有任务运行时：`⏱ HH:MM:SS 任务名`

#### 4.1.2 主面板（Popover）

点击菜单栏图标后弹出，包含以下区域（从上到下）：

| 区域 | 说明 |
|------|------|
| 输入区 | 多行文本输入框 + 提交按钮 |
| 想法池 | 折叠区域，点击展开，显示所有想法池任务（含创建日期） |
| 必做项列表 | 展开区域，显示所有必做项及其状态（已完成项灰色划线在底部） |
| 操作栏 | "+ 添加想法"、"📊 今日总结"、"📅 历史记录"、"⚙️ 设置" |

#### 4.1.3 想法池展开

每个任务卡片包含：
- 任务标题
- 分类标签（工作/生活/学习...）
- 预估时长
- 优先级标签（高/中/低）
- AI 推荐标记（如推荐，显示理由）
- 创建日期（用于区分不同天的想法）
- "已尝试"标记（若之前执行过但未完成）
- 操作按钮：[加入必做] [删除]

#### 4.1.4 必做项列表

每个任务卡片包含：
- 状态图标（待执行 / 执行中 / 已完成）
- 任务标题
- 预估时长 / 已用时长
- 操作：点击开始/切换执行，右滑标记完成

#### 4.1.5 日终总结页

独立窗口或全屏 Popover，包含：
- 等级展示（大字体 S/A/B/C/D）
- 统计卡片（完成数、总时长、偏差率）
- AI 评价文本
- 明日建议
- 驳斥按钮：点击后展示 AI 评分理由和依据，用户可输入想法要求重新评分（每日限 3 次，用完后变灰不可点）
- 操作按钮：[同步到备忘录] [关闭]

#### 4.1.6 历史记录页

- 日历视图，每格显示日期 + 当天评分等级
- 未评分的天显示"—"
- 点击某天可查看该天的详细日终总结

#### 4.1.7 设置页

- API Key 输入框（智谱 AI，必填，存储于 Keychain）
- AI 服务配置（V1 预留入口，暂不可操作）
- 并行任务开关
- 开机自启开关
- 数据管理（清除历史数据）

### 4.2 交互规范

| 交互 | 行为 |
|------|------|
| 点击菜单栏图标 | 展开/收起主面板 |
| 提交输入 | 回车键或点击提交按钮 |
| 点击必做项 | 若无运行任务 → 开始计时；若有运行任务 → 停止当前，启动新任务 |
| 点击"今日总结" | 若已评分 → 显示评分结果；若未评分 → 触发评分流程 |
| 点击"结束今天" | 结束所有运行中任务 → 调用 AI 评分 → 展示评分页 |

### 4.3 状态与反馈

| 状态 | 反馈 |
|------|------|
| AI 解析中 | 输入区下方显示加载动画 |
| AI 解析失败 | 输入区下方显示错误提示，保留输入文本 |
| 任务计时中 | 菜单栏实时更新计时 |
| 日终评分中 | 显示加载动画 |
| 评分完成 | 弹出评分页面 |
| 同步完成 | 按钮状态变为"已同步 ✓" |

---

## 5. 非功能需求

### 5.1 性能要求

| 编号 | 需求 |
|------|------|
| NFR-PERF-001 | 应用冷启动时间 < 2 秒 |
| NFR-PERF-002 | 主面板展开响应时间 < 200ms |
| NFR-PERF-003 | 计时器刷新频率每秒 1 次 |
| NFR-PERF-004 | 内存占用 < 100MB |
| NFR-PERF-005 | AI 调用不阻塞 UI，在后台线程执行 |

### 5.2 可靠性要求

| 编号 | 需求 |
|------|------|
| NFR-REL-001 | 本地数据每日自动备份（SwiftData 基于 CoreData 自带机制） |
| NFR-REL-002 | AI 服务不可用时，本地计时功能正常使用 |
| NFR-REL-003 | 应用崩溃后重启，计时任务可恢复 |
| NFR-REL-004 | 网络中断时暂存用户输入，网络恢复后提示重新提交 |

### 5.3 安全性要求

| 编号 | 需求 |
|------|------|
| NFR-SEC-001 | AI API Key 存储在 macOS Keychain 中 |
| NFR-SEC-002 | 所有 AI 调用使用 HTTPS 加密传输 |
| NFR-SEC-003 | 用户数据仅存储在本地，不上传至任何第三方服务器（AI API 调用除外） |

### 5.4 可维护性要求

| 编号 | 需求 |
|------|------|
| NFR-MAIN-001 | AI 服务层通过 Protocol 抽象，便于替换底层实现 |
| NFR-MAIN-002 | 代码遵循 MVVM 架构模式 |
| NFR-MAIN-003 | 关键业务逻辑需有单元测试覆盖 |

### 5.5 兼容性要求

| 编号 | 需求 |
|------|------|
| NFR-COMP-001 | 支持 macOS 14.0 (Sonoma) 及以上版本 |
| NFR-COMP-002 | 支持 Apple Silicon (M1+) 和 Intel 架构 |

---

## 6. 接口规范

### 6.1 外部接口

#### 6.1.1 智谱 AI API

| 项目 | 说明 |
|------|------|
| 协议 | HTTPS POST |
| 地址 | 智谱 AI 官方 API Endpoint |
| 认证 | API Key（存储于 Keychain） |
| 超时 | 30 秒 |
| 重试 | 失败后最多重试 2 次，间隔 3 秒 |

**请求格式**：

```json
{
  "model": "glm-5.1",
  "messages": [
    {
      "role": "system",
      "content": "<系统提示词>"
    },
    {
      "role": "user",
      "content": "<用户自然语言输入>"
    }
  ],
  "temperature": 0.3,
  "response_format": {
    "type": "json_object"
  }
}
```

**响应格式（想法解析）**：

```json
{
  "tasks": [
    {
      "title": "string",
      "category": "string",
      "estimated_minutes": 90,
      "priority": "high|medium|low",
      "recommended": true,
      "reason": "string"
    }
  ]
}
```

**响应格式（日终评分）**：

```json
{
  "grade": "S|A|B|C|D",
  "summary": "string",
  "stats": {
    "total_tasks": 5,
    "completed_tasks": 4,
    "total_planned_minutes": 240,
    "total_actual_minutes": 265,
    "deviation_rate": 0.1
  },
  "suggestion": "string"
}
```

#### 6.1.2 macOS 备忘录（Apple Notes）

| 项目 | 说明 |
|------|------|
| 方式 | AppleScript 桥接 |
| 操作 | 创建新备忘录，写入格式化的日终总结内容 |
| 内容格式 | 纯文本 + Markdown |

### 6.2 内部接口

#### 6.2.1 AI 服务协议（AIServiceProtocol）

```swift
protocol AIServiceProtocol {
    func parseThoughts(input: String, existingTasks: [Task]) async throws -> [ParsedTask]
    func generateDailyGrade(summary: DailySummaryInput) async throws -> DailyGrade
    func appealGrade(originalGrade: DailyGrade, originalInput: DailySummaryInput, userFeedback: String) async throws -> DailyGrade
}
```

#### 6.2.2 数据持久化接口

```swift
protocol DataStoreProtocol {
    func saveThought(_ thought: Thought) throws
    func saveTask(_ task: Task) throws
    func saveSessionLog(_ log: SessionLog) throws
    func saveDailySummary(_ summary: DailySummary) throws
    func fetchTasks(date: Date, pool: TaskPool) throws -> [Task]
    func fetchSessionLogs(taskId: UUID) throws -> [SessionLog]
    func fetchSessionLogs(taskId: UUID, date: Date) throws -> [SessionLog]
    func fetchDailySummary(date: Date) throws -> DailySummary?
    func fetchDailySummaries(from: Date, to: Date) throws -> [DailySummary]
    func migrateUnfinishedMustDo(date: Date) throws
}
```

---

## 7. 数据模型

### 7.1 Thought（想法输入）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | UUID | PK | 主键 |
| raw_text | String | NOT NULL | 用户原始输入文本 |
| created_at | Date | NOT NULL, DEFAULT NOW | 输入时间 |
| processed | Bool | DEFAULT FALSE | 是否已被 AI 解析 |

### 7.2 Task（任务）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | UUID | PK | 主键 |
| thought_id | UUID | FK → Thought.id | 关联的原始想法 |
| title | String | NOT NULL | 任务名称 |
| category | String | NOT NULL | 分类（工作/生活/学习等） |
| estimated_minutes | Int | NOT NULL | AI 预估时长（分钟） |
| priority | String | NOT NULL | 优先级（high/medium/low） |
| ai_recommended | Bool | DEFAULT FALSE | AI 是否推荐为必做 |
| recommendation_reason | String | nullable | AI 推荐理由 |
| pool | Enum | NOT NULL | 所在池（idea_pool / must_do） |
| sort_order | Int | DEFAULT 0 | 排序权重 |
| status | Enum | NOT NULL, DEFAULT pending | 任务状态 |
| date | Date | NOT NULL | 所属日期 |
| created_at | Date | NOT NULL, DEFAULT NOW | 创建时间 |
| created_date | Date | NOT NULL | 创建日期（用于想法池中按日区分） |
| attempted | Bool | DEFAULT FALSE | 是否曾经尝试执行过（跨天移回想法池时标记为 TRUE） |

### 7.3 SessionLog（计时记录）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | UUID | PK | 主键 |
| task_id | UUID | FK → Task.id, NOT NULL | 关联任务 |
| started_at | Date | NOT NULL | 开始时间 |
| ended_at | Date | nullable | 结束时间（null = 进行中） |
| duration_seconds | Int | DEFAULT 0 | 时长（秒） |
| date | Date | NOT NULL | 执行日期（用于按天聚合统计） |

> 一个任务可对应多条 SessionLog，每次执行新增一条记录，跨天执行时各自独立。

### 7.4 DailySummary（日终总结）

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | UUID | PK | 主键 |
| date | Date | NOT NULL, UNIQUE | 日期 |
| grade | String | NOT NULL | 等级（S/A/B/C/D） |
| summary | String | NOT NULL | AI 评价文本 |
| suggestion | String | nullable | 明日建议 |
| total_planned_minutes | Int | NOT NULL | 计划总时长 |
| total_actual_minutes | Int | NOT NULL | 实际总时长 |
| completed_count | Int | NOT NULL | 完成任务数 |
| total_count | Int | NOT NULL | 总任务数 |
| synced_to_notes | Bool | DEFAULT FALSE | 是否已同步到备忘录 |
| appeal_count | Int | DEFAULT 0 | 已申诉次数（每日限 3 次） |
| grading_basis | String | nullable | AI 评分理由和依据（申诉时展示给用户） |
| created_at | Date | NOT NULL, DEFAULT NOW | 创建时间 |

---

## 8. 任务状态机

```
                    ┌──────────────────────────────┐
                    │                              │
                    ▼                              │
  ┌──────────┐  点击开始  ┌──────────┐  点击其他   │
  │ pending  │─────────→│ running  │──────────┐   │
  │ (待执行)  │          │ (执行中)  │          │   │
  └──────────┘          └────┬─────┘          │   │
       │                     │                │   │
       │              手动暂停│                │   │
       │                     ▼                │   │
       │              ┌──────────┐            │   │
       │              │  paused  │──── 继续 →│   │
       │              │ (已暂停)  │   恢复为   │   │
       │              └──────────┘  running   │   │
       │                     │                │   │
       │                     │ 标记完成        │   │
       │                     ▼                ▼   │
       │              ┌──────────┐         重新开始
       │              │   done   │            当前
       │              │ (已完成)  │         任务
       │              └──────────┘          │
       │                     ▲              │
       │                     │              │
       └─────────────────────┘──────────────┘
                  (从 pending 直接标记完成)
```

> 注：V1 版本不实现手动暂停功能（paused 状态预留），用户切换任务时直接从 running 转为 done 或切换到其他任务。

---

## 9. 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| AI API 调用超时 | 提示"AI 服务响应超时，请稍后重试"，保留输入文本 |
| AI API 调用失败（非 200） | 提示"AI 服务暂时不可用"，保留输入文本 |
| AI 返回格式异常 | 提示"解析失败，请重新描述"，保留输入文本 |
| 网络不可用 | 提示"网络不可用，请检查网络连接" |
| 备忘录同步失败 | 提示"同步失败"，允许重试，不影响主流程 |
| 数据库写入失败 | 记录日志，提示用户，不静默失败 |

---

## 10. 优先级与版本规划

### P0 — V1 MVP（必须实现）

- 自然语言输入 + AI 解析 + 想法池
- 想法池跨天保留 + 创建日期显示
- 必做项管理（AI 推荐 + 手动挑选，加入后从想法池消失）
- 任务正计时 + 菜单栏显示（时钟图标）
- 任务切换（自动停止上一个）
- 已完成任务灰色划线 + 移到底部
- 跨天未完成必做项自动移回想法池 + 标记"已尝试"
- 日终 AI 评分（S-D）
- 评分申诉机制（驳斥按钮，每日限 3 次）
- 次日启动自动补评昨日
- API Key 配置（未配置时显示"请配置 API"）

### P1 — V1.x（尽快实现）

- 同步到备忘录
- 历史记录日历视图
- 任务排序调整
- AI 解析失败降级方案
- 计时恢复（应用重启后）

### P2 — V2.0（后续迭代）

- 并行任务支持
- 开机自启
- 应用关闭确认
- 周报/月报
- 多 AI 服务切换配置
- 输入长度限制

### P2 — V2.0（后续迭代）

- 并行任务支持
- 开机自启
- 应用关闭确认
- 周报/月报
- 多 AI 服务切换配置

---

## 附录 A：AI Prompt 设计

### A.1 想法解析 Prompt（V1 草稿）

```
你是一个任务管理助手。用户会用自然语言描述想法和计划。
请将用户的输入拆解为结构化的任务列表。

已有任务列表（避免重复）：
{{existing_tasks}}

用户输入：
{{user_input}}

要求：
1. 每个任务必须是可执行、可完成的具体行动
2. 任务粒度控制在 15-90 分钟，超过的请拆分
3. 为每个任务预估合理时长（分钟）
4. 为每个任务分类（工作/生活/学习/其他）
5. 判断优先级（high/medium/low）并说明理由
6. 推荐其中最应该今天完成的任务（recommended = true）
7. 输出严格的 JSON 格式

输出格式：
{
  "tasks": [
    {
      "title": "string",
      "category": "string",
      "estimated_minutes": number,
      "priority": "high|medium|low",
      "recommended": boolean,
      "reason": "string"
    }
  ]
}
```

### A.2 日终评分 Prompt（V1 草稿）

```
你是一个效率教练。根据用户今天的任务完成情况，给出评价和评分。

今日任务数据：
- 必做项总数：{{total_count}}
- 已完成必做项：{{completed_count}}
- 计划总时长：{{total_planned_minutes}} 分钟
- 实际总时长：{{total_actual_minutes}} 分钟
- 想法池额外完成：{{extra_completed}} 个

任务明细：
{{task_details}}

评分标准（参考基准，可根据具体情况调整）：
- S：必做项全部完成，时间偏差 ≤10%，额外完成想法池任务
- A：必做项全部完成，时间偏差 ≤20%
- B：必做项完成 ≥80%
- C：必做项完成 ≥50%
- D：必做项完成 <50%

要求：
1. 给出等级（S/A/B/C/D）
2. 写一段评价（100-200字），肯定做得好的，指出可改进的
3. 给出明日建议
4. 输出严格的 JSON 格式

输出格式：
{
  "grade": "S|A|B|C|D",
  "summary": "string",
  "stats": {
    "total_tasks": number,
    "completed_tasks": number,
    "total_planned_minutes": number,
    "total_actual_minutes": number,
    "deviation_rate": number
  },
  "suggestion": "string"
}
```

---

## 附录 B：备忘录同步内容模板

```
📋 NL Plan 日终总结 — {{date}}

等级：{{grade}}

📊 统计
- 必做项完成：{{completed_count}}/{{total_count}}
- 计划时长：{{total_planned_minutes}} 分钟
- 实际时长：{{total_actual_minutes}} 分钟
- 时间偏差：{{deviation_rate}}%

📝 AI 评价
{{summary}}

💡 明日建议
{{suggestion}}

---
任务明细：
{{task_details}}
```
