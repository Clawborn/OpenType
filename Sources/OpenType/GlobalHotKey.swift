import Carbon
import CoreGraphics
import Foundation

final class GlobalHotKey {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    var onToggle: (() -> Void)?
    var onStopRequested: (() -> Void)?
    var onCycleMode: (() -> Void)?

    private(set) var shortcutKeys = HotKeyPreset.controlShiftSpace.keys
    private(set) var behavior: HotKeyBehavior = .holdToTalk
    private(set) var isUsingPreferred = false
    private(set) var activePreset: HotKeyPreset?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var heldModifierKeyCodes: Set<Int64> = []
    private var suppressedKeyCodes: Set<Int64> = []
    private var modifierChordWasUsed = false
    private var watchedModifierKeyCodes: Set<Int64> = []
    private var modifierNeedsDoubleTap = false
    private var optionHybridEnabled = false
    private var optionLongPressKeyCode: Int64?
    private var pendingLongPressTokens: [Int64: UUID] = [:]
    private var lastModifierTapKeyCode: Int64?
    private var isMomentaryActivation = false
    private var heldModeSwitchKeyCodes: Set<Int64> = []
    private var modeSwitchDidFire = false
    private var modeSwitchChordActive = false
    private var activeChordKeyCode: Int64?
    private var activeChordFlags: CGEventFlags = []
    private var doubleTapDetector = DoubleTapDetector(threshold: 0.45)
    private var stopOnAnyKeyEnabled = false
    private var isInstalled = false

    deinit {
        uninstall()
    }

    @discardableResult
    func install(preference: HotKeyPreset) -> Bool {
        guard !isInstalled else { return true }

        if preference.usesModifierOnlyEventTap {
            if installModifierOnlyTap(preference) {
                shortcutKeys = preference.keys
                if preference.usesOptionHybridGesture {
                    behavior = .optionHybrid
                } else {
                    behavior = preference.usesDoubleModifierTap
                        ? .doubleTapThenAnyKey
                        : .pressThenAnyKey
                }
                activePreset = preference
                isUsingPreferred = true
                isInstalled = true
                return true
            }

            // Modifier-only shortcuts require Accessibility. Keep OpenType
            // usable while the user is granting it, without claiming the
            // requested shortcut is active.
            for fallback in Self.emergencyFallbacks {
                if installChord(fallback) {
                    activePreset = fallback
                    shortcutKeys = fallback.keys
                    isUsingPreferred = false
                    return true
                }
                uninstall()
            }
            return false
        }

        guard installChord(preference) else {
            uninstall()
            return false
        }
        activePreset = preference
        shortcutKeys = preference.keys
        isUsingPreferred = true
        return true
    }

    func reinstall(preference: HotKeyPreset) -> Bool {
        uninstall()
        return install(preference: preference)
    }

    func setRecordingActive(_ active: Bool) {
        switch behavior {
        case .holdToTalk:
            stopOnAnyKeyEnabled = false
        case .optionHybrid:
            stopOnAnyKeyEnabled = active && !isMomentaryActivation
        default:
            stopOnAnyKeyEnabled = active
        }
        if !active {
            suppressedKeyCodes = []
            isMomentaryActivation = false
        }
    }

    private func installModifierOnlyTap(_ preset: HotKeyPreset) -> Bool {
        watchedModifierKeyCodes = Self.modifierKeyCodes(for: preset)
        modifierNeedsDoubleTap = preset.usesDoubleModifierTap
        optionHybridEnabled = preset.usesOptionHybridGesture
        guard !watchedModifierKeyCodes.isEmpty else { return false }

        let callback: CGEventTapCallBack = { _, type, event, userData in
            guard let userData else {
                return Unmanaged.passUnretained(event)
            }
            let instance = Unmanaged<GlobalHotKey>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return instance.handleEventTap(type: type, event: event)
        }

        return installEventTap(
            mask: (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
                | (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue),
            callback: callback
        )
    }

    private func installStopKeyTap() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, userData in
            guard let userData else {
                return Unmanaged.passUnretained(event)
            }
            let instance = Unmanaged<GlobalHotKey>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return instance.handleEventTap(type: type, event: event)
        }

        return installEventTap(
            mask: (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
                | (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue),
            callback: callback
        )
    }

    private func installEventTap(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack
    ) -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleEventTap(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp, suppressedKeyCodes.contains(keyCode) {
            suppressedKeyCodes.remove(keyCode)
            return nil
        }

        if type == .keyDown {
            if isActiveChordEvent(keyCode: keyCode, flags: event.flags) {
                return Unmanaged.passUnretained(event)
            }
            if stopOnAnyKeyEnabled {
                stopOnAnyKeyEnabled = false
                suppressedKeyCodes.insert(keyCode)
                DispatchQueue.main.async { [weak self] in
                    self?.onStopRequested?()
                }
                return nil
            }
            if !heldModifierKeyCodes.isEmpty {
                modifierChordWasUsed = true
                resetModifierTapSequence()
                cancelPendingLongPresses()
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        handleModeSwitchFlagsChanged(keyCode)

        guard watchedModifierKeyCodes.contains(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        if heldModifierKeyCodes.contains(keyCode) {
            handleModifierReleased(keyCode)
        } else {
            handleModifierPressed(keyCode)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleModifierPressed(_ keyCode: Int64) {
        if heldModifierKeyCodes.isEmpty {
            modifierChordWasUsed = modeSwitchChordActive
        } else {
            modifierChordWasUsed = true
            resetModifierTapSequence()
            cancelPendingLongPresses()
        }
        heldModifierKeyCodes.insert(keyCode)

        guard optionHybridEnabled,
              !modifierChordWasUsed,
              !stopOnAnyKeyEnabled else { return }

        let token = UUID()
        pendingLongPressTokens[keyCode] = token
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.optionLongPressThreshold
        ) { [weak self] in
            guard let self,
                  self.pendingLongPressTokens[keyCode] == token,
                  self.heldModifierKeyCodes.contains(keyCode),
                  !self.modifierChordWasUsed else { return }
            self.pendingLongPressTokens[keyCode] = nil
            self.optionLongPressKeyCode = keyCode
            self.isMomentaryActivation = true
            self.resetModifierTapSequence()
            self.onPressed?()
        }
    }

    private func handleModifierReleased(_ keyCode: Int64) {
        heldModifierKeyCodes.remove(keyCode)
        pendingLongPressTokens[keyCode] = nil

        if optionHybridEnabled, optionLongPressKeyCode == keyCode {
            optionLongPressKeyCode = nil
            DispatchQueue.main.async { [weak self] in
                self?.onReleased?()
            }
        } else if !modifierChordWasUsed {
            let now = Date.timeIntervalSinceReferenceDate
            let shouldToggle: Bool
            if optionHybridEnabled || modifierNeedsDoubleTap {
                shouldToggle = registerModifierTap(
                    keyCode: keyCode,
                    at: now
                )
            } else {
                shouldToggle = true
            }

            if shouldToggle {
                isMomentaryActivation = false
                DispatchQueue.main.async { [weak self] in
                    self?.onToggle?()
                }
            }
        }

        if heldModifierKeyCodes.isEmpty {
            modifierChordWasUsed = false
        }
    }

    private func registerModifierTap(
        keyCode: Int64,
        at time: TimeInterval
    ) -> Bool {
        if lastModifierTapKeyCode != keyCode {
            doubleTapDetector.reset()
        }
        let triggered = doubleTapDetector.registerTap(at: time)
        lastModifierTapKeyCode = triggered ? nil : keyCode
        return triggered
    }

    private func resetModifierTapSequence() {
        doubleTapDetector.reset()
        lastModifierTapKeyCode = nil
    }

    private func cancelPendingLongPresses() {
        pendingLongPressTokens = [:]
    }

    private func handleModeSwitchFlagsChanged(_ keyCode: Int64) {
        guard Self.modeSwitchKeyCodes.contains(keyCode) else { return }

        if heldModeSwitchKeyCodes.contains(keyCode) {
            heldModeSwitchKeyCodes.remove(keyCode)
        } else {
            heldModeSwitchKeyCodes.insert(keyCode)
        }

        let leftOptionDown = heldModeSwitchKeyCodes.contains(Int64(kVK_Option))
        let shiftDown = heldModeSwitchKeyCodes.contains(Int64(kVK_Shift))
            || heldModeSwitchKeyCodes.contains(Int64(kVK_RightShift))
        let chordDown = leftOptionDown && shiftDown

        if chordDown {
            modeSwitchChordActive = true
            modifierChordWasUsed = true
            cancelPendingLongPresses()
            resetModifierTapSequence()
            guard !modeSwitchDidFire else { return }
            modeSwitchDidFire = true
            DispatchQueue.main.async { [weak self] in
                self?.onCycleMode?()
            }
        } else {
            modeSwitchDidFire = false
            if heldModeSwitchKeyCodes.isEmpty {
                modeSwitchChordActive = false
            }
        }
    }

    private func isActiveChordEvent(
        keyCode: Int64,
        flags: CGEventFlags
    ) -> Bool {
        guard let activeChordKeyCode, keyCode == activeChordKeyCode else {
            return false
        }
        return flags.intersection(activeChordFlags) == activeChordFlags
    }

    private func installChord(_ preset: HotKeyPreset) -> Bool {
        guard let chord = Self.chord(for: preset) else { return false }
        activeChordKeyCode = Int64(chord.keyCode)
        activeChordFlags = chord.cgFlags

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let instance = Unmanaged<GlobalHotKey>
                .fromOpaque(userData)
                .takeUnretainedValue()
            let kind = GetEventKind(event)

            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) {
                    if instance.behavior == .holdToTalk {
                        instance.onPressed?()
                    } else {
                        instance.onToggle?()
                    }
                } else if kind == UInt32(kEventHotKeyReleased),
                          instance.behavior == .holdToTalk {
                    instance.onReleased?()
                }
            }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(
            signature: fourCharacterCode("OTYP"),
            id: 1
        )
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { return false }

        // Carbon works without Accessibility. The event tap upgrades the
        // interaction from hold-to-talk to press once / any key to stop.
        behavior = installStopKeyTap() ? .pressThenAnyKey : .holdToTalk
        isInstalled = true
        return true
    }

    func uninstall() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        eventTap = nil
        runLoopSource = nil
        heldModifierKeyCodes = []
        suppressedKeyCodes = []
        watchedModifierKeyCodes = []
        modifierNeedsDoubleTap = false
        optionHybridEnabled = false
        optionLongPressKeyCode = nil
        pendingLongPressTokens = [:]
        lastModifierTapKeyCode = nil
        isMomentaryActivation = false
        heldModeSwitchKeyCodes = []
        modeSwitchDidFire = false
        modeSwitchChordActive = false
        modifierChordWasUsed = false
        activeChordKeyCode = nil
        activeChordFlags = []
        stopOnAnyKeyEnabled = false
        doubleTapDetector.reset()
        behavior = .holdToTalk
        isInstalled = false
        isUsingPreferred = false
        activePreset = nil
    }

    private func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }

    private static let emergencyFallbacks: [HotKeyPreset] = [
        .controlShiftSpace,
        .controlOptionSpace,
        .optionSpace
    ]

    private static let optionLongPressThreshold: TimeInterval = 0.30

    private static let modeSwitchKeyCodes: Set<Int64> = [
        Int64(kVK_Option),
        Int64(kVK_Shift),
        Int64(kVK_RightShift)
    ]

    private static func modifierKeyCodes(for preset: HotKeyPreset) -> Set<Int64> {
        switch preset {
        case .leftOption:
            return [Int64(kVK_Option)]
        case .doubleControl:
            return [Int64(kVK_Control), Int64(kVK_RightControl)]
        case .doubleOption:
            return [Int64(kVK_Option), Int64(kVK_RightOption)]
        case .doubleShift:
            return [Int64(kVK_Shift), Int64(kVK_RightShift)]
        default:
            return []
        }
    }

    private static func chord(
        for preset: HotKeyPreset
    ) -> (
        keyCode: UInt32,
        carbonModifiers: UInt32,
        cgFlags: CGEventFlags
    )? {
        switch preset {
        case .controlShiftSpace:
            return (
                UInt32(kVK_Space),
                UInt32(controlKey | shiftKey),
                [.maskControl, .maskShift]
            )
        case .optionSpace:
            return (
                UInt32(kVK_Space),
                UInt32(optionKey),
                [.maskAlternate]
            )
        case .controlSpace:
            return (
                UInt32(kVK_Space),
                UInt32(controlKey),
                [.maskControl]
            )
        case .controlOptionSpace:
            return (
                UInt32(kVK_Space),
                UInt32(controlKey | optionKey),
                [.maskControl, .maskAlternate]
            )
        default:
            return nil
        }
    }
}

struct DoubleTapDetector {
    let threshold: TimeInterval
    private(set) var lastTap: TimeInterval?

    mutating func registerTap(at time: TimeInterval) -> Bool {
        if let lastTap, time - lastTap <= threshold {
            self.lastTap = nil
            return true
        }
        lastTap = time
        return false
    }

    mutating func reset() {
        lastTap = nil
    }
}
