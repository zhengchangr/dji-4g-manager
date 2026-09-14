import XCTest
@testable import DJI4GManager

final class ModuleGenerationTests: XCTestCase {

    func testProductIDsMatchDJIModules() {
        XCTAssertEqual(DJIModuleGeneration.gen1.productID, 0x4006)
        XCTAssertEqual(DJIModuleGeneration.gen2.productID, 0x4009)
        XCTAssertEqual(DJIModuleGeneration.allCases.count, 2)
    }

    func testDisplayTextShowsGenerationAndUSBIdentifier() {
        XCTAssertEqual(DJIModuleGeneration.gen1.displayName, "一代")
        XCTAssertEqual(DJIModuleGeneration.gen2.displayName, "二代")
        XCTAssertEqual(DJIModuleGeneration.gen1.usbID, "2ca3:4006")
        XCTAssertEqual(DJIModuleGeneration.gen2.usbID, "2ca3:4009")
        XCTAssertEqual(DJIModuleGeneration.gen1.detailText, "一代模块（2ca3:4006）")
        XCTAssertEqual(DJIModuleGeneration.gen2.detailText, "二代模块（2ca3:4009）")
    }
}
