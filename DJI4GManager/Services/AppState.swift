import Foundation
import AppKit
import Network
import Observation
import UserNotifications

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case searching
        case connected
        case switching
        case gen2Only
        case failed(String)
    }

    var phase: Phase = .searching
    /// 当前识别到的模块代际（未插模块时为 nil）。
    var detectedGeneration: DJIModuleGeneration?
    var status = ModuleStatus()
    var pdp = PDPStatus()
    var network = NetworkSnapshot()
    var networkServices: [NetworkServiceInfo] = []
    var messages: [SMSMessage] = []
    var esim = ESIMState()
    var lastError: String?
    var isRefreshing = false
    var autoPollSMS = true
    var notificationsEnabled = true
    var refreshInterval: TimeInterval = 4
    var currentSpeedDown: Double?
    var currentSpeedUp: Double?
    var esimBusy = false
    var manualPhoneNumber: String {
        didSet {
            UserDefaults.standard.set(manualPhoneNumber, forKey: "manualPhoneNumber")
        }
    }
    var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: "showInDock")
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }

    struct ATLogEntry: Identifiable {
        let id = UUID()
        var command: String
        var response: String
        var date: Date
    }
    var atLog: [ATLogEntry] = []

    /// 软件更新流程的当前状态。
    enum UpdatePhase {
        case idle
        case checking
        case found(AppUpdater.UpdateInfo)
        case downloading
        case downloaded(AppUpdater.UpdateInfo, URL)
        case installing
        case upToDate
        case failed(String)
    }
    var updatePhase: UpdatePhase = .idle

    private let session = ModemSession()
    private var detectionTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastCounters: (rx: UInt64, tx: UInt64, date: Date)?
    private var lastSMSPoll = Date.distantPast
    private var seenSMSIDs = Set<Int>()
    private var activeESIMChannel: UInt8?

    init() {
        manualPhoneNumber = UserDefaults.standard.string(forKey: "manualPhoneNumber") ?? ""
        showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
    }

    var isConnected: Bool {
        phase == .connected
    }

    /// 是否只检测到二代模块（无一代管理通道）。
    var isGen2Only: Bool {
        phase == .gen2Only
    }

    /// 页面展示的号码：优先模块读到的，其次手动填写的。
    var displayPhoneNumber: String {
        status.phoneNumber.isEmpty ? manualPhoneNumber : status.phoneNumber
    }

    /// 与模块网卡对应的系统网络服务（用于把默认出口切到模块）。
    var moduleService: NetworkServiceInfo? {
        if !network.activeInterface.isEmpty {
            if let match = networkServices.first(where: { $0.device == network.activeInterface }) {
                return match
            }
        }
        return networkServices.first { $0.port.lowercased().contains("baiwang") }
    }

    // MARK: - 生命周期

    func start() {
        guard detectionTask == nil else { return }
        requestNotificationPermission()
        startPathMonitor()
        detectionTask = Task { [weak self] in
            await self?.detectionLoop()
        }
    }

    // MARK: - 软件更新

    func checkForUpdates() async {
        updatePhase = .checking
        do {
            let releases = try await AppUpdater.fetchReleases()
            if let update = AppUpdater.pickUpdate(from: releases) {
                updatePhase = .found(update)
            } else {
                updatePhase = .upToDate
            }
        } catch {
            updatePhase = .failed("无法检查更新：\(error.localizedDescription)")
        }
    }

    func downloadUpdate(_ update: AppUpdater.UpdateInfo) async {
        updatePhase = .downloading
        do {
            let stagedApp = try await AppUpdater.prepareUpdate(update)
            updatePhase = .downloaded(update, stagedApp)
        } catch {
            updatePhase = .failed("下载失败：\(error.localizedDescription)")
        }
    }

    func installUpdate(_ update: AppUpdater.UpdateInfo, stagedApp: URL) {
        do {
            try AppUpdater.scheduleInstall(stagedApp: stagedApp)
            updatePhase = .installing
        } catch {
            updatePhase = .failed("安装失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 轮询

    private func detectionLoop() async {
        while !Task.isCancelled {
            let generations = LibusbTransport.presentGenerations()
            if generations.contains(.gen1) {
                detectedGeneration = .gen1
                if !session.isConnected {
                    await connect()
                }
                await refreshAll()
            } else if generations.contains(.gen2) {
                detectedGeneration = .gen2
                if session.isConnected {
                    await session.close()
                }
                if phase != .gen2Only {
                    phase = .gen2Only
                    status = ModuleStatus()
                    lastError = nil
                }
                refreshNetworkState()
            } else {
                detectedGeneration = nil
                if session.isConnected {
                    await session.close()
                }
                if phase != .searching {
                    phase = .searching
                    status = ModuleStatus()
                    network = NetworkSnapshot()
                    networkServices = []
                    lastCounters = nil
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func connect() async {
        do {
            try await session.connect(LibusbTransport())
            phase = .connected
        } catch {
            phase = .searching
        }
    }

    func refreshAll() async {
        guard isConnected else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            status = try await session.run { try ATClient.refreshStatus(transport: $0) }
            pdp = try await session.run { try ATClient.queryPDPStatus(transport: $0) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        refreshNetworkState()

        if autoPollSMS, Date().timeIntervalSince(lastSMSPoll) > 15 {
            lastSMSPoll = Date()
            await refreshSMS()
        }
    }

    /// 刷新模块网卡、系统网络服务与实时流量。
    private func refreshNetworkState() {
        network = NetworkMonitor.snapshot()
        networkServices = NetworkMonitor.services()
        updateSpeeds()
    }

    private func updateSpeeds() {
        guard !network.activeInterface.isEmpty,
              let counter = network.counters[network.activeInterface] else {
            currentSpeedDown = nil
            currentSpeedUp = nil
            return
        }
        let now = Date()
        if let last = lastCounters {
            let elapsed = now.timeIntervalSince(last.date)
            if elapsed > 0.5 {
                currentSpeedDown = Double(counter.rx - last.rx) / elapsed
                currentSpeedUp = Double(counter.tx - last.tx) / elapsed
            }
        }
        lastCounters = (counter.rx, counter.tx, now)
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let text: String
            switch path.status {
            case .satisfied: text = "已连接互联网"
            case .requiresConnection: text = "需要连接"
            case .unsatisfied: text = "无互联网"
            @unknown default: text = "未知"
            }
            Task { @MainActor [weak self] in
                self?.network.pathStatus = text
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.dji4gmanager.pathmonitor"))
        pathMonitor = monitor
    }

    // MARK: - 用户操作：模式与重启

    func setUSBNetMode(_ mode: Int) async {
        guard isConnected else { return }
        do {
            try await session.run { try ATClient.setUSBNetMode(transport: $0, mode: mode) }
            status.usbNetMode = mode
            phase = .switching
            await session.close()
            lastError = "已切换，模块正在重启并重新枚举 USB 接口…"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rebootModule() async {
        guard isConnected else { return }
        do {
            try await session.run { try ATClient.reboot(transport: $0) }
            phase = .switching
            await session.close()
            lastError = "模块已重启，等待重新连接…"
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 把系统默认出口切换到模块网卡（调整网络服务顺序，需要输入 Mac 密码授权）。
    func makeModuleDefaultRoute() async {
        networkServices = NetworkMonitor.services()
        guard let service = moduleService else {
            lastError = "没有找到模块对应的网络服务（Baiwang / \(network.activeInterface)），请先确认模块网卡已就绪。"
            return
        }
        do {
            try NetworkMonitor.setDefaultService(service.name, allServices: networkServices)
            lastError = "已把「\(service.name)」设为默认网络出口，正在生效…"
            network = NetworkMonitor.snapshot()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 短信

    func refreshSMS() async {
        guard isConnected else { return }
        do {
            let fresh = try await session.run { try ATClient.listSMS(transport: $0) }
            if notificationsEnabled {
                for message in fresh where message.isIncoming && !seenSMSIDs.contains(message.id) {
                    postNotification(title: "新短信", body: "\(message.phoneNumber)：\(message.text)")
                }
            }
            for message in fresh {
                seenSMSIDs.insert(message.id)
            }
            messages = fresh
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendSMS(to phoneNumber: String, text: String) async throws {
        guard isConnected else { throw ModemError.notOpen }
        try await session.run { try ATClient.sendSMS(transport: $0, to: phoneNumber, text: text) }
        await refreshSMS()
    }

    func deleteSMS(at index: Int) async {
        guard isConnected else { return }
        do {
            try await session.run { try ATClient.deleteSMS(transport: $0, index: index) }
            messages.removeAll { $0.id == index }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - eSIM

    func refreshESIM() async {
        guard isConnected else { return }
        esimBusy = true
        defer { esimBusy = false }
        var state = ESIMState()

        do {
            try await session.run { transport in
                for candidate in ATClient.euiccAIDs {
                    do {
                        let channel = try ATClient.openEUICCChannel(transport: transport, aid: candidate.aid)
                        defer { try? ATClient.closeEUICCChannel(transport: transport, channel: channel) }
                        if candidate.name == "ISD-R" {
                            state.eid = try ESIMProtocol.getEID(transport: transport, channel: channel)
                            state.profiles = try ESIMProtocol.getProfilesInfo(transport: transport, channel: channel)
                        }
                        state.detectedAID = candidate.name
                        break
                    } catch {
                        continue
                    }
                }
            }
            esim = state
        } catch {
            state.lastError = error.localizedDescription
            esim = state
        }
    }

    func enableProfile(iccid: String) async {
        await runProfileCommand("enable", iccid: iccid) { transport, channel in
            try ESIMProtocol.enableProfile(transport: transport, channel: channel, iccid: iccid)
        }
    }

    func disableProfile(iccid: String) async {
        await runProfileCommand("disable", iccid: iccid) { transport, channel in
            try ESIMProtocol.disableProfile(transport: transport, channel: channel, iccid: iccid)
        }
    }

    func deleteProfile(iccid: String) async {
        await runProfileCommand("delete", iccid: iccid) { transport, channel in
            try ESIMProtocol.deleteProfile(transport: transport, channel: channel, iccid: iccid)
        }
    }

    func renameProfile(iccid: String, nickname: String) async {
        await runProfileCommand("rename", iccid: iccid) { transport, channel in
            try ESIMProtocol.setNickname(transport: transport, channel: channel, iccid: iccid, nickname: nickname)
        }
    }

    private func runProfileCommand(
        _ operation: String,
        iccid: String,
        body: @escaping (any ModemTransport, UInt8) throws -> Void
    ) async {
        guard isConnected else { return }
        do {
            try await session.run { transport in
                guard let aid = ATClient.euiccAIDs.first(where: { $0.name == "ISD-R" })?.aid else { return }
                let channel = try ATClient.openEUICCChannel(transport: transport, aid: aid)
                defer { try? ATClient.closeEUICCChannel(transport: transport, channel: channel) }
                try body(transport, channel)
            }
            await refreshESIM()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - AT 透传

    func runAT(_ command: String) async -> String {
        guard isConnected else {
            let message = "模块未连接"
            atLog.append(ATLogEntry(command: command, response: message, date: Date()))
            return message
        }
        do {
            let response = try await session.run { try ATClient.execute(transport: $0, command: command) }
            atLog.append(ATLogEntry(command: command, response: response, date: Date()))
            return response
        } catch {
            atLog.append(ATLogEntry(command: command, response: error.localizedDescription, date: Date()))
            return error.localizedDescription
        }
    }

    // MARK: - 通知

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
