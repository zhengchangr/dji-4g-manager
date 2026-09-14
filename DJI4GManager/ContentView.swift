import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: AppSection? = .status

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 270)
        } detail: {
            detail
                .navigationTitle(selection?.title ?? "DJI 4G Manager")
        }
        .task { appState.start() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("管理") {
                ForEach([AppSection.status, .internet, .sms, .esim, .at]) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            Section("系统") {
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                    .tag(AppSection.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 8, height: 8)
                Text(phaseText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if appState.isGen2Only {
                Gen2ModuleNotice()
                    .padding([.horizontal, .top], 16)
            }

            if let error = appState.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                    Spacer()
                    Button {
                        appState.lastError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding([.horizontal, .top], 16)
            }

            switch selection ?? .status {
            case .status: StatusView()
            case .internet: InternetView()
            case .sms: SMSView()
            case .esim: ESIMView()
            case .at: ATConsoleView()
            case .settings: SettingsView()
            }
        }
    }

    private var indicatorColor: Color {
        switch appState.phase {
        case .connected: .green
        case .switching: .orange
        case .gen2Only: .orange
        case .failed: .red
        case .searching: .secondary
        }
    }

    private var phaseText: String {
        switch appState.phase {
        case .connected:
            if let generation = appState.detectedGeneration {
                return "\(generation.displayName)模块已连接"
            }
            return "模块已连接"
        case .switching: return "模块切换中…"
        case .gen2Only: return "已识别二代模块"
        case .failed: return "连接失败"
        case .searching: return "等待模块…"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
