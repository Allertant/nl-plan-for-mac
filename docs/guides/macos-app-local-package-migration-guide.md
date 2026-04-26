# macOS App + Local Package 改造指导方案

这份文档不是只服务于 `NLPlan`，而是总结一类项目的通用改造方案：

- 当前仓库是纯 Swift Package，或“工程入口不清晰”
- 想把它整理成更接近 Apple 推荐方式的 macOS App 工程
- 希望外层是 `xcodeproj`，内层是可复用的 local Swift package
- 未来可能继续拆分多个 package

## 1. 目标形态

推荐目标结构：

```text
repo-root/
  MyApp.xcodeproj
  MyApp/
    MyApp.swift
    Info.plist
  Packages/
    MyAppKit/
      Package.swift
      Sources/
        MyAppKit/
          ...
      Tests/
        MyAppKitTests/
          ...
  docs/
```

其中：

- `MyApp.xcodeproj`
  - 外层 app 工程入口
  - 管理 scheme、签名、bundle、plist、Xcode 构建配置
- `MyApp/`
  - 很薄的 app host
  - 只保留 `@main App`、`Info.plist`、极少量 app 级入口逻辑
- `Packages/MyAppKit/`
  - 真正的业务代码包
  - 包含 UI、数据层、领域层、AI 逻辑等
  - 可被 app project 本地引用

## 2. 为什么推荐这种结构

这种结构接近 Apple 现在的推荐路径：

- App project 作为应用入口
- local package 作为项目内可复用模块

它的优点：

- app 和业务代码职责清晰
- Xcode 构建更自然，支持 `xcodebuild -project ...`
- package 可单独测试
- 未来可以继续拆多个 package
- 比“所有代码都堆在一个 app target”更适合中大型项目

## 3. 命名约定

推荐命名方式：

- App target / App bundle：`MyApp`
- Code package / Code module：`MyAppKit`
- Test target：`MyAppKitTests`

不要混成：

- app 叫 `MyApp`
- 代码包也叫 `MyApp`

原因：

- Xcode 构建产物容易撞名
- Swift module 和 app target 同名时，后续排查问题会更费劲

也不要让测试 target 命名漂移，例如：

- `MyAppKit`
- `MyAppTests`

更清晰的做法是：

- `MyAppKit`
- `MyAppKitTests`

这样一眼就知道测试在测哪个模块。

## 4. 标准改造步骤

### 阶段 A：先建立外层 app 工程

目标：

- 先让仓库有一个明确的 Xcode app 入口

做法：

1. 新建 `MyApp.xcodeproj`
2. 新建薄 app host 目录，例如 `MyApp/`
3. 新建 `MyApp.swift` 作为 `@main App`
4. 新建 `Info.plist`
5. 让 host 只负责挂载业务模块暴露出来的 `Scene` 或根视图

### 阶段 B：把业务代码整理成 local package

目标：

- 把主要代码从“直接属于 app target”改成“属于 package”

做法：

1. 建立 package
2. 业务模块命名为 `MyAppKit`
3. 外层 app 通过 Xcode 的 local package 机制引用该包
4. app host 内只写：

```swift
import SwiftUI
import MyAppKit

@main
struct MyApp: App {
    var body: some Scene {
        MyAppMainScene()
    }
}
```

### 阶段 C：把 package 整理成标准目录

标准目录约定：

```text
Package.swift
Sources/
  MyAppKit/
Tests/
  MyAppKitTests/
```

不要长期停留在非标准结构，例如：

- 业务代码目录自定义成 `MyApp/`
- 测试目录自定义成 `MyAppTests/`

虽然技术上可行，但不利于长期维护。

### 阶段 D：如果将来有多个 package，再下沉到 `Packages/`

如果仓库里以后不止一个 package，推荐结构变成：

```text
Packages/
  MyAppKit/
  MyAppAI/
  MyAppUI/
```

这样每个 package 都有自己的：

- `Package.swift`
- `Sources/`
- `Tests/`

不会与根目录冲突。

## 5. 什么时候需要 `Packages/`

### 单 package 阶段

如果仓库里只有一个 package，下面两种都可以：

```text
repo-root/
  Package.swift
  Sources/
  Tests/
```

或：

```text
repo-root/
  MyApp.xcodeproj
  Packages/
    MyAppKit/
```

### 多 package 阶段

如果将来需要多个 package，强烈建议使用：

```text
Packages/<PackageName>/
```

原因：

- 一个目录只能有一个 `Package.swift`
- 多个 package 不能都直接堆在仓库根目录

## 6. 面向菜单栏 macOS App 的特殊点

如果是菜单栏应用，通常还会有这些需求：

- `LSUIElement = true`
  - 隐藏 Dock 图标
- `MenuBarExtra`
  - 作为主入口
- `AppDelegate`
  - 处理菜单栏、窗口、生命周期补充逻辑

建议：

- 这些仍然放在业务 package 内
- 外层 app host 不要承载太多具体业务逻辑

换句话说：

- app host 负责“启动”
- package 负责“真正的应用行为”

## 7. 当前这类结构的推荐边界

### 当前已经足够好的状态

如果项目已经是：

- `xcodeproj` 作为外层入口
- 业务代码在 `Packages/MyAppKit`
- package 使用 `Sources/` 和 `Tests/`

那已经是相当合理的结构了。

### 暂时不必继续拆分的情况

如果业务代码虽然多，但仍然耦合紧密，先不要急着拆：

- `MyAppKit`
- `MyAppAI`
- `MyAppUI`
- `MyAppPersistence`

拆太早会增加维护成本。

更合理的顺序通常是：

1. 先完成 app + local package 结构
2. 跑通构建和测试
3. 再根据真实边界拆第二个、第三个 package

## 8. 构建命令建议

### package 测试

进入 package 目录：

```bash
cd Packages/MyAppKit
swift test
```

### app 构建

在仓库根目录：

```bash
xcodebuild \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .DerivedData/MyApp \
  -clonedSourcePackagesDirPath .DerivedData/MyApp/SourcePackages \
  build
```

推荐显式指定：

- `-derivedDataPath`
- `-clonedSourcePackagesDirPath`

好处：

- 输出目录稳定
- 不依赖系统默认缓存路径
- 更适合自动化脚本和 AI 代理

## 9. 常见坑

### 1. app target 和 package module 同名

问题：

- 容易发生产物路径冲突
- 编译输出、module、bundle 名容易打架

建议：

- app：`MyApp`
- package：`MyAppKit`

### 2. 测试 target 命名不统一

问题：

- 可读性差

建议：

- `MyAppKitTests`

### 3. package 结构不标准

问题：

- Xcode / SPM 虽然能跑，但后续认知成本高

建议：

- 用标准 `Sources/` + `Tests/`

### 4. 根目录只有一个 package 时偷懒不分层

问题：

- 将来需要多个 package 时还要再迁一次

建议：

- 如果明确未来会继续拆包，尽早采用 `Packages/`

## 10. 最佳实践总结

一套适合这类 macOS 项目的推荐方案：

1. 外层 `xcodeproj`
2. 薄 app host
3. 业务代码放 `Packages/MyAppKit`
4. package 使用标准 `Sources/` 和 `Tests/`
5. 测试 target 命名与代码包命名保持成对
6. app 与 package 不同名
7. 用固定的 `DerivedData` 路径进行 CLI 构建

如果是类似 `NLPlan` 这种已经不算小的菜单栏应用，这基本就是一条长期可维护的工程组织方案。
