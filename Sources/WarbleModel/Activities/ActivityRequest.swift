import Foundation

/// Why a line from an app wasn't taken, as a sentence for the developer, with no code.
public struct ActivityError: Error, Equatable, Sendable {
    public var message: String
    /// The `op` the line asked for, when it got far enough to say, so the reply names it.
    public var operation: String?

    public init(_ message: String, operation: String? = nil) {
        self.message = message
        self.operation = operation
    }
}

/// The fields of a `start`, checked against the limits but not yet tied to a sender.
public struct ActivityDraft: Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String?
    public var badge: String?
    public var icon: ActivityIcon?
    public var clock: ActivityClock?
    public var buttons: [ActivityButton] = []
    public var priority: ActivityPriority = .normal
    /// Seconds from the start until Warble ends the activity itself.
    public var lasts: TimeInterval = ActivityLimits.defaultLasts
    /// For a script only: the name it shows under.
    public var from: String?
}

/// One line from an app, parsed and checked against every limit that needs no state. Here, with no socket, so every
/// message in the protocol is tested on Linux.
public struct ActivityRequest: Equatable, Sendable {
    public static let version = 1

    public enum Operation: Equatable, Sendable {
        case start(ActivityDraft)
        case update(id: String, ActivityPatch)
        case end(id: String)
    }

    public var operation: Operation

    /// The `op` the line asked for, which the reply repeats as `re`.
    public var name: String {
        switch operation {
        case .start: "start"
        case .update: "update"
        case .end: "end"
        }
    }

    public var id: String {
        switch operation {
        case .start(let draft): draft.id
        case .update(let id, _), .end(let id): id
        }
    }

    /// The request in `line`, or the error naming the first limit it breaks. `isScript` is whether the sender is a script,
    /// whose `start` must name itself with `from`, which a signed app's is ignored.
    public static func decode(_ line: Data, isScript: Bool) throws(ActivityError) -> ActivityRequest {
        guard line.count <= ActivityLimits.lineBytes else {
            throw ActivityError("the line is \(line.count) bytes; the most is \(ActivityLimits.lineBytes)")
        }
        guard case .object(let object)? = try? JSONDecoder().decode(JSONValue.self, from: line) else {
            throw ActivityError("the line isn't a JSON object")
        }
        let fields = Fields(object)
        guard case .number(let version)? = object["v"], version == Double(Self.version) else {
            throw ActivityError("this Warble speaks only version \(Self.version) of the activities protocol; update Warble or the app so they match")
        }
        guard case .string(let op)? = object["op"] else {
            throw ActivityError("op is missing; it is start, update or end")
        }
        guard ["start", "update", "end"].contains(op) else {
            throw ActivityError("op \"\(op)\" isn't one Warble knows; it is start, update or end")
        }
        do throws(ActivityError) {
            let id = try fields.id()
            switch op {
            case "start": return ActivityRequest(operation: .start(try fields.draft(id: id, isScript: isScript)))
            case "update": return ActivityRequest(operation: .update(id: id, try fields.patch()))
            default: return ActivityRequest(operation: .end(id: id))
            }
        } catch {
            throw ActivityError(error.message, operation: op)
        }
    }
}

/// A line's fields, read one at a time. Each reader throws the sentence a developer reads.
private struct Fields {
    let object: [String: JSONValue]

    init(_ object: [String: JSONValue]) {
        self.object = object
    }

    func id() throws(ActivityError) -> String {
        guard let value = object["id"], value != .null else { throw ActivityError("id is missing") }
        return try bytes("id", value, max: ActivityLimits.idBytes)
    }

    func draft(id: String, isScript: Bool) throws(ActivityError) -> ActivityDraft {
        guard let title = object["title"], title != .null else { throw ActivityError("title is missing") }
        var draft = ActivityDraft(id: id, title: try text("title", title, max: ActivityLimits.title))
        // On a start, null is the same as leaving the field out.
        if let value = present("detail") { draft.detail = try text("detail", value, max: ActivityLimits.detail) }
        if let value = present("badge") { draft.badge = try text("badge", value, max: ActivityLimits.badge) }
        if let value = present("icon") { draft.icon = try icon(value) }
        if let value = present("clock") { draft.clock = try clock(value) }
        if let value = present("buttons") { draft.buttons = try buttons(value) }
        if let value = present("priority") { draft.priority = try priority(value) }
        if let value = present("lasts") { draft.lasts = try lasts(value) }
        if isScript {
            guard let value = present("from") else { throw ActivityError("from is missing; a script names itself with from") }
            draft.from = try text("from", value, max: ActivityLimits.from)
        }
        return draft
    }

    func patch() throws(ActivityError) -> ActivityPatch {
        var patch = ActivityPatch()
        if object["from"] != nil { throw ActivityError("from can't change after the activity starts") }
        if let value = object["title"] {
            patch.title = try text("title", try kept("title", value), max: ActivityLimits.title)
        }
        if let value = object["priority"] {
            patch.priority = try priority(try kept("priority", value))
        }
        patch.detail = try change("detail") { (value) throws(ActivityError) in try text("detail", value, max: ActivityLimits.detail) }
        patch.badge = try change("badge") { (value) throws(ActivityError) in try text("badge", value, max: ActivityLimits.badge) }
        patch.icon = try change("icon", icon)
        patch.clock = try change("clock", clock)
        patch.buttons = try change("buttons", buttons)
        patch.lasts = try change("lasts", lasts)
        return patch
    }

    // MARK: Fields

    private func present(_ name: String) -> JSONValue? {
        object[name].flatMap { $0 == .null ? nil : $0 }
    }

    /// `name` in an update, which is `.clear` for null, `.keep` when the line leaves it out and otherwise read by `read`.
    private func change<Value: Equatable & Sendable>(
        _ name: String, _ read: (JSONValue) throws(ActivityError) -> Value
    ) throws(ActivityError) -> ActivityChange<Value> {
        guard let value = object[name] else { return .keep }
        return value == .null ? .clear : .set(try read(value))
    }

    /// The value of a field an update can change but not clear.
    private func kept(_ name: String, _ value: JSONValue) throws(ActivityError) -> JSONValue {
        guard value != .null else { throw ActivityError("\(name) can't be cleared; send a new one instead") }
        return value
    }

    private func text(_ name: String, _ value: JSONValue, max: Int) throws(ActivityError) -> String {
        guard case .string(let string) = value else { throw ActivityError("\(name) must be text") }
        guard !string.isEmpty else { throw ActivityError("\(name) is empty") }
        guard string.count <= max else { throw ActivityError("\(name) is \(string.count) characters; the most is \(max)") }
        return string
    }

    private func bytes(_ name: String, _ value: JSONValue, max: Int) throws(ActivityError) -> String {
        guard case .string(let string) = value else { throw ActivityError("\(name) must be text") }
        guard !string.isEmpty else { throw ActivityError("\(name) is empty") }
        guard string.utf8.count <= max else { throw ActivityError("\(name) is \(string.utf8.count) bytes; the most is \(max)") }
        return string
    }

    /// An SF Symbol's name: lowercase letters, digits and dots.
    private func symbol(_ name: String, _ value: JSONValue) throws(ActivityError) -> String {
        let string = try bytes(name, value, max: ActivityLimits.symbolBytes)
        guard string.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." }) else {
            throw ActivityError("\(name) is \"\(string)\"; a symbol name has only lowercase letters, digits and dots")
        }
        return string
    }

    private func object(_ name: String, _ value: JSONValue, keys: Set<String>) throws(ActivityError) -> [String: JSONValue] {
        guard case .object(let fields) = value else { throw ActivityError("\(name) must be an object") }
        if let unknown = fields.keys.sorted().first(where: { !keys.contains($0) }) {
            throw ActivityError("\(name) has no \(unknown); it has \(keys.sorted().joined(separator: ", "))")
        }
        return fields
    }

    private func icon(_ value: JSONValue) throws(ActivityError) -> ActivityIcon {
        let fields = try object("icon", value, keys: ["symbol", "tint"])
        guard let symbolName = fields["symbol"] else { throw ActivityError("icon needs a symbol") }
        var icon = ActivityIcon(symbol: try symbol("icon symbol", symbolName))
        if let tint = fields["tint"], tint != .null {
            let names = ActivityTint.allCases.map(\.rawValue)
            guard case .string(let name) = tint, let known = ActivityTint(rawValue: name) else {
                throw ActivityError("icon tint isn't one Warble draws; it is \(names.dropLast().joined(separator: ", ")) or \(names.last ?? "")")
            }
            icon.tint = known
        }
        return icon
    }

    private func clock(_ value: JSONValue) throws(ActivityError) -> ActivityClock {
        let fields = try object("clock", value, keys: ["since", "until"])
        func seconds(_ name: String) throws(ActivityError) -> Date? {
            guard let value = fields[name] else { return nil }
            // Up to the year 2100, so a date can't be one SwiftUI's timer can't draw.
            guard case .number(let seconds) = value, (0...4_102_444_800).contains(seconds) else {
                throw ActivityError("clock \(name) must be a number of seconds since 1970, up to the year 2100")
            }
            return Date(timeIntervalSince1970: seconds)
        }
        switch (try seconds("since"), try seconds("until")) {
        case (let since?, nil): return .since(since)
        case (nil, let until?): return .until(until)
        default: throw ActivityError("clock needs since or until, and only one of them")
        }
    }

    private func buttons(_ value: JSONValue) throws(ActivityError) -> [ActivityButton] {
        guard case .array(let values) = value else { throw ActivityError("buttons must be a list") }
        guard values.count <= ActivityLimits.buttons else {
            throw ActivityError("buttons has \(values.count); an activity can have \(ActivityLimits.buttons) at most")
        }
        var buttons: [ActivityButton] = []
        for value in values {
            let fields = try object("a button", value, keys: ["id", "label", "symbol"])
            guard let id = fields["id"] else { throw ActivityError("a button needs an id") }
            guard let label = fields["label"] else { throw ActivityError("a button needs a label") }
            var button = ActivityButton(
                id: try bytes("button id", id, max: ActivityLimits.buttonIDBytes),
                label: try text("button label", label, max: ActivityLimits.buttonLabel)
            )
            if let symbolName = fields["symbol"], symbolName != .null {
                button.symbol = try symbol("button symbol", symbolName)
            }
            guard !buttons.contains(where: { $0.id == button.id }) else { throw ActivityError("two buttons share the id \"\(button.id)\"") }
            buttons.append(button)
        }
        return buttons
    }

    private func priority(_ value: JSONValue) throws(ActivityError) -> ActivityPriority {
        guard case .string(let name) = value, let priority = ActivityPriority(rawValue: name) else {
            throw ActivityError("priority is normal or high")
        }
        return priority
    }

    private func lasts(_ value: JSONValue) throws(ActivityError) -> TimeInterval {
        let range = ActivityLimits.lasts
        guard case .number(let seconds) = value, range.contains(seconds) else {
            throw ActivityError("lasts must be a number of seconds from \(Int(range.lowerBound)) to \(Int(range.upperBound))")
        }
        return seconds
    }
}

/// A JSON value, so a field set to `null` can be told from one left out, which `Codable` structs can't do.
enum JSONValue: Equatable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}
