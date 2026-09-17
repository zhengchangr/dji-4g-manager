import Foundation

/// 从模块读取到的状态快照。
struct ModuleStatus: Equatable {
    var isPresent = false
    var manufacturer = ""
    var model = ""
    var revision = ""
    var imei = ""
    var phoneNumber = ""
    /// 号码来源（AT+CNUM 或 SIM 卡本机号码电话簿）。
    var phoneNumberSource = ""
    var simState = "未知"
    var signalLevel = -1        // 0...31，-1 表示未知
    var operatorName = ""
    var networkMode = ""
    var band = ""
    var channel = ""
    var usbNetMode = -1         // 0...3，-1 表示未知
    var usbConfig = ""
    var ipAddress = ""
    var lastUpdated: Date?

    var signalPercent: Double {
        guard signalLevel >= 0 else { return 0 }
        return min(1.0, Double(signalLevel) / 31.0)
    }

    var signalDescription: String {
        guard signalLevel >= 0 else { return "未知" }
        return "\(signalLevel)/31 (\(-113 + signalLevel * 2) dBm)"
    }

    var usbNetModeDescription: String {
        switch usbNetMode {
        case 0: "短信 / 管理模式"
        case 1: "USB 上网模式"
        case 2: "实验模式 2"
        case 3: "实验模式 3"
        default: "未知"
        }
    }
}

/// 模块的 PDP 数据上下文（APN）。
struct PDPContextInfo: Identifiable, Equatable {
    let id: Int
    let pdn: String
    let apn: String
}

/// 数据连接状态快照：APN 上下文、激活状态与模块侧 IP。
struct PDPStatus: Equatable {
    var contexts: [PDPContextInfo] = []
    var activeIDs: Set<Int> = []
    var addresses: [Int: String] = [:]

    var hasDataSession: Bool {
        !addresses.values.allSatisfy { $0.isEmpty || $0 == "0.0.0.0" }
    }
}
