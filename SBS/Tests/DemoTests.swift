import XCTest
@testable import SBS

final class DemoTests: XCTestCase {
    func testDemoConnectsFourScalesAndEndsCleanly() {
        let scales = ScaleManager(defaults: UserDefaults(suiteName: #function)!)
        scales.startDemo()
        XCTAssertTrue(scales.isDemo)
        XCTAssertTrue(scales.canStart)
        XCTAssertEqual(Slot.allCases.map { scales.slots[$0]?.status }, Array(repeating: .connected, count: 4))
        scales.endDemo()
        XCTAssertFalse(scales.isDemo)
        XCTAssertFalse(scales.canStart)
    }

    func testOnlyHardwareTestedBrandsAreOutOfBeta() {
        XCTAssertEqual(ScaleDrivers.all.filter { !$0.isBeta }.map { $0.brand }, ["Bookoo"])
    }
}
