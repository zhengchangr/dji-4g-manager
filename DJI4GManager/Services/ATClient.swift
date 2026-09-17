import Foundation

/// 大疆一代 4G 模块的 AT 指令层：状态、模式切换、短信与 eSIM 基础能力。
enum ATClient {

    // MARK: - 状态

    static func refreshStatus(transport: any ModemTransport) throws -> ModuleStatus {
        var status = ModuleStatus()
        status.isPresent = true
        status.manufacturer = query(transport, "AT+CGMI", prefix: "+CGMI:")
        status.model = query(transport, "AT+CGMM", prefix: "+CGMM:")
        status.revision = parseFirmware(queryRaw(transport, "AT+CGMR"))
        status.imei = firstDigitsLine(queryRaw(transport, "AT+CGSN"))
        let phone = readPhoneNumber(transport)
        status.phoneNumber = phone.number
        status.phoneNumberSource = phone.source
        status.simState = parseSIMState(query(transport, "AT+CPIN?", prefix: "+CPIN:"))
        status.signalLevel = parseCSQ(query(transport, "AT+CSQ", prefix: "+CSQ:"))
        status.operatorName = parseOperator(query(transport, "AT+COPS?", prefix: "+COPS:"))
        parseQNWInfo(query(transport, "AT+QNWINFO", prefix: "+QNWINFO:"), into: &status)
        status.usbNetMode = parseUSBNetMode(query(transport, "AT+QCFG=\"usbnet\"", prefix: "+QCFG:"))
        status.usbConfig = value(after: "+QCFG:", in: queryRaw(transport, "AT+QCFG=\"usbcfg\""))
        status.ipAddress = parseIPAddress(query(transport, "AT+CGPADDR=1", prefix: "+CGPADDR:"))
        status.lastUpdated = Date()
        return status
    }

    // MARK: - 模式切换

    static func setUSBNetMode(transport: any ModemTransport, mode: Int) throws {
        guard (0 ... 3).contains(mode) else {
            throw ModemError.commandFailed("模式必须是 0...3")
        }
        let response = try transport.command("AT+QCFG=\"usbnet\",\(mode)", timeout: 5)
        guard response.contains("OK") else {
            throw ModemError.commandFailed(response)
        }
    }

    static func reboot(transport: any ModemTransport) throws {
        _ = try? transport.command("AT+CFUN=1,1", timeout: 3)
    }

    // MARK: - 短信

    static func listSMS(transport: any ModemTransport) throws -> [SMSMessage] {
        let mode = try transport.command("AT+CMGF=0", timeout: 3)
        guard mode.contains("OK") else {
            throw ModemError.commandFailed("切换到 PDU 短信模式失败：\(mode)")
        }
        let response = try transport.command("AT+CMGL=4", timeout: 15)
        return SMSCodec.parseCMGL(response)
    }

    static func sendSMS(transport: any ModemTransport, to phoneNumber: String, text: String) throws {
        let mode = try transport.command("AT+CMGF=0", timeout: 3)
        guard mode.contains("OK") else {
            throw ModemError.commandFailed("切换到 PDU 短信模式失败：\(mode)")
        }
        let pdu = try SMSCodec.buildSubmitPDU(to: phoneNumber, text: text)
        // PDU 模式下 CMGS 的数据阶段要发送“大写十六进制文本 + Ctrl-Z”，
        // 而不是原始二进制字节。
        let hexPdu = SMSCodec.bytesToHex(pdu.data)
        let followUp = Array(hexPdu.utf8) + [0x1A]
        let response = try transport.commandWithPrompt(
            "AT+CMGS=\(pdu.lengthOctets)",
            followUp: followUp,
            timeout: 45
        )
        guard response.contains("+CMGS:") && response.contains("OK") else {
            throw ModemError.commandFailed(response)
        }
    }

    static func deleteSMS(transport: any ModemTransport, index: Int) throws {
        let response = try transport.command("AT+CMGD=\(index)", timeout: 3)
        guard response.contains("OK") else { throw ModemError.commandFailed(response) }
    }

    // MARK: - 数据连接（PDP / APN）

    /// 查询数据连接状态：APN 上下文、激活状态与模块侧 IP。
    static func queryPDPStatus(transport: any ModemTransport) throws -> PDPStatus {
        var status = PDPStatus()
        if let contexts = try? transport.command("AT+CGDCONT?", timeout: 3) {
            status.contexts = parseCGDCONT(contexts)
        }
        if let active = try? transport.command("AT+CGACT?", timeout: 3) {
            status.activeIDs = parseCGACT(active)
        }
        if let addresses = try? transport.command("AT+CGPADDR=1", timeout: 3) {
            status.addresses = parseCGPADDR(addresses)
        }
        return status
    }

    private static func parseCGDCONT(_ response: String) -> [PDPContextInfo] {
        let pattern = #"\+CGDCONT:\s*(\d+),"([^"]*)","([^"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(response.startIndex..., in: response)
        var result: [PDPContextInfo] = []
        for match in regex.matches(in: response, range: range) {
            guard let idRange = Range(match.range(at: 1), in: response),
                  let pdnRange = Range(match.range(at: 2), in: response),
                  let apnRange = Range(match.range(at: 3), in: response),
                  let id = Int(response[idRange]) else { continue }
            result.append(PDPContextInfo(
                id: id,
                pdn: String(response[pdnRange]),
                apn: String(response[apnRange])
            ))
        }
        return result
    }

    private static func parseCGACT(_ response: String) -> Set<Int> {
        var active = Set<Int>()
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed
                .replacingOccurrences(of: "+CGACT:", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, let id = Int(parts[0]), parts[1] == "1" {
                active.insert(id)
            }
        }
        return active
    }

    private static func parseCGPADDR(_ response: String) -> [Int: String] {
        var addresses: [Int: String] = [:]
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed
                .replacingOccurrences(of: "+CGPADDR:", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2, let id = Int(parts[0]) {
                addresses[id] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return addresses
    }

    // MARK: - eSIM（实验性）

    static let euiccAIDs: [(name: String, aid: [UInt8])] = [
        ("ISD-R", [0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x89, 0x00, 0x00, 0x01, 0x00]),
        ("ECASD", [0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x89, 0x00, 0x00, 0x02, 0x00]),
        ("eSIM.me", [0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0x00, 0x00, 0x00, 0x00, 0x89, 0x00, 0x00, 0x03, 0x00]),
        ("5ber", [0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x89, 0x00, 0x05, 0x05, 0x00]),
    ]

    static func openEUICCChannel(transport: any ModemTransport, aid: [UInt8]) throws -> UInt8 {
        let aidHex = SMSCodec.bytesToHex(aid)
        let response = try transport.command("AT+CCHO=\"\(aidHex)\"", timeout: 8)
        guard let match = response.firstMatch(of: #"\+CCHO:\s*(\d+)"#) else {
            throw ModemError.commandFailed(response)
        }
        guard let channel = UInt8(match) else {
            throw ModemError.commandFailed("无法解析通道号：\(response)")
        }
        return channel
    }

    static func transmitAPDU(transport: any ModemTransport, channel: UInt8, apdu: [UInt8]) throws -> [UInt8] {
        let apduHex = SMSCodec.bytesToHex(apdu)
        let response = try transport.command("AT+CGLA=\(channel),\(apduHex.count),\"\(apduHex)\"", timeout: 15)
        guard let hex = response.firstMatch(of: ##"\+CGLA:\s*\d+\s*,\s*"?([0-9A-Fa-f]+)"?"##) else {
            throw ModemError.commandFailed(response)
        }
        return SMSCodec.hexToBytes(hex)
    }

    static func closeEUICCChannel(transport: any ModemTransport, channel: UInt8) throws {
        _ = try? transport.command("AT+CCHC=\(channel)", timeout: 5)
    }

    /// 读取 eUICC 的 EID（SGP.22 GetEID，需先打开 ECASD 通道）。
    static func readEID(transport: any ModemTransport, channel: UInt8) throws -> String {
        try ESIMProtocol.getEID(transport: transport, channel: channel)
    }

    // MARK: - AT 透传

    static func execute(transport: any ModemTransport, command: String) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("AT") else {
            throw ModemError.commandFailed("指令必须以 AT 开头")
        }
        return try transport.command(trimmed, timeout: 15)
    }

    // MARK: - 解析工具

    private static func query(_ transport: any ModemTransport, _ command: String, prefix: String) -> String {
        guard let response = try? transport.command(command, timeout: 3) else { return "" }
        return value(after: prefix, in: response)
    }

    private static func queryRaw(_ transport: any ModemTransport, _ command: String) -> String {
        (try? transport.command(command, timeout: 3)) ?? ""
    }

    private static func value(after prefix: String, in response: String) -> String {
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix(prefix) {
                return trimmed
                    .replacingOccurrences(of: prefix, with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func firstDigitsLine(_ response: String) -> String {
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let digits = trimmed.filter { $0.isNumber }
            if digits.count >= 15 { return String(digits) }
        }
        return ""
    }

    /// 解析固件版本：优先标准 `+CGMR:` 前缀格式；
    /// 该模块固件也可能不带前缀直接回一行文本（如 QDC507GLEFM21）。
    private static func parseFirmware(_ response: String) -> String {
        let prefixed = value(after: "+CGMR:", in: response)
        if !prefixed.isEmpty { return prefixed }
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("AT") || upper == "OK" || upper == "ERROR" || trimmed.hasPrefix("+") {
                continue
            }
            return trimmed
        }
        return ""
    }

    private static func parseSIMState(_ value: String) -> String {
        switch value.uppercased() {
        case "READY": "READY（已就绪）"
        case "SIM PIN": "需要 PIN"
        case "SIM PUK": "需要 PUK"
        case "NOT INSERTED": "未插卡"
        case "SIM ERROR", "ERROR": "SIM 错误"
        default: value.isEmpty ? "未知" : value
        }
    }

    private static func parseCSQ(_ value: String) -> Int {
        let parts = value.split(separator: ",")
        guard let first = parts.first, let level = Int(first.trimmingCharacters(in: .whitespaces)) else {
            return -1
        }
        return level == 99 ? -1 : level
    }

    private static func parseOperator(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let firstQuote = trimmed.firstIndex(of: "\"") else { return trimmed }
        let rest = trimmed[trimmed.index(after: firstQuote)...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<endQuote])
    }

    private static func parseQNWInfo(_ value: String, into status: inout ModuleStatus) {
        let pattern = #"\"([^\"]+)\",\"([^\"]*)\",\"([^\"]*)\",(\d+)"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return }
        let matched = String(value[range])
        let parts = matched.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        guard parts.count >= 4 else { return }
        status.networkMode = parts[0]
        status.band = parts[2]
        status.channel = parts[3]
    }

    private static func parseUSBNetMode(_ value: String) -> Int {
        guard let last = value.split(separator: ",").last,
              let mode = Int(last.trimmingCharacters(in: .whitespaces)) else {
            return -1
        }
        return mode
    }

    /// 读取本机号码：优先 `AT+CNUM`，它直接返回 SIM 卡登记的本机号码；
    /// 但很多运营商没有把号码写进 SIM，此时回退读取 SIM 卡的
    /// “本机号码”电话簿（EF_MSISDN，电话簿名 `ON`）。
    private static func readPhoneNumber(_ transport: any ModemTransport) -> (number: String, source: String) {
        let cnum = parseCNUM(queryRaw(transport, "AT+CNUM"))
        if !cnum.isEmpty {
            return (cnum, "AT+CNUM")
        }

        let previousStorage = parseCPBSStorage(queryRaw(transport, "AT+CPBS?"))
        _ = queryRaw(transport, "AT+CPBS=\"ON\"")
        let numbers = parseCPBR(queryRaw(transport, "AT+CPBR=1,10"))
        let restoreStorage = (previousStorage?.isEmpty == false ? previousStorage : nil) ?? "SM"
        if restoreStorage != "ON" {
            _ = queryRaw(transport, "AT+CPBS=\"\(restoreStorage)\"")
        }
        if let first = numbers.first {
            return (first, "SIM 卡本机号码（AT+CPBR）")
        }
        return ("", "")
    }

    /// 解析 `AT+CPBS?` 当前电话簿名，例如 `+CPBS: "SM",1,250` → `SM`。
    private static func parseCPBSStorage(_ response: String) -> String? {
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("+CPBS:") else { continue }
            return extractQuotedFields(trimmed).first(where: { !$0.isEmpty })
        }
        return nil
    }

    /// 解析 `AT+CPBR` 返回的本机号码列表。
    private static func parseCPBR(_ response: String) -> [String] {
        var numbers: [String] = []
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("+CPBR:") else { continue }
            for field in extractQuotedFields(trimmed) {
                if let number = canonicalPhoneCandidate(field) {
                    numbers.append(number)
                    break
                }
            }
        }
        return numbers
    }

    /// 解析 AT+CNUM 响应，提取第一个有效本机号码。
    /// 真机可能返回多行 +CNUM、带标签引号字段，或占位值（FFFFFFFF / 全零 / Own Number）。
    private static func parseCNUM(_ response: String) -> String {
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("+CNUM:") else { continue }
            let payload = trimmed.replacingOccurrences(of: "+CNUM:", with: "")
            for field in extractQuotedFields(payload) {
                if let number = canonicalPhoneCandidate(field) {
                    return number
                }
            }
        }
        return ""
    }

    private static func extractQuotedFields(_ text: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuote = false
        for char in text {
            if char == "\"" {
                if inQuote {
                    fields.append(current)
                    current = ""
                }
                inQuote.toggle()
            } else if inQuote {
                current.append(char)
            }
        }
        return fields
    }

    private static func canonicalPhoneCandidate(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespaces)
        if candidate.isEmpty { return nil }
        let upper = candidate.uppercased()
        if upper == "FFFFFFFF" || upper == "00000000000" || upper == "OWN NUMBER" {
            return nil
        }
        if upper.hasPrefix("TEL:") {
            candidate = String(candidate.dropFirst(4))
        }
        candidate = candidate
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let digits = candidate.filter { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        return candidate
    }

    private static func parseIPAddress(_ value: String) -> String {
        for part in value.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(".") { return trimmed }
        }
        return ""
    }
}

private extension String {
    func firstMatch(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let textRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[textRange])
    }
}
