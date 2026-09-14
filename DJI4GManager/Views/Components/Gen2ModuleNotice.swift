import SwiftUI

/// 检测到二代模块时的提示卡。
///
/// 二代模块封闭了 USB AT 管理口，软件无法读取固件 / IMEI / 手机号，
/// 也无法使用短信、eSIM、AT 调试与模式切换；它只能被当作可能的纯网卡使用。
struct Gen2ModuleNotice: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "simcard")
                        .foregroundStyle(Color.orange)
                    Text("检测到大疆二代 4G 模块（2ca3:4009）")
                        .font(.callout.weight(.semibold))
                    StatusBadge(title: "仅网卡模式", color: .orange)
                }

                Text("二代模块的 USB 管理口已被封闭，因此无法读取固件、IMEI、手机号，也无法使用短信、eSIM、AT 调试和模式切换。它能不能在 Mac 上作为纯网卡上网，取决于系统是否把它的网卡接口识别出来——请到「系统设置 → 网络」查看是否出现 Baiwang 网卡。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.network.isAvailable {
                    Label("已发现活动的 USB/以太网网卡（\(appState.network.activeInterface)）。若它对应的网络服务名含 Baiwang，可到「上网」页查看并设为默认出口。", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Label("尚未发现模块网卡。若系统设置里能看到 Baiwang，请先确认它处于「已连接」状态。", systemImage: "magnifyingglass")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    Gen2ModuleNotice()
        .environment(AppState())
        .padding()
        .frame(width: 760)
}
