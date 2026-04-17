import SwiftUI

/// 队列详情容器视图
struct QueueDetailContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let inputVM = appState.inputViewModel,
               let queueItemID = appState.currentPage.queueItemID,
               let queueItem = inputVM.queueItems.first(where: { $0.id == queueItemID }) {
                QueueDetailView(viewModel: inputVM, queueItem: queueItem)
            } else {
                // 找不到队列项，返回主页面
                Color.clear
                    .frame(width: 360, height: 520)
                    .onAppear {
                        appState.currentPage = .main
                    }
            }
        }
    }
}
