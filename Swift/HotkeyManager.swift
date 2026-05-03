
import Carbon
import Cocoa

// MARK: - Error Handling
enum HotkeyManagerError: Error, LocalizedError {
    case settingsManagerNotAvailable
    case permissionDenied
    case hotkeyRegistrationFailed(status: OSStatus)
    case eventHandlerInstallationFailed(status: OSStatus)
    case bundleIdentifierNotFound

    var errorDescription: String? {
        switch self {
        case .settingsManagerNotAvailable:
            return "Settings manager is not available."
        case .permissionDenied:
            return "Accessibility permission is required for global hotkeys."
        case .hotkeyRegistrationFailed(let status):
            return "Failed to register global hotkey with status: \(status)"
        case .eventHandlerInstallationFailed(let status):
            return "Failed to install global hotkey event handler with status: \(status)"
        case .bundleIdentifierNotFound:
            return "Could not determine the application's bundle identifier."
        }
    }
}

// MARK: - HotkeyManager Class
class HotkeyManager {
    
    // MARK: - Properties
    private var transcribeHotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?
    
    private let logger = Logger()
    private let settingsManager: SettingsManager
    
    // Callbacks for hotkey presses
    var onTranscribeHotkeyPressed: (() -> Void)?
    
    // MARK: - Initialization
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        logger.log("[HotkeyManager] Initializing", level: .info)
        setupHotkeys()
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeySettingsChanged),
            name: .hotkeySettingsChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanup()
    }
    
    // MARK: - Public Methods
    func refreshHotkeyConfiguration() {
        logger.log("[HotkeyManager] Refreshing hotkey configuration", level: .info)
        cleanup()
        setupHotkeys()
    }
    
    // MARK: - Settings Change Handling
    @objc private func handleHotkeySettingsChanged() {
        logger.log("[HotkeyManager] Transcribe hotkey settings changed, refreshing configuration", level: .info)
        refreshHotkeyConfiguration()
    }
    
    // MARK: - Setup
    private func setupHotkeys() {
        // First, set up the local hotkey which always works
        setupLocalHotkey()
        
        // Then, attempt to set up the global hotkey
        do {
            try setupGlobalHotkey()
        } catch {
            logger.logError(error, context: "Failed to register global hotkey")
            if let error = error as? HotkeyManagerError, case .permissionDenied = error {
                logAccessibilityInstructions()
                // Start polling for permission grant
                startAccessibilityPermissionPolling()
            }
        }
    }
    
    // MARK: - Accessibility Polling
    private var permissionPollingTimer: Timer?
    
    private func startAccessibilityPermissionPolling() {
        // Poll every 2 seconds to check if user granted permission
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): kCFBooleanFalse]
            let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if isTrusted {
                self.logger.log("[HotkeyManager] Accessibility permission granted! Registering global hotkey...", level: .info)
                timer.invalidate()
                self.permissionPollingTimer = nil
                
                // Re-attempt to register global hotkey
                do {
                    try self.setupGlobalHotkey()
                } catch {
                    self.logger.logError(error, context: "Failed to register global hotkey after permission grant")
                }
            }
        }
    }
    
    // MARK: - Global Hotkey (Carbon)
    private func setupGlobalHotkey() throws {
        guard checkAccessibilityPermissions() else {
            throw HotkeyManagerError.permissionDenied
        }
        
        // Register transcribe hotkey
        let transcribeDisplay = settingsManager.getHotkeyDisplayString()
        logger.log("[HotkeyManager] Attempting to register transcribe hotkey: \(transcribeDisplay)", level: .debug)
        
        let (transcribeKeyCode, transcribeModifiers) = try getTranscribeHotkeyConfiguration()
        let transcribeHotkeyID = try getUniqueHotkeyID(id: 1)
        
        let transcribeStatus = RegisterEventHotKey(transcribeKeyCode, transcribeModifiers, transcribeHotkeyID, GetApplicationEventTarget(), 0, &transcribeHotkeyRef)
        guard transcribeStatus == noErr else {
            throw HotkeyManagerError.hotkeyRegistrationFailed(status: transcribeStatus)
        }
        logger.log("[HotkeyManager] Transcribe hotkey registered successfully: \(transcribeDisplay)", level: .info)

        try installGlobalHotkeyEventHandler()
    }
    
    private func installGlobalHotkeyEventHandler() throws {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let hotkeyManager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            hotkeyManager.handleGlobalHotkeyEvent(event: event)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        
        guard status == noErr else {
            throw HotkeyManagerError.eventHandlerInstallationFailed(status: status)
        }
        logger.log("[HotkeyManager] Global hotkey event handler installed", level: .debug)
    }
    
    private func handleGlobalHotkeyEvent(event: EventRef?) {
        guard let event = event else { return }
        
        // Get the hotkey ID from the event to determine which hotkey was pressed
        var hotkeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        
        guard result == noErr else {
            logger.log("[HotkeyManager] Failed to get hotkey ID from event", level: .error)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if hotkeyID.id == 1 {
                // Transcribe hotkey
                let display = self.settingsManager.getHotkeyDisplayString()
                self.logger.log("[HotkeyManager] Transcribe hotkey pressed: \(display)", level: .info)
                self.onTranscribeHotkeyPressed?()
            }
        }
    }
    
    // MARK: - Local Hotkey (Cocoa)
    private func setupLocalHotkey() {
        let transcribeDisplay = settingsManager.getHotkeyDisplayString()
        logger.log("[HotkeyManager] Setting up local hotkey: \(transcribeDisplay)", level: .debug)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            let actualModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Check transcribe hotkey
            if let (expectedKeyCode, expectedModifiers) = try? self.getTranscribeHotkeyConfigurationForLocalMonitor() {
                if actualModifiers == expectedModifiers && event.keyCode == expectedKeyCode {
                    self.logger.log("[HotkeyManager] Local transcribe hotkey pressed: \(transcribeDisplay)", level: .info)
                    self.onTranscribeHotkeyPressed?()
                    return nil // Swallow the event
                }
            }

            return event
        }
        logger.log("[HotkeyManager] Local hotkey monitor installed", level: .debug)
    }
    
    // MARK: - Configuration & Permissions
    private func getUniqueHotkeyID(id: UInt32) throws -> EventHotKeyID {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw HotkeyManagerError.bundleIdentifierNotFound
        }
        
        let signature = fourCharString(from: bundleId)
        return EventHotKeyID(signature: signature, id: id)
    }
    
    private func fourCharString(from string: String) -> FourCharCode {
        // A simple hashing algorithm to generate a FourCharCode from a string.
        var hash: UInt32 = 0
        for char in string.unicodeScalars {
            hash = (hash &* 31) &+ char.value
        }
        return hash
    }
    
    private func getTranscribeHotkeyConfiguration() throws -> (keyCode: UInt32, modifiers: UInt32) {
        let keyCode = UInt32(settingsManager.hotkeyKeyCode)
        var modifiers: UInt32 = 0
        for modifier in settingsManager.hotkeyModifiers {
            switch modifier {
            case "command": modifiers |= UInt32(cmdKey)
            case "shift":   modifiers |= UInt32(shiftKey)
            case "option":  modifiers |= UInt32(optionKey)
            case "control": modifiers |= UInt32(controlKey)
            default: break
            }
        }
        return (keyCode, modifiers)
    }
    
    private func getTranscribeHotkeyConfigurationForLocalMonitor() throws -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let keyCode = UInt16(settingsManager.hotkeyKeyCode)
        var modifiers: NSEvent.ModifierFlags = []
        for modifier in settingsManager.hotkeyModifiers {
            switch modifier {
            case "command": modifiers.insert(.command)
            case "shift":   modifiers.insert(.shift)
            case "option":  modifiers.insert(.option)
            case "control": modifiers.insert(.control)
            default: break
            }
        }
        return (keyCode, modifiers)
    }

    private func checkAccessibilityPermissions() -> Bool {
        // First check without prompting
        let checkOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): kCFBooleanFalse]
        let isTrusted = AXIsProcessTrustedWithOptions(checkOptions as CFDictionary)
        
        if !isTrusted {
            // Prompt the user to grant permissions
            logger.log("[HotkeyManager] Accessibility not granted, prompting user...", level: .info)
            let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): kCFBooleanTrue]
            _ = AXIsProcessTrustedWithOptions(promptOptions as CFDictionary)
        }
        
        return isTrusted
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        logger.log("[HotkeyManager] Cleaning up hotkey resources", level: .debug)
        
        // Stop permission polling timer
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
        
        // Clean up global hotkeys
        if let hotkeyRef = transcribeHotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.transcribeHotkeyRef = nil
            logger.log("[HotkeyManager] Transcribe hotkey unregistered", level: .debug)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
            logger.log("[HotkeyManager] Global event handler removed", level: .debug)
        }
        
        // Clean up local monitor
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
            logger.log("[HotkeyManager] Local hotkey monitor removed", level: .debug)
        }
    }
    
    // MARK: - Helper
    private func logAccessibilityInstructions() {
        logger.log("[HotkeyManager] To enable global hotkeys, please grant Accessibility permissions:", level: .warning)
        logger.log("[HotkeyManager] 1. Open System Settings > Privacy & Security", level: .warning)
        logger.log("[HotkeyManager] 2. Select 'Accessibility'", level: .warning)
        logger.log("[HotkeyManager] 3. Find 'uttr' and enable it.", level: .warning)
        logger.log("[HotkeyManager] 4. A restart of the app may be required.", level: .warning)
    }
}
