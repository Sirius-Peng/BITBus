import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("查询", systemImage: "magnifyingglass")
                }

            TasksView()
                .tabItem {
                    Label("任务", systemImage: "checklist")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}
