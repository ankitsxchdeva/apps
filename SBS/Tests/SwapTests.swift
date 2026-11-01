import XCTest
@testable import SBS

final class SwapTests: XCTestCase {
    func testSwapTradesScalesAndRemembersIt() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("11111111-1111-1111-1111-111111111111", forKey: "scale.a")
        defaults.set("Bookoo", forKey: "scale.a.brand")
        defaults.set("22222222-2222-2222-2222-222222222222", forKey: "scale.c")
        defaults.set("Acaia", forKey: "scale.c.brand")
        let scales = ScaleManager(defaults: defaults)
        scales.swap(.a, .c)
        XCTAssertEqual(defaults.string(forKey: "scale.a"), "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(defaults.string(forKey: "scale.a.brand"), "Acaia")
        XCTAssertEqual(defaults.string(forKey: "scale.c"), "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(defaults.string(forKey: "scale.c.brand"), "Bookoo")
    }

    func testSwapWithAnEmptySlotMovesTheScale() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("11111111-1111-1111-1111-111111111111", forKey: "scale.b")
        let scales = ScaleManager(defaults: defaults)
        scales.swap(.b, .d)
        XCTAssertNil(defaults.string(forKey: "scale.b"))
        XCTAssertEqual(defaults.string(forKey: "scale.d"), "11111111-1111-1111-1111-111111111111")
    }
}
