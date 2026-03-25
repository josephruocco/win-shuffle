import AppKit
import Carbon

final class GlobalHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: fourCharCode("WSHF"), id: 1)
    fileprivate var handler: (@MainActor () -> Void)?

    func install(handler: @escaping @MainActor () -> Void) {
        uninstall()
        self.handler = handler

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func uninstall() {
        handler = nil

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleEvent(event: EventRef, handler: @escaping @MainActor () -> Void) -> OSStatus {
        var receivedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )

        guard status == noErr, receivedID.id == hotKeyID.id, receivedID.signature == hotKeyID.signature else {
            return status
        }

        Task { @MainActor in
            handler()
        }
        return noErr
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return noErr
    }

    let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    guard let handler = monitor.handler else {
        return noErr
    }

    return monitor.handleEvent(event: event, handler: handler)
}

private func fourCharCode(_ value: String) -> FourCharCode {
    value.utf16.reduce(0) { partialResult, element in
        (partialResult << 8) + FourCharCode(element)
    }
}
