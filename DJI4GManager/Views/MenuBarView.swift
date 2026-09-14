import AppKit
import SwiftUI

/// 菜单栏快捷入口。
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 8, height: 8)
                Text(phaseText)
                    .font(.callout.weight(.medium))
            }
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Label("网络", systemImage: "network")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            networkRow(title: "下载速度", value: NetworkMonitor.formattedSpeed(bytesPerSecond: appState.currentSpeedDown ?? 0), icon: "arrow.down")
            networkRow(title: "上传速度", value: NetworkMonitor.formattedSpeed(bytesPerSecond: appState.currentSpeedUp ?? 0), icon: "arrow.up")
            networkRow(title: "总使用流量", value: NetworkMonitor.formattedBytes(appState.network.sessionTotal), icon: "sum")
            Text("本次运行累计 · 以运营商账单为准")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开 DJI 4G Manager", systemImage: "macwindow")
            }
            Divider()
            Button("退出 DJI 4G Manager") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 250)
    }

    private var phaseText: String {
        return switch appState.phase {
        case .connected:
            if let generation = appState.detectedGeneration {
                "\(generation.displayName)模块已连接"
            } else {
                "模块已连接"
            }
        case .switching: "模块切换中…"
        case .gen2Only: "已识别二代模块（2ca3:4009）"
        case .failed: "连接失败"
        case .searching: "等待模块…"
        }
    }

    private var detailText: String {
        if appState.isGen2Only {
            if appState.network.isAvailable {
                return "管理口不可用 · 网卡 \(appState.network.activeInterface) 已就绪"
            }
            return "管理口不可用 · 等待系统识别网卡"
        }
        let generationPrefix = appState.detectedGeneration.map { "\($0.displayName)模块 · " } ?? ""
        if appState.status.usbNetMode >= 0 {
            return generationPrefix + appState.status.usbNetModeDescription
        }
        return generationPrefix + appState.status.simState
    }

    private func networkRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .monospaced()
        }
    }

    private var indicatorColor: Color {
        return switch appState.phase {
        case .connected: .green
        case .switching: .orange
        case .gen2Only: .orange
        case .failed: .red
        case .searching: .secondary
        }
    }
}
