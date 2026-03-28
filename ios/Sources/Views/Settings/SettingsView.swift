import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var saveMessage: String?
    @State private var saveError: String?

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            Form {
                Section("API 凭证") {
                    TextField("API Host", text: $appModel.settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("API Token", text: $appModel.settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("API Time", text: $appModel.settings.time)
                        .keyboardType(.numberPad)

                    TextField("User ID", text: $appModel.settings.userID)
                        .keyboardType(.numberPad)
                }

                Section("说明") {
                    Text("原仓库的本机代理抓包功能无法在 iOS App 内等价实现，iOS 版改为手动录入凭证。")
                    Text("请求会直接访问 `http://hqapp1.bit.edu.cn`，已在工程里开启 ATS 明文白名单。")
                }

                Section("通知") {
                    Button("请求本地通知权限") {
                        Task {
                            await appModel.requestNotificationAuthorization()
                            saveMessage = "已发起通知权限请求。"
                        }
                    }
                }

                Section {
                    Button("保存配置", action: saveSettings)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("设置")
            .alert("保存成功", isPresented: Binding(
                get: { saveMessage != nil },
                set: { if !$0 { saveMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(saveMessage ?? "")
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func saveSettings() {
        do {
            try appModel.saveSettings()
            saveMessage = "配置已保存。"
        } catch {
            saveError = error.localizedDescription
        }
    }
}
