// Compile with the production DarwinNotifications.swift; runs only synthetic Mac process handoffs.
import Darwin
import Foundation

@main
enum DarwinHandoffProbe {
    static let fixture = "Syllivra synthetic handoff: Grüße, 中文, 🙂."

    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 4, arguments[1] == "listen" {
            let name = arguments[2] as CFString
            let payload = URL(fileURLWithPath: arguments[3])
            DarwinNotificationCenter.addObserver(for: name) {
                let received = (try? String(contentsOf: payload, encoding: .utf8)) == fixture
                FileHandle.standardOutput.write(Data((received ? "ACK\n" : "BAD PAYLOAD\n").utf8))
            }
            FileHandle.standardOutput.write(Data("READY\n".utf8))
            RunLoop.current.run(until: Date().addingTimeInterval(6))
            DarwinNotificationCenter.removeAllObservers()
            return
        }

        guard let scratch = ProcessInfo.processInfo.environment["CODEX_TASK_TMP"] else {
            fatalError("Run through codex-task so synthetic payloads stay in task scratch")
        }
        let payload = URL(fileURLWithPath: scratch).appendingPathComponent("handoff.txt")
        try fixture.write(to: payload, atomically: true, encoding: .utf8)
        let name = "de.aiity.saiity.tests.handoff.\(UUID().uuidString)"
        let child = Process(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: arguments[0])
        child.arguments = ["listen", name, payload.path]
        child.standardOutput = output
        child.standardError = FileHandle.standardError
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        precondition(read(output.fileHandleForReading) == "READY", "The observer process did not register")
        DarwinNotificationCenter.post(name as CFString)
        precondition(read(output.fileHandleForReading) == "ACK", "Cross-process signal/payload mismatch")
        child.waitUntilExit()
        precondition(child.terminationStatus == 0, "The observer process failed")
        print("PASS: production Darwin signal crossed Mac processes; the independent reader received the exact synthetic Unicode payload")
    }

    private static func read(_ handle: FileHandle) -> String {
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        precondition(poll(&descriptor, 1, 5_000) > 0, "Timed out waiting for the observer process")
        return String(decoding: handle.availableData, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
