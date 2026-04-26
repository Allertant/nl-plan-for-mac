# NLPlan

macOS 菜单栏任务管理应用，使用 SwiftUI + SwiftData，核心逻辑在 `Packages/NLPlanKit`。

## 页面导航动画规则

所有从主页进入二级页面的切换必须有渐入动画（opacity 0→1，时长 0.15s），避免数据未加载完成时的页面闪动。返回主页不添加动画。

实现方式：在 `MainContentView` 中通过 `secondaryPageOpacity` 状态 + `onChange(of: currentPage)` 统一控制，无需在每个容器视图中单独处理。
