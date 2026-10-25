// Shows a 30-second countdown in Warble's notch, with a Pause button, prints what Warble sends back, and ends it.
//
// Turn on Settings › Activities in Warble, then run:
//
//     swift docs/examples/activity.swift
//
// Pass the bundle identifier to talk to a dev build: `swift docs/examples/activity.swift dev.lorcan.Warble.dev`.
// The protocol is in the guide, "Show an activity in the notch".

import Darwin
import Foundation

let bundleIdentifier = CommandLine.arguments.dropFirst().first ?? "dev.lorcan.Warble"
let socketPath = NSString(string: "~/Library/Application Support/\(bundleIdentifier)/activities.sock").expandingTildeInPath

// Connect. If nothing answers, Warble isn't running or Settings › Activities is off, and the app shows nothing.
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(socketPath.utf8)) }
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else {
    print("Warble isn't showing activities. Open it and turn on Settings › Activities.")
    exit(1)
}

/// Sends one JSON object as a line.
func send(_ message: [String: Any]) {
    var line = message
    line["v"] = 1
    let data = try! JSONSerialization.data(withJSONObject: line) + Data("\n".utf8)
    _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
}

var buffer = Data()

/// The next line Warble sent, waiting at most `seconds` for it, or `nil` if none came or the connection closed.
func nextLine(waiting seconds: Double) -> [String: Any]? {
    while true {
        if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex ..< newline]
            buffer.removeSubrange(buffer.startIndex ... newline)
            return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        }
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&poller, 1, Int32(max(seconds, 0) * 1000)) > 0 else { return nil }
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &chunk, chunk.count)
        guard count > 0 else { return nil }
        buffer.append(contentsOf: chunk[..<count])
    }
}

let pause = ["id": "pause", "label": "Pause", "symbol": "pause.fill"]
let resume = ["id": "resume", "label": "Resume", "symbol": "play.fill"]

// A signed app is named by its signature. A script names itself with `from`, shown as "Script: Countdown example".
var remaining = 30.0
send([
    "op": "start", "id": "countdown", "from": "Countdown example", "title": "30-second countdown",
    "detail": "From the example script", "icon": ["symbol": "timer", "tint": "orange"],
    "clock": ["until": Date().timeIntervalSince1970 + remaining], "buttons": [pause],
])

var deadline: Date? = Date().addingTimeInterval(remaining)
loop: while true {
    let wait = deadline.map { $0.timeIntervalSinceNow } ?? 3600
    guard let line = nextLine(waiting: wait) else {
        if let deadline, deadline.timeIntervalSinceNow <= 0 {
            // The countdown reached zero: the sender ends the activity, since Warble leaves a finished clock at 0:00.
            send(["op": "end", "id": "countdown"])
            print("Done.")
        } else {
            print("Warble closed the connection.")
        }
        break loop
    }
    print(line)
    switch (line["event"] as? String, line["button"] as? String) {
    case ("button", "pause"):
        remaining = deadline?.timeIntervalSinceNow ?? remaining
        deadline = nil
        // `null` clears the clock, so the wing shows the badge instead.
        send(["op": "update", "id": "countdown", "detail": "Paused", "clock": NSNull(), "badge": "Paused", "buttons": [resume]])
    case ("button", "resume"):
        deadline = Date().addingTimeInterval(remaining)
        send(["op": "update", "id": "countdown", "detail": "From the example script", "clock": ["until": Date().timeIntervalSince1970 + remaining], "badge": NSNull(), "buttons": [pause]])
    case ("ended", _):
        // The user closed it, or turned this app off in Settings.
        break loop
    default:
        break
    }
}
close(fd)
