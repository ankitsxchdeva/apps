import XCTest
@testable import SBS

final class LabelTests: XCTestCase {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testLabelsAreRememberedAndMoveWithASwap() {
        let defaults = freshDefaults(#function)
        let scales = ScaleManager(defaults: defaults)
        scales.setLabel("V60", for: .a)
        scales.setLabel("Origami", for: .b)
        scales.swap(.a, .b)
        XCTAssertEqual(scales.labels[.a], "Origami")
        XCTAssertEqual(ScaleManager(defaults: defaults).labels[.b], "V60")
        scales.setLabel("  ", for: .a)
        XCTAssertNil(scales.labels[.a])
    }

    func testRunKeepsTheLabelsItStartedWith() throws {
        let scales = ScaleManager(defaults: freshDefaults(#function))
        scales.setLabel("V60", for: .a)
        let recorder = Recorder(scales: scales)
        recorder.start()
        scales.setLabel("Changed", for: .a)
        recorder.ingest(ScaleReading(grams: 2, flow: 0, battery: nil, timer: 0.2), from: .a, at: .now.addingTimeInterval(1))
        let run = try XCTUnwrap(recorder.stop())
        XCTAssertEqual(run.labels, [.a: "V60"])
        XCTAssertEqual(run.seriesName(.a), "A · V60")
        XCTAssertEqual(run.seriesName(.b), "B")
    }

    func testLabelsRoundTripAndOldRunsHaveNone() throws {
        let run = Run(date: .now, labels: [.b: "Origami"])
        let decoded = try JSONDecoder().decode(Run.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded.labels, [.b: "Origami"])
        let old = #"{"id":"6B1C1A2E-3D4F-4A5B-8C6D-7E8F9A0B1C2D","date":0,"note":"","a":[],"b":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(Run.self, from: Data(old.utf8)).labels, [:])
    }

    func testCSVCarriesQuotedLabels() {
        let run = Run(date: .now, labels: [.a: #"Kalita "155", 4:6"#],
                      a: [Sample(t: 0, grams: 0, flow: 0)], b: [Sample(t: 0.1, grams: 1.25, flow: 2)])
        XCTAssertEqual(run.csv, """
            scale,label,time_s,grams,flow_g_per_s
            A,"Kalita ""155"", 4:6",0.000,0.00,0.00
            B,,0.100,1.25,2.00

            """)
    }
}
