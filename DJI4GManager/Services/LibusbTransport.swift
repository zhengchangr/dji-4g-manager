import Foundation
import CLibusb

/// 大疆 4G 模块代际（按 USB 产品 ID 区分）。
enum DJIModuleGeneration: Equatable, CaseIterable, Sendable {
    case gen1
    case gen2

    /// 一代 2ca3:4006；二代 2ca3:4009。
    var productID: UInt16 {
        switch self {
        case .gen1: return 0x4006
        case .gen2: return 0x4009
        }
    }

    var displayName: String {
        switch self {
        case .gen1: return "一代"
        case .gen2: return "二代"
        }
    }

    /// 形如 2ca3:4006 的 USB 标识，用于界面展示。
    var usbID: String {
        String(format: "2ca3:%04X", productID)
    }

    /// 形如“一代模块（2ca3:4006）”的完整说明。
    var detailText: String {
        "\(displayName)模块（\(usbID)）"
    }
}

/// 通过 libusb 与大疆一代 4G 模块（USB 2ca3:4006）通信。
/// 所有方法必须在同一条串行队列上调用（由 ModemSession 保证）。
final class LibusbTransport: ModemTransport {
    static let vendorID: UInt16 = 0x2CA3
    static let productID: UInt16 = 0x4006

    private var context: OpaquePointer?
    private var handle: OpaquePointer?
    private var claimedInterface: Int32 = -1
    private var endpointIn: UInt8 = 0
    private var endpointOut: UInt8 = 0
    private var openFlag = false

    var isOpen: Bool { openFlag }

    // MARK: - 设备检测

    static func isDevicePresent() -> Bool {
        presentGenerations().contains(.gen1)
    }

    /// 枚举当前插在 Mac 上的大疆 4G 模块代际。
    static func presentGenerations() -> Set<DJIModuleGeneration> {
        var context: OpaquePointer?
        guard libusb_init(&context) == 0, let context else { return [] }
        defer { libusb_exit(context) }

        var list: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(context, &list)
        guard count > 0, let list else { return [] }
        defer { libusb_free_device_list(list, 1) }

        var found: Set<DJIModuleGeneration> = []
        for index in 0 ..< Int(count) {
            guard let device = list[index] else { continue }
            let pointer = UnsafeMutablePointer<libusb_device_descriptor>.allocate(capacity: 1)
            memset(pointer, 0, MemoryLayout<libusb_device_descriptor>.size)
            defer { pointer.deallocate() }
            guard libusb_get_device_descriptor(device, pointer) == 0,
                  pointer.pointee.idVendor == vendorID else { continue }
            for generation in DJIModuleGeneration.allCases
            where generation.productID == pointer.pointee.idProduct {
                found.insert(generation)
            }
        }
        return found
    }

    // MARK: - ModemTransport

    func open() throws {
        guard !openFlag else { return }

        var context: OpaquePointer?
        guard libusb_init(&context) == 0, let context else {
            throw ModemError.usb("libusb 初始化失败")
        }
        self.context = context

        guard let handle = libusb_open_device_with_vid_pid(context, Self.vendorID, Self.productID) else {
            libusb_exit(context)
            self.context = nil
            throw ModemError.deviceNotFound
        }
        self.handle = handle

        do {
            let candidates = try findATCandidates()
            var lastError: Error = ModemError.interfaceNotFound
            for candidate in candidates {
                if probeCandidate(candidate) {
                    openFlag = true
                    return
                }
                lastError = ModemError.usb("AT 探测失败：接口 \(candidate.interfaceNumber)")
            }
            closeLocked()
            throw lastError
        } catch {
            closeLocked()
            throw error
        }
    }

    func close() {
        closeLocked()
    }

    func command(_ command: String, timeout: TimeInterval) throws -> String {
        try executeCommand(command, timeout: timeout, promptFollowUp: nil)
    }

    func commandWithPrompt(_ command: String, followUp: [UInt8], timeout: TimeInterval) throws -> String {
        try executeCommand(command, timeout: timeout, promptFollowUp: followUp)
    }

    // MARK: - 私有实现

    private func closeLocked() {
        if claimedInterface >= 0, let handle {
            libusb_release_interface(handle, claimedInterface)
            claimedInterface = -1
        }
        if let handle {
            libusb_close(handle)
            self.handle = nil
        }
        if let context {
            libusb_exit(context)
            self.context = nil
        }
        openFlag = false
        endpointIn = 0
        endpointOut = 0
    }

    private struct ATCandidate {
        let interfaceNumber: Int32
        let endpointOut: UInt8
        let endpointIn: UInt8
    }

    private func findATCandidates() throws -> [ATCandidate] {
        guard let handle, let device = libusb_get_device(handle) else {
            throw ModemError.usb("无法取得设备句柄")
        }
        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        let result = libusb_get_active_config_descriptor(device, &config)
        guard result == 0, let config else {
            throw ModemError.usb("读取配置描述符失败（\(result)）")
        }
        defer { libusb_free_config_descriptor(config) }

        let descriptor = config.pointee
        guard let interfaces = descriptor.interface else {
            throw ModemError.interfaceNotFound
        }

        var candidates: [ATCandidate] = []
        for interfaceIndex in 0 ..< Int(descriptor.bNumInterfaces) {
            let interface = interfaces[interfaceIndex]
            guard let altsettings = interface.altsetting else { continue }
            for altIndex in 0 ..< Int(interface.num_altsetting) {
                let alt = altsettings[altIndex]
                guard let endpoints = alt.endpoint else { continue }
                var endpointIn: UInt8 = 0
                var endpointOut: UInt8 = 0
                for endpointIndex in 0 ..< Int(alt.bNumEndpoints) {
                    let endpoint = endpoints[endpointIndex]
                    guard endpoint.bmAttributes & 0x03 == 0x02 else { continue } // bulk
                    if endpoint.bEndpointAddress & 0x80 != 0 {
                        endpointIn = endpoint.bEndpointAddress
                    } else {
                        endpointOut = endpoint.bEndpointAddress
                    }
                }
                if endpointIn != 0 && endpointOut != 0 {
                    candidates.append(ATCandidate(
                        interfaceNumber: Int32(alt.bInterfaceNumber),
                        endpointOut: endpointOut,
                        endpointIn: endpointIn
                    ))
                }
            }
        }
        if candidates.isEmpty {
            throw ModemError.interfaceNotFound
        }
        return candidates
    }

    private func probeCandidate(_ candidate: ATCandidate) -> Bool {
        guard let handle else { return false }
        guard libusb_claim_interface(handle, candidate.interfaceNumber) == 0 else { return false }
        drain(endpointIn: candidate.endpointIn)
        do {
            let response = try bulkExchange(
                "AT",
                endpointOut: candidate.endpointOut,
                endpointIn: candidate.endpointIn,
                timeout: 0.9
            )
            if response.contains("OK") {
                claimedInterface = candidate.interfaceNumber
                endpointOut = candidate.endpointOut
                endpointIn = candidate.endpointIn
                return true
            }
        } catch {
            // 继续尝试下一个候选接口
        }
        libusb_release_interface(handle, candidate.interfaceNumber)
        return false
    }

    private func executeCommand(
        _ command: String,
        timeout: TimeInterval,
        promptFollowUp: [UInt8]?
    ) throws -> String {
        guard openFlag else { throw ModemError.notOpen }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ModemError.commandFailed("指令为空") }

        drain(endpointIn: endpointIn)
        try bulkWrite(Array((trimmed + "\r").utf8), endpoint: endpointOut, timeout: timeout)

        let deadline = Date().addingTimeInterval(timeout)
        var chunks = Data()
        var followUpSent = false

        while Date() < deadline {
            let remaining = min(0.9, max(0.05, deadline.timeIntervalSinceNow))
            let data = try bulkRead(endpointIn: endpointIn, timeout: remaining)
            if !data.isEmpty {
                chunks.append(data)
            }

            if let followUp = promptFollowUp, !followUpSent,
               responseHasPrompt(chunks) {
                followUpSent = true
                try bulkWrite(followUp, endpoint: endpointOut, timeout: 2)
            }

            let text = String(decoding: chunks, as: UTF8.self)
            if responseCompleted(text) {
                return normalizedResponse(text)
            }
        }

        if chunks.isEmpty {
            throw ModemError.timeout
        }
        return normalizedResponse(String(decoding: chunks, as: UTF8.self))
    }

    /// 判断模块是否已给出 AT 输入提示符 `>`（最后非空白字符）。
    private func responseHasPrompt(_ chunks: Data) -> Bool {
        let text = String(decoding: chunks, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(">")
    }

    /// 判断 AT 响应是否已完整结束（收到 OK / ERROR / +CME ERROR / +CMS ERROR）。
    /// 注意：不能只看到 "+CMGS:" 就提前返回，必须等最终 OK，否则会漏掉结果。
    private func responseCompleted(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "OK" || trimmed.hasSuffix("\nOK") || normalized.contains("\nOK\n") {
            return true
        }
        if trimmed == "ERROR" || trimmed.hasSuffix("\nERROR") || normalized.contains("\nERROR\n") {
            return true
        }
        let upper = normalized.uppercased()
        return upper.contains("+CME ERROR:") || upper.contains("+CMS ERROR:")
    }

    private func bulkWrite(_ bytes: [UInt8], endpoint: UInt8, timeout: TimeInterval) throws {
        guard let handle else { throw ModemError.notOpen }
        var transferred: Int32 = 0
        let result = bytes.withUnsafeBytes { buffer -> Int32 in
            libusb_bulk_transfer(
                handle,
                endpoint,
                UnsafeMutablePointer(mutating: buffer.bindMemory(to: UInt8.self).baseAddress),
                Int32(bytes.count),
                &transferred,
                UInt32(timeout * 1000)
            )
        }
        guard result == 0 else {
            if Self.isFatalUSBError(result) {
                closeLocked()
            }
            throw ModemError.usb("写入失败（\(result)）")
        }
    }

    private func bulkRead(endpointIn: UInt8, timeout: TimeInterval) throws -> Data {
        guard let handle else { throw ModemError.notOpen }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bufferLength = Int32(buffer.count)
        var transferred: Int32 = 0
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            libusb_bulk_transfer(
                handle,
                endpointIn,
                raw.bindMemory(to: UInt8.self).baseAddress,
                bufferLength,
                &transferred,
                UInt32(timeout * 1000)
            )
        }
        if result == -7 { // LIBUSB_ERROR_TIMEOUT
            return Data()
        }
        guard result == 0 else {
            if Self.isFatalUSBError(result) {
                closeLocked()
            }
            throw ModemError.usb("读取失败（\(result)）")
        }
        return Data(buffer[0 ..< Int(transferred)])
    }

    /// libusb 中表示设备已断开 / 句柄失效的错误码：
    /// -1 IO、-4 NO_DEVICE、-5 NOT_FOUND。遇到这些错误时关闭传输通道，
    /// 让上层轮询逻辑重新打开设备，而不是一直卡在失效句柄上。
    private static func isFatalUSBError(_ result: Int32) -> Bool {
        result == -1 || result == -4 || result == -5
    }

    private func bulkExchange(_ command: String, endpointOut: UInt8, endpointIn: UInt8, timeout: TimeInterval) throws -> String {
        try bulkWrite(Array((command + "\r").utf8), endpoint: endpointOut, timeout: timeout)
        let deadline = Date().addingTimeInterval(timeout)
        var chunks = Data()
        while Date() < deadline {
            let remaining = min(0.9, max(0.05, deadline.timeIntervalSinceNow))
            let data = try bulkRead(endpointIn: endpointIn, timeout: remaining)
            if !data.isEmpty {
                chunks.append(data)
                let text = String(decoding: chunks, as: UTF8.self)
                if text.contains("\r\nOK\r\n") || text.contains("\r\nERROR\r\n") {
                    return text
                }
            }
        }
        return String(decoding: chunks, as: UTF8.self)
    }

    private func drain(endpointIn: UInt8) {
        guard let handle else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bufferLength = Int32(buffer.count)
        var transferred: Int32 = 0
        while true {
            let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
                libusb_bulk_transfer(
                    handle,
                    endpointIn,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    bufferLength,
                    &transferred,
                    50
                )
            }
            if result != 0 || transferred == 0 { break }
        }
    }

    private func normalizedResponse(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
