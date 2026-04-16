# NL Plan for Mac

一款基于 AI 的 macOS 菜单栏计划管理工具，帮助你用自然语言规划每日任务、追踪时间、获得 AI 智能总结。

## 功能

- 📝 **自然语言输入** — 用一句话描述你的计划，AI 自动拆解为任务，支持连续输入非阻塞处理
- 📋 **解析队列** — 提交后立即可以继续输入，队列逐个处理并展示实时状态
- ⏱ **专注计时** — 为每个任务启动计时，菜单栏实时显示进度
- 💡 **想法池** — 随时记录灵感，稍后转化为任务
- 📊 **AI 日终总结** — 自动评分、生成总结和明日建议
- 📅 **历史回顾** — 查看往日的计划和表现

## 系统要求

- macOS 14.0 (Sonoma) 及以上
- Xcode 15.0 及以上

## 构建与运行

```bash
# 克隆项目
git clone https://github.com/Allertant/nl-plan-for-mac.git
cd nl-plan-for-mac

# 构建
swift build

# 或在 Xcode 中打开 Package.swift 直接运行
```

## 权限说明

| 权限 | 用途 | 触发时机 |
|------|------|----------|
| **UserDefaults + Base64** | 存储 AI API Key | 首次保存或读取 API Key 时 |

应用使用 UserDefaults + Base64 编码存储 API Key，避免未签名应用触发 Keychain 反复弹窗。正式签名分发后可按需迁移回 Keychain Services。

## 配置

1. 点击菜单栏图标打开面板
2. 点击底部「设置」按钮
3. 输入你的 [DeepSeek API Key](https://platform.deepseek.com/) 并保存

## 技术栈

- **UI**：SwiftUI + MenuBarExtra
- **数据持久化**：SwiftData
- **AI 服务**：DeepSeek（通过 AIServiceProtocol 抽象，可扩展）
- **安全存储**：UserDefaults + Base64 编码

## License

MIT
