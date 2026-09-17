import XCTest
@testable import DJI4GManager

final class ATClientTests: XCTestCase {

    func testRefreshStatusParsesDemoResponses() throws {
        let transport = DemoTransport()
        try transport.open()
        let status = try ATClient.refreshStatus(transport: transport)
        XCTAssertEqual(status.manufacturer, "Baiwang")
        XCTAssertEqual(status.model, "QDC507")
        XCTAssertEqual(status.revision, "QDC507GLEFM21")
        XCTAssertEqual(status.simState, "READY（已就绪）")
        XCTAssertEqual(status.signalLevel, 24)
        XCTAssertEqual(status.operatorName, "CHN-UNICOM")
        XCTAssertEqual(status.networkMode, "FDD LTE")
        XCTAssertEqual(status.band, "LTE BAND 3")
        XCTAssertEqual(status.usbNetMode, 0)
        XCTAssertEqual(status.phoneNumber, "+8613800138000")
        XCTAssertEqual(status.ipAddress, "192.168.225.1")
        XCTAssertEqual(status.imei, "861234567890123")
    }

    func testRefreshStatusParsesBareFirmwareAndIMEIWithEcho() throws {
        // 真机带命令回显，且 CGMR 直接回一行文本（无 +CGMR: 前缀）
        let transport = StaticTransport(responses: [
            "AT+CGMR": "AT+CGMR\r\r\nQDC507GLEFM21\r\nOK\r\n",
            "AT+CGSN": "AT+CGSN\r\r\n861234567890123\r\nOK\r\n",
        ])
        try transport.open()
        let status = try ATClient.refreshStatus(transport: transport)
        XCTAssertEqual(status.revision, "QDC507GLEFM21")
        XCTAssertEqual(status.imei, "861234567890123")
    }

    func testRefreshStatusParsesPrefixedCGSN() throws {
        // 部分固件 IMEI 带 +CGSN: 前缀
        let transport = StaticTransport(responses: [
            "AT+CGSN": "AT+CGSN\r\r\n+CGSN: \"861234567890123\"\r\nOK\r\n",
        ])
        try transport.open()
        let status = try ATClient.refreshStatus(transport: transport)
        XCTAssertEqual(status.imei, "861234567890123")
    }

    func testParseCNUMQuotedWithCRLF() {
        let response = "\r\n+CNUM: \"My Number\",\"+8613800138000\",145\r\n\r\nOK\r\n"
        let status = try! ATClient.refreshStatus(transport: StaticTransport(responses: ["AT+CNUM": response]))
        XCTAssertEqual(status.phoneNumber, "+8613800138000")
    }

    func testParseCNUMSkipsPlaceholderAndFindsRealNumber() {
        let response = "\r\n+CNUM: \"Own Number\",\"\",129\r\n+CNUM: \"Line 1\",\"+8613900139000\",145\r\n\r\nOK\r\n"
        let status = try! ATClient.refreshStatus(transport: StaticTransport(responses: ["AT+CNUM": response]))
        XCTAssertEqual(status.phoneNumber, "+8613900139000")
    }

    func testParseCNUMRejectsFFFFPlaceholder() {
        let response = "\r\n+CNUM: \"Own Number\",\"FFFFFFFF\",129\r\n\r\nOK\r\n"
        let status = try! ATClient.refreshStatus(transport: StaticTransport(responses: ["AT+CNUM": response]))
        XCTAssertEqual(status.phoneNumber, "")
    }

    func testParseCNUMEmptyWhenNoNumber() {
        let response = "\r\nOK\r\n"
        let status = try! ATClient.refreshStatus(transport: StaticTransport(responses: ["AT+CNUM": response]))
        XCTAssertEqual(status.phoneNumber, "")
    }

    func testPhoneNumberFallsBackToOwnNumberPhonebook() {
        // 运营商没把号码写进 CNUM 时，回退读取 SIM 卡“本机号码”电话簿。
        let transport = StaticTransport(responses: [
            "AT+CNUM": "\r\nOK\r\n",
            "AT+CPBS?": "\r\n+CPBS: \"SM\",1,250\r\nOK\r\n",
            "AT+CPBS=\"ON\"": "OK\r\n",
            "AT+CPBR=1,10": "\r\n+CPBR: 1,\"\",129,\"\"\r\n+CPBR: 2,\"+8613800138000\",145,\"\"\r\nOK\r\n",
            "AT+CPBS=\"SM\"": "OK\r\n",
        ])
        try! transport.open()
        let status = try! ATClient.refreshStatus(transport: transport)
        XCTAssertEqual(status.phoneNumber, "+8613800138000")
        XCTAssertEqual(status.phoneNumberSource, "SIM 卡本机号码（AT+CPBR）")
    }

    func testPhoneNumberPrefersCNUMOverPhonebook() {
        let transport = StaticTransport(responses: [
            "AT+CNUM": "\r\n+CNUM: \"Line 1\",\"+8613900139000\",145\r\nOK\r\n",
            "AT+CPBR=1,10": "\r\n+CPBR: 1,\"+8613800138000\",145,\"\"\r\nOK\r\n",
        ])
        let status = try! ATClient.refreshStatus(transport: transport)
        XCTAssertEqual(status.phoneNumber, "+8613900139000")
        XCTAssertEqual(status.phoneNumberSource, "AT+CNUM")
    }

    func testPhoneNumberEmptyWhenBothSourcesEmpty() {
        let transport = StaticTransport(responses: [
            "AT+CNUM": "\r\nOK\r\n",
            "AT+CPBR=1,10": "\r\n+CPBR: 1,\"FFFFFFFF\",129,\"\"\r\nOK\r\n",
        ])
        let status = try! ATClient.refreshStatus(transport: transport)
        XCTAssertEqual(status.phoneNumber, "")
        XCTAssertEqual(status.phoneNumberSource, "")
    }

    func testQueryPDPStatusParsesAPNContexts() throws {
        let transport = StaticTransport(responses: [
            "AT+CGDCONT?": "\r\n+CGDCONT: 1,\"IP\",\"cmnet\",\"0.0.0.0\",0,0\r\n+CGDCONT: 2,\"IP\",\"\",\"0.0.0.0\",0,0\r\nOK\r\n",
            "AT+CGACT?": "\r\n+CGACT: 1,1\r\n+CGACT: 2,0\r\nOK\r\n",
            "AT+CGPADDR=1": "\r\n+CGPADDR: 1,\"10.77.25.111\"\r\nOK\r\n",
        ])
        try transport.open()
        let pdp = try ATClient.queryPDPStatus(transport: transport)
        XCTAssertEqual(pdp.contexts.count, 2)
        XCTAssertEqual(pdp.contexts[0].apn, "cmnet")
        XCTAssertEqual(pdp.contexts[1].apn, "")
        XCTAssertEqual(pdp.activeIDs, [1])
        XCTAssertEqual(pdp.addresses[1], "10.77.25.111")
        XCTAssertTrue(pdp.hasDataSession)
    }

    func testQueryPDPStatusNoDataSession() throws {
        let transport = StaticTransport(responses: [
            "AT+CGDCONT?": "\r\n+CGDCONT: 1,\"IP\",\"\",\"0.0.0.0\",0,0\r\nOK\r\n",
            "AT+CGACT?": "\r\n+CGACT: 1,0\r\nOK\r\n",
            "AT+CGPADDR=1": "\r\n+CGPADDR: 1,\"0.0.0.0\"\r\nOK\r\n",
        ])
        try transport.open()
        let pdp = try ATClient.queryPDPStatus(transport: transport)
        XCTAssertFalse(pdp.hasDataSession)
        XCTAssertEqual(pdp.contexts.first?.apn, "")
        XCTAssertTrue(pdp.activeIDs.isEmpty)
    }

    func testESIMGetEIDThroughDemo() throws {
        let transport = DemoTransport()
        try transport.open()
        let channel = try ATClient.openEUICCChannel(transport: transport, aid: ATClient.euiccAIDs[0].aid)
        let eid = try ESIMProtocol.getEID(transport: transport, channel: channel)
        XCTAssertEqual(eid, "89049032123456789012345678901234")
    }

    func testESIMProfilesThroughDemo() throws {
        let transport = DemoTransport()
        try transport.open()
        let channel = try ATClient.openEUICCChannel(transport: transport, aid: ATClient.euiccAIDs[0].aid)
        let profiles = try ESIMProtocol.getProfilesInfo(transport: transport, channel: channel)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].iccid, "89860095020312345678")
        XCTAssertEqual(profiles[0].name, "中国联通")
        XCTAssertEqual(profiles[0].state, "enabled")
        XCTAssertEqual(profiles[1].iccid, "89860113911122334455")
        XCTAssertEqual(profiles[1].state, "disabled")
    }

    func testESIMEnableProfileThroughDemo() throws {
        let transport = DemoTransport()
        try transport.open()
        let channel = try ATClient.openEUICCChannel(transport: transport, aid: ATClient.euiccAIDs[0].aid)
        XCTAssertNoThrow(try ESIMProtocol.enableProfile(transport: transport, channel: channel, iccid: "89860113911122334455"))
    }
}
