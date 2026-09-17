import SwiftUI

struct ATConsoleView: View {
    @Environment(AppState.self) private var appState
    @State private var command = ""
    @State private var busy = false

    private let presets = [
        "AT",
        "AT+CSQ",
        "AT+CPIN?",
        "AT+COPS?",
        "AT+QNWINFO",
        "AT+QCFG=\"usbnet\"",
        "AT+QCFG=\"usbcfg\"",
        "AT+CGDCONT?",
        "AT+CGACT?",
        "AT+CGPADDR=1",
        "AT+CNUM",
        "AT+CPBS=\"ON\"",
        "AT+CPBR=1,10",
        "AT+CPBS?",
        "AT+CGSN",
    ]

    var body: some View {
        Group {
            if appState.isGen2Only {
                EmptyStateView(
                    icon: "terminal",
                    title: "二代模块不支持 AT 调试",
                    message: "AT 指令需要访问模块的 USB 管理口，二代模块已封闭该通道。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    inputBar
                    Divider()
                    logList
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("输入 AT 指令，例如 AT+CSQ", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { run() }
                Button {
                    run()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .djGlassProminent()
                .disabled(command.isEmpty || busy)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) { command = preset }
                            .djGlass()
                    }
                }
            }
        }
        .padding(14)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.atLog.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("→ \(entry.command)")
                                    .font(.callout.weight(.semibold))
                                    .monospaced()
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.response)
                                .font(.callout)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .djGlassPanel(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .id(entry.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: appState.atLog.count) {
                if let last = appState.atLog.last {
                    proxy.scrollTo(last.id, anchor: .top)
                }
            }
        }
    }

    private func run() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        busy = true
        Task {
            _ = await appState.runAT(trimmed)
            busy = false
        }
    }
}

#Preview {
    ATConsoleView()
        .environment(AppState())
}
