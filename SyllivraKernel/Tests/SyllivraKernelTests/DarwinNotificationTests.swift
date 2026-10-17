import CoreFoundation
import XCTest
@testable import SyllivraKernel

final class DarwinNotificationTests: XCTestCase {
    private func channel() -> CFString {
        "de.aiity.saiity.tests.\(UUID().uuidString)" as CFString
    }

    func testNativeDarwinPostsReachEverySubscriber() async {
        let name = channel()
        let first = expectation(description: "first subscriber")
        let second = expectation(description: "second subscriber")
        DarwinNotificationCenter.addObserver(for: name) { first.fulfill() }
        DarwinNotificationCenter.addObserver(for: name) { second.fulfill() }
        defer {
            DarwinNotificationCenter.removeObserver(for: name)
            DarwinNotificationCenter.removeObserver(for: name)
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
        await fulfillment(of: [first, second], timeout: 2)
    }

    func testRemovingOneSubscriberKeepsTheRemainingSubscriber() async {
        let name = channel()
        let removed = expectation(description: "removed subscriber")
        removed.isInverted = true
        let retained = expectation(description: "retained subscriber")
        DarwinNotificationCenter.addObserver(for: name) { removed.fulfill() }
        DarwinNotificationCenter.addObserver(for: name) { retained.fulfill() }
        DarwinNotificationCenter.removeObserver(for: name)
        defer { DarwinNotificationCenter.removeObserver(for: name) }
        DarwinNotificationCenter.post(name)
        await fulfillment(of: [removed, retained], timeout: 0.3)
    }

    func testAChannelCanBeRegisteredAgainAfterItsLastSubscriberLeaves() async {
        let name = channel()
        let old = expectation(description: "old subscription")
        old.isInverted = true
        DarwinNotificationCenter.addObserver(for: name) { old.fulfill() }
        DarwinNotificationCenter.removeObserver(for: name)
        let replacement = expectation(description: "new subscription")
        DarwinNotificationCenter.addObserver(for: name) { replacement.fulfill() }
        defer { DarwinNotificationCenter.removeObserver(for: name) }
        DarwinNotificationCenter.post(name)
        await fulfillment(of: [old, replacement], timeout: 0.3)
    }

    func testRemovingAnUnknownChannelDoesNotAffectAnotherChannel() async {
        let name = channel()
        let delivered = expectation(description: "independent channel")
        DarwinNotificationCenter.addObserver(for: name) { delivered.fulfill() }
        defer { DarwinNotificationCenter.removeObserver(for: name) }
        DarwinNotificationCenter.removeObserver(for: channel())
        DarwinNotificationCenter.post(name)
        await fulfillment(of: [delivered], timeout: 2)
    }

    func testASecondOwnerCanLeaveWithoutRemovingTheFirstOwnersListener() async {
        let name = channel()
        let retained = expectation(description: "earlier owner")
        let removed = expectation(description: "departed owner")
        removed.isInverted = true
        let first = DarwinNotificationCenter.addObserver(for: name) { retained.fulfill() }
        let second = DarwinNotificationCenter.addObserver(for: name) { removed.fulfill() }
        DarwinNotificationCenter.removeObserver(for: name, token: second)
        defer { DarwinNotificationCenter.removeObserver(for: name, token: first) }
        DarwinNotificationCenter.post(name)
        await fulfillment(of: [retained, removed], timeout: 0.3)
    }
}
