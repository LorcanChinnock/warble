import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import WarbleCore

struct Artwork: View {
    let image: NSImage?
    var radius: CGFloat = 8
    /// The placeholder note's size, when there's no art.
    var symbolSize: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let image {
                // Clear takes the size the caller gives, so artwork that isn't square, such as a video's, fills it and
                // is cropped rather than drawn at its own width.
                Color.clear.overlay {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else {
                shape.fill(Color(white: 0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: symbolSize))
                            .foregroundStyle(Native.secondary)
                    }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// Lets the art be dragged into another app, over the button that opens the app playing: a click still opens it, and a
/// drag starts once the pointer moves. It carries what `ArtDrag` says, and reports the drag starting and ending so the
/// card stays open meanwhile.
struct ArtDragArea: NSViewRepresentable {
    let drag: ArtDrag
    let image: NSImage?
    let onClick: () -> Void
    let onDragging: (Bool) -> Void

    func makeNSView(context: Context) -> ArtDragView {
        ArtDragView()
    }

    func updateNSView(_ view: ArtDragView, context: Context) {
        view.drag = drag
        view.image = image
        view.onClick = onClick
        view.onDragging = onDragging
    }
}

final class ArtDragView: NSView, NSDraggingSource {
    /// How far the pointer moves with the button down before a click becomes a drag, as in Finder.
    private static let dragDistance: CGFloat = 4

    var drag: ArtDrag?
    var image: NSImage?
    var onClick: () -> Void = {}
    var onDragging: (Bool) -> Void = { _ in }
    /// Where the button went down, until the click ends or becomes a drag.
    private var downAt: NSPoint?

    // The panel is never key, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt, let drag else { return }
        let point = event.locationInWindow
        guard hypot(point.x - downAt.x, point.y - downAt.y) >= Self.dragDistance else { return }
        self.downAt = nil
        beginDraggingSession(with: items(for: drag), event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if downAt != nil {
            onClick()
        }
        downAt = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragging(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragging(false)
    }

    /// One item for the art and the link together, as Safari drags an image, so each app takes the form it uses: Finder
    /// the image as a file, Notes or Messages the image, and a text field or a browser the link. It starts from the art
    /// under the pointer.
    private func items(for drag: ArtDrag) -> [NSDraggingItem] {
        let writer: NSPasteboardWriting
        if let data = drag.image, let fileName = drag.fileName {
            writer = ArtPromise(data: data, fileName: fileName, link: drag.link)
        } else if let link = drag.link {
            let item = NSPasteboardItem()
            item.setString(link.absoluteString, forType: .URL)
            item.setString(link.absoluteString, forType: .string)
            writer = item
        } else {
            return []
        }
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: image ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil))
        return [item]
    }
}

/// The art as a file Finder writes where it's dropped, named for the track, as image data for an app that takes it
/// directly, such as Messages or Notes, and the track's link, if any, as a URL and as text.
final class ArtPromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let data: Data
    private let fileName: String
    private let link: URL?
    /// The type the bytes already are, which an app can take as they are.
    private let imageType: NSPasteboard.PasteboardType

    init(data: Data, fileName: String, link: URL?) {
        self.data = data
        self.fileName = fileName
        self.link = link
        let type = UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .jpeg
        imageType = NSPasteboard.PasteboardType(type.identifier)
        super.init()
        fileType = type.identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + (imageType == .tiff ? [.tiff] : [imageType, .tiff])
            + (link == nil ? [] : [.URL, .string])
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case imageType: data
        case .tiff: NSImage(data: data)?.tiffRepresentation
        case .URL, .string: link?.absoluteString
        default: super.pasteboardPropertyList(forType: type)
        }
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    nonisolated func filePromiseProvider(
        _ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try data.write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
