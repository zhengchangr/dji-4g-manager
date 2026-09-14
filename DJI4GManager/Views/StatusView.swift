import SwiftUI

struct StatusView: View {
    @Environment(AppState.self) private var appState
    @State private var showPhoneEditor = false
    @State private var phoneDraft = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if appState.isConnected {
                    heroCard
                    LazyVGrid(columns: columns, spacing: 14) {
                        metricCard("模块代际", value: appState.detectedGeneration?.detailText ?? "未知", icon: "cpu")
                        metricCard("SIM 状态", value: appState.status.simState, icon: "simcard")
                        metricCard("运营商", value: appState.status.operatorName.isEmpty ? "未知" : appState.status.operatorName, icon: "building.2")
                        signalCard
                        metricCard("网络制式", value: appState.status.networkMode.isEmpty ? "未知" : appState.status.networkMode, icon: "cellularbars")
                        metricCard("频段 / 信道", value: bandText, icon: "antenna.radiowaves.left.and.right")
                        metricCard("USB 模式", value: appState.status.usbNetModeDescription, icon: "cable.connector")
                        metricCard("IMEI", value: appState.status.imei.isEmpty ? "未知" : appState.status.imei, icon: "number", monospaced: true)
                        phoneCard
                        metricCard("固件版本", value: appState.status.revision.isEmpty ? "未知" : appState.status.revision, icon: "gearshape")
                        metricCard("IP 地址", value: appState.status.ipAddress.isEmpty ? "未知" : appState.status.ipAddress, icon: "network", monospaced: true)
                    }
                    if let updated = appState.status.lastUpdated {
                        Text("更新于 \(updated.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    EmptyStateView(
                        icon: appState.isGen2Only ? "simcard" : "cable.connector.slash",
                        title: appState.isGen2Only ? "已识别二代模块（2ca3:4009）" : "等待模块接入",
                        message: appState.isGen2Only
                            ? "二代模块封闭了 USB 管理口，无法读取运营商、信号、IMEI、手机号、固件等状态。请切换到「上网」页查看它是否被系统识别为网卡。"
                            : "请将大疆一代（2ca3:4006）或二代（2ca3:4009）4G 模块通过支持数据传输的 USB-C 线连接到 Mac。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
            .padding(18)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新状态")
            }
        }
        .sheet(isPresented: $showPhoneEditor) {
            phoneEditor
        }
    }

    private var phoneCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "phone")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                    Text("手机号码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if appState.status.phoneNumber.isEmpty {
                        Button("手动填写") {
                            phoneDraft = appState.manualPhoneNumber
                            showPhoneEditor = true
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                Text(appState.displayPhoneNumber.isEmpty ? "未知" : appState.displayPhoneNumber)
                    .font(.callout.weight(.medium))
                    .monospaced()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !appState.status.phoneNumber.isEmpty {
                    Text("来自模块（AT+CNUM）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if !appState.manualPhoneNumber.isEmpty {
                    Text("手动设置（保存在本机）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var phoneEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置手机号码")
                .font(.title3.weight(.semibold))
            Text("模块未从 SIM 卡读到本机号码（AT+CNUM 无返回）。手动填写的号码只保存在本机，用于展示。")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("手机号码（国际格式 +86…）", text: $phoneDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { showPhoneEditor = false }
                    .djGlass()
                Button("保存") {
                    appState.manualPhoneNumber = phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    showPhoneEditor = false
                }
                .djGlassProminent()
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var heroCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image(systemName: "simcard.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(moduleName)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        StatusBadge(title: phaseBadgeText, color: phaseBadgeColor)
                        if let generation = appState.detectedGeneration {
                            StatusBadge(title: generation.detailText, color: .blue)
                        }
                        if !appState.status.model.isEmpty {
                            StatusBadge(title: appState.status.model, color: .secondary)
                        }
                    }
                }
                Spacer()
                if appState.status.signalLevel >= 0 {
                    VStack(alignment: .trailing, spacing: 6) {
                        SignalBars(level: appState.status.signalPercent)
                        Text(appState.status.signalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metricCard(_ title: String, value: String, icon: String, monospaced: Bool = false) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.callout.weight(.medium))
                    .monospaced(monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var signalCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                    Text("信号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    SignalBars(level: appState.status.signalPercent)
                    Text(appState.status.signalDescription)
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    private var moduleName: String {
        if !appState.status.model.isEmpty {
            return "\(appState.status.manufacturer) \(appState.status.model)"
        }
        if let generation = appState.detectedGeneration {
            return "大疆\(generation.displayName) 4G 模块"
        }
        return "大疆 4G 模块"
    }

    private var bandText: String {
        let band = appState.status.band
        let channel = appState.status.channel
        if band.isEmpty, channel.isEmpty { return "未知" }
        if band.isEmpty { return "信道 \(channel)" }
        if channel.isEmpty { return band }
        return "\(band) · 信道 \(channel)"
    }

    private var phaseBadgeText: String {
        switch appState.phase {
        case .connected: "已连接"
        case .switching: "切换中"
        default: "状态未知"
        }
    }

    private var phaseBadgeColor: Color {
        switch appState.phase {
        case .connected: .green
        case .switching: .orange
        default: .secondary
        }
    }
}

#Preview {
    StatusView()
        .environment(AppState())
}
