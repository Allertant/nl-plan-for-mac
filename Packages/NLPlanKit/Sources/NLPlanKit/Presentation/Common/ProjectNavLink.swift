import SwiftUI

/// 导航到项目详情页的统一组件，保证从不同入口（想法池/历史详情）进入的逻辑一致
struct ProjectNavLink: View {
    @Environment(AppState.self) private var appState
    let ideaId: UUID
    var returnTo: AppState.Page? = nil

    var body: some View {
        HoverTextButton("查看项目", color: .indigo, isEmphasized: true) {
            if let returnTo { appState.returnPage = returnTo }
            appState.currentPage = .projectDetail(ideaId)
        }
    }
}
