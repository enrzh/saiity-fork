import XCTest
@testable import SyllivraKernel

final class AudioCaptureBufferTests: XCTestCase {
    func testStopKeepsSamplesEvenWhenUIHasNotReceivedAnyUpdates() {
        let buffer = AudioCaptureBuffer()
        buffer.start(sessionID: 1)
        for number in 0..<20 {
            _ = buffer.capture { [Float(number)] }
        }
        XCTAssertEqual(buffer.stop(), (0..<20).map(Float.init))
        XCTAssertEqual(buffer.count, 0)
        XCTAssertNil(buffer.capture { XCTFail("Idle capture must not convert audio"); return [99] })
        XCTAssertEqual(buffer.stop(), [])
    }

    func testStopDrainsAnAdmittedCallbackBeforeTheNextSession() {
        let buffer = AudioCaptureBuffer()
        buffer.start(sessionID: 1)
        let entered = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        let captured = expectation(description: "callback completes")
        let stopped = expectation(description: "stop drains callback")
        DispatchQueue.global().async {
            _ = buffer.capture {
                entered.signal()
                XCTAssertEqual(finish.wait(timeout: .now() + 2), .success)
                return [1, 2, 3]
            }
            captured.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            XCTAssertEqual(buffer.stop(), [1, 2, 3])
            buffer.start(sessionID: 2)
            let next = buffer.capture { [4, 5] }
            XCTAssertEqual(next?.sessionID, 2)
            XCTAssertEqual(buffer.stop(), [4, 5])
            stopped.fulfill()
        }
        finish.signal()
        wait(for: [captured, stopped], timeout: 3)
    }

    func testFailedConversionDoesNotLosePreviousSamples() {
        let buffer = AudioCaptureBuffer()
        buffer.start(sessionID: 3)
        XCTAssertEqual(buffer.capture { [1, 2] }?.totalSampleCount, 2)
        XCTAssertNil(buffer.capture { nil })
        XCTAssertEqual(buffer.stop(), [1, 2])
    }
}
