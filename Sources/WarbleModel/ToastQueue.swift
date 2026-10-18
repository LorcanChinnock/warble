import Foundation

/// A short notice that slides out of the notch. `Content` is what it shows, such as a title and artist.
public struct Notice<Content: Equatable & Sendable>: Equatable, Sendable {
    /// What a notice is about. A new notice of a kind replaces the one of that kind already showing or waiting.
    public enum Kind: String, CaseIterable, Sendable {
        case trackChanged
        case outputChanged
    }

    public var kind: Kind
    public var content: Content
    /// How long it shows, counted from when it appears or the pointer last left it.
    public var duration: TimeInterval

    public init(kind: Kind, content: Content, duration: TimeInterval) {
        self.kind = kind
        self.content = content
        self.duration = duration
    }
}

/// Decides which notice shows and for how long: one at a time, in the order they came, with a newer notice of the same
/// kind taking the place of the older, so skipping five tracks shows one toast for the last. The pointer on a toast
/// keeps it showing. Like `HoverIntent` it holds no timers: after each call the owner schedules one for `deadline`, if
/// any, and calls `advance(to:)` when it fires.
public struct ToastQueue<Content: Equatable & Sendable>: Equatable, Sendable {
    /// The notice showing, if any.
    public private(set) var current: Notice<Content>?
    /// When `current` goes and the next shows, or `nil` while nothing shows or the pointer holds it.
    public private(set) var deadline: Date?
    public private(set) var waiting: [Notice<Content>] = []
    private var held = false

    public init() {}

    public mutating func post(_ notice: Notice<Content>, at date: Date) {
        advance(to: date)
        if current?.kind == notice.kind || current == nil {
            // A replacement shows afresh, so the newest gets its full time.
            show(notice, at: date)
        } else if let index = waiting.firstIndex(where: { $0.kind == notice.kind }) {
            waiting[index] = notice
        } else {
            waiting.append(notice)
        }
    }

    /// The pointer moved onto the toast (`true`) or off it. Leaving gives the toast its full time again.
    public mutating func hold(_ holding: Bool, at date: Date) {
        advance(to: date)
        guard let current, holding != held else { return }
        held = holding
        deadline = holding ? nil : date + current.duration
    }

    /// A click on the toast: it goes at once, and the next shows.
    public mutating func dismiss(at date: Date) {
        advance(to: date)
        guard current != nil else { return }
        // The pointer was on the notice it clicked, not the one that replaces it.
        held = false
        showNext(at: date)
    }

    /// Applies every deadline due by `date`. A late timer shows each waiting notice in turn from when it was due, so
    /// ones that would already have gone are skipped.
    public mutating func advance(to date: Date) {
        while let due = deadline, due <= date {
            showNext(at: due)
        }
    }

    private mutating func showNext(at date: Date) {
        if waiting.isEmpty {
            current = nil
            deadline = nil
            held = false
        } else {
            show(waiting.removeFirst(), at: date)
        }
    }

    private mutating func show(_ notice: Notice<Content>, at date: Date) {
        current = notice
        deadline = held ? nil : date + notice.duration
    }
}
