import AppKit
import ApplicationServices

// The pointer for scripts/perf.sh, in global screen points from the top left of the main display, as CGEvent and
// accessibility use them. Needs Accessibility permission for the terminal.
//   perf-input housing            the centre of the main display's camera housing, or its top centre without a notch
//   perf-input pointer            where the pointer is
//   perf-input move X Y           moves the pointer, as a hand on the trackpad would
//   perf-input click X Y          moves the pointer there and clicks
//   perf-input find BUNDLE NAME   the centre of the element whose accessibility description is NAME, in the app
//                                 with that bundle identifier

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func post(_ type: CGEventType, _ at: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(20_000)
}

let args = CommandLine.arguments
func point() -> CGPoint {
    guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else { fail("usage: perf-input move|click X Y") }
    return CGPoint(x: x, y: y)
}

func centre(of element: AXUIElement) -> CGPoint? {
    var position: CFTypeRef?
    var size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
}

func find(_ name: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    var description: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description) == .success, description as? String == name {
        return element
    }
    var children: CFTypeRef?
    guard depth < 30, AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
          let children = children as? [AXUIElement] else { return nil }
    for child in children {
        if let found = find(name, in: child, depth: depth + 1) { return found }
    }
    return nil
}

switch args.count > 1 ? args[1] : "" {
case "housing":
    guard let screen = NSScreen.main, let primary = NSScreen.screens.first else { fail("no display") }
    let x: CGFloat
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
        x = (left.maxX + right.minX) / 2
    } else {
        x = screen.frame.midX
    }
    // A few points down from the top edge, inside the housing and the virtual notch alike.
    let y = primary.frame.maxY - screen.frame.maxY + 6
    print(Int(x), Int(y))
case "pointer":
    let location = CGEvent(source: nil)?.location ?? .zero
    print(Int(location.x), Int(location.y))
case "move":
    post(.mouseMoved, point())
case "click":
    let at = point()
    post(.mouseMoved, at)
    post(.leftMouseDown, at)
    post(.leftMouseUp, at)
case "find":
    guard args.count >= 4 else { fail("usage: perf-input find BUNDLE NAME") }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else { fail("\(args[2]) isn't running") }
    guard let element = find(args[3], in: AXUIElementCreateApplication(app.processIdentifier)), let at = centre(of: element) else { fail("no \(args[3]) in \(args[2])") }
    print(Int(at.x), Int(at.y))
default:
    fail("usage: perf-input housing|pointer|move|click|find …")
}
