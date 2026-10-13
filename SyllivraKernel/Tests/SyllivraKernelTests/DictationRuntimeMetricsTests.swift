import XCTest
@testable import SyllivraKernel

final class DictationRuntimeMetricsTests: XCTestCase {
    func testOlderTimingRecordsWithoutContextRemainDeliverable() throws {
        let data = Data("{\"sessionID\":\"fixture\",\"stopUptimeNanoseconds\":1,\"stagesMs\":{\"published\":2}}".utf8)
        let metrics = try JSONDecoder().decode(DictationRuntimeMetrics.self, from: data)
        XCTAssertEqual(metrics.context, [:])
        XCTAssertEqual(metrics.stagesMs["published"], 2)
    }
    func testDurationsSurviveCrossProcessEncodingWithoutTranscriptText() throws {
        var app = DictationRuntimeMetrics(sessionID: "fixture", stopUptimeNanoseconds: 1_000_000)
        app.mark("cleanup", now: 3_500_000)
        let data = try JSONEncoder().encode(app)
        var keyboard = try JSONDecoder().decode(DictationRuntimeMetrics.self, from: data)
        keyboard.mark("proxyInserted", now: 5_000_000)
        XCTAssertEqual(keyboard.stagesMs["cleanup"], 2.5)
        XCTAssertEqual(keyboard.stagesMs["proxyInserted"], 4)
        keyboard.mark("invalidClock", now: 0)
        XCTAssertNil(keyboard.stagesMs["invalidClock"])
    }
}
