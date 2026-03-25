import AppKit
import ApplicationServices
import CoreGraphics

struct AccessibilityWindow: Identifiable {
    let id: String
    let appName: String
    let title: String
    let element: AXUIElement
    let frame: CGRect
    let screenFrame: CGRect
}

enum AccessibilityWindowError: Error {
    case attributeReadFailed
}

extension AccessibilityWindow {
    static func loadMovableWindows(excluding bundleID: String?) -> [AccessibilityWindow] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isHidden &&
                app.bundleIdentifier != bundleID &&
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            .flatMap { app in
                windows(for: app)
            }
    }

    private static func windows(for app: NSRunningApplication) -> [AccessibilityWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windowElements: [AXUIElement] = copyArrayValue(
            attribute: kAXWindowsAttribute as CFString,
            from: appElement
        ) else {
            return []
        }

        return windowElements.compactMap { element in
            guard let window = loadWindow(
                element: element,
                appName: app.localizedName ?? "Unknown App",
                pid: app.processIdentifier
            ) else {
                return nil
            }
            return window
        }
    }

    private static func loadWindow(
        element: AXUIElement,
        appName: String,
        pid: pid_t
    ) -> AccessibilityWindow? {
        guard isStandardWindow(element) else {
            return nil
        }

        guard
            let positionValue: AXValue = copyValue(attribute: kAXPositionAttribute as CFString, from: element),
            let sizeValue: AXValue = copyValue(attribute: kAXSizeAttribute as CFString, from: element)
        else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue, .cgSize, &size)

        guard size.width > 160, size.height > 120 else {
            return nil
        }

        let frame = CGRect(origin: origin, size: size)
        guard
            !frame.isEmpty,
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
        else {
            return nil
        }

        let title: String = copyValue(attribute: kAXTitleAttribute as CFString, from: element) ?? appName
        return AccessibilityWindow(
            id: "\(pid)-\(title)-\(Int(frame.origin.x))-\(Int(frame.origin.y))",
            appName: appName,
            title: title.isEmpty ? appName : title,
            element: element,
            frame: frame,
            screenFrame: screen.visibleFrame
        )
    }

    private static func isStandardWindow(_ element: AXUIElement) -> Bool {
        let subrole: String? = copyValue(attribute: kAXSubroleAttribute as CFString, from: element)
        let minimized: NSNumber? = copyValue(attribute: kAXMinimizedAttribute as CFString, from: element)

        guard minimized?.boolValue != true else {
            return false
        }

        return subrole == nil || subrole == kAXStandardWindowSubrole as String
    }

    static func setPosition(_ point: CGPoint, for element: AXUIElement) {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            return
        }

        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private static func copyValue<T>(attribute: CFString, from element: AXUIElement) -> T? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        guard result == .success, let rawValue else {
            return nil
        }
        return rawValue as? T
    }

    private static func copyArrayValue(attribute: CFString, from element: AXUIElement) -> [AXUIElement]? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        guard result == .success, let rawValue else {
            return nil
        }
        return rawValue as? [AXUIElement]
    }
}
