import Foundation
import CoreGraphics

final class FunctionKeyMonitor {
    var onFnPressedChanged: ((Bool) -> Void)?
    var onFnSpacePressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnPressed = false

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<FunctionKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            switch type {
            case .flagsChanged:
                let fnNow = event.flags.contains(.maskSecondaryFn)

                if fnNow != monitor.isFnPressed {
                    monitor.isFnPressed = fnNow
                    monitor.onFnPressedChanged?(fnNow)
                }
                return Unmanaged.passUnretained(event)
            case .keyDown, .keyUp:
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let isSpace = keyCode == 49
                let fnActive = event.flags.contains(.maskSecondaryFn) || monitor.isFnPressed
                if isSpace && fnActive {
                    if type == .keyDown {
                        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                        if !isRepeat {
                            monitor.onFnSpacePressed?()
                        }
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isFnPressed = false
    }

    deinit {
        stop()
    }
}
