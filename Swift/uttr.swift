import SwiftUI
import Cocoa
import AVFoundation

@main
struct uttr: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {

    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private var audioRecorder: AudioRecorder?
    private var hotkeyManager: HotkeyManager?
    private var pasteManager: PasteManager?
    private var transcriptionProvider: TranscriptionProvider?
    private var logger: Logger?
    private var settingsManager: SettingsManager?
    private var historyManager: HistoryManager?
    private var notificationManager: NotificationManager?
    private var menuBarPopoverView: MenuBarPopoverView?
    private var popover: NSPopover?
    private var menuBarIconManager: MenuBarIconManager?
    private var eventMonitor: Any?

    // Settings window
    private var settingsWindow: NSWindow?
    private var settingsWindowController: NSWindowController?

    private var isRecording = false

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as menu bar app - hide from dock and cmd+tab
        NSApp.setActivationPolicy(.accessory)

        setupComponents()
        setupMenuBar()
        startTranscriptionProvider()
        logger?.log("=== App Setup Complete ===", level: .info)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    // MARK: - Setup
    private func setupComponents() {
        logger = Logger()
        logger?.log("=== Initializing App Setup ===", level: .debug)

        // Initialize managers
        settingsManager = SettingsManager()
        historyManager = HistoryManager()
        notificationManager = NotificationManager()

        // Initialize core components
        audioRecorder = AudioRecorder()

        guard let settingsManager = settingsManager else {
            logger?.log("Failed to initialize required managers", level: .error)
            return
        }

        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        pasteManager = PasteManager()
        transcriptionProvider = TranscriptionProviderFactory.make(
            id: settingsManager.transcriptionProviderID,
            settings: settingsManager
        )
        logger?.log("TranscriptionProvider initialized: \(settingsManager.transcriptionProviderID)", level: .debug)

        // Set up hotkey callbacks
        hotkeyManager?.onTranscribeHotkeyPressed = { [weak self] in
            self?.handleTranscribeHotkeyPress()
        }

        // Initialize menu bar popover view
        menuBarPopoverView = MenuBarPopoverView()
        menuBarPopoverView?.onStartRecording = { [weak self] in
            self?.startRecording()
        }
        menuBarPopoverView?.onStopRecording = { [weak self] in
            self?.stopRecording()
        }
        menuBarPopoverView?.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }

        // Set up notification observers for settings changes
        NotificationCenter.default.addObserver(
            forName: .transcriptionProviderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSettingsChanged()
        }

        NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.refreshHotkeyConfiguration()
        }

        logger?.log("App Components Initialized", level: .debug)
    }

    private func startTranscriptionProvider() {
        Task { [weak self] in
            guard let self, let provider = self.transcriptionProvider else { return }
            do {
                try await provider.prepare()
                await MainActor.run {
                    self.logger?.log("Transcription provider ready: \(provider.displayName)", level: .info)
                    self.notificationManager?.showAppInitializationSuccess()
                    self.menuBarIconManager?.playStartupAnimation()
                }
            } catch {
                await MainActor.run {
                    self.logger?.log("Failed to prepare transcription provider: \(error)", level: .error)
                    self.notificationManager?.showAppInitializationError("Failed to prepare transcription provider")
                    self.menuBarIconManager?.showErrorState()
                }
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.imagePosition = .imageLeft
            button.action = #selector(menuBarClicked)
            button.target = self
        }

        // Initialize the menu bar icon manager
        menuBarIconManager = MenuBarIconManager(statusItem: statusItem!)

        // Setup popover for menu with our custom MenuBarView
        setupPopover()
    }

    private func setupPopover() {
        guard let menuBarPopoverView = menuBarPopoverView else {
            logger?.log("Error: menuBarPopoverView is nil during popover setup", level: .error)
            return
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 160, height: 54)
        popover?.behavior = .transient  // Auto-dismisses when losing focus
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: menuBarPopoverView)

        // Set up popover delegate for additional menu-bar behavior
        popover?.delegate = self

        logger?.log("MenuBarPopoverView setup complete", level: .debug)
    }

    // MARK: - Event Handlers
    @objc private func menuBarClicked() {
        logger?.log("Menu bar clicked!")

        guard let button = statusItem?.button else { return }

        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }

        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)

        // Add event monitor to detect clicks outside the popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.popover?.isShown == true {
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)

        // Remove event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleTranscribeHotkeyPress() {
        if isRecording {
            logger?.log("Stopping recording...", level: .info)
            stopRecording()
        } else {
            logger?.log("Starting recording...", level: .info)
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }

        do {
            try audioRecorder?.startRecording()
            isRecording = true
            menuBarPopoverView?.updateRecordingState(true)

            // Hide our icon and let Apple's native recording indicator show
            menuBarIconManager?.setRecordingState()

            notificationManager?.showRecordingStarted()
            logger?.log("Recording started")
        } catch {
            logger?.logError(error, context: "Failed to start recording")
            notificationManager?.showTranscriptionError("Failed to start recording")
            menuBarIconManager?.showErrorState()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }

        guard let audioFileURL = audioRecorder?.stopRecording() else {
            logger?.log("Failed to get audio file", level: .error)
            notificationManager?.showTranscriptionError("Failed to save audio file")
            menuBarIconManager?.showErrorState()
            return
        }

        isRecording = false
        menuBarPopoverView?.updateRecordingState(false)
        notificationManager?.showRecordingStopped()
        logger?.log("Audio file successfully saved to: \(audioFileURL.path)", level: .debug)
        menuBarIconManager?.setProcessingState()

        processAudioFile(audioFileURL)
    }

    private func processAudioFile(_ audioFileURL: URL) {
        logger?.log("Starting audio file processing for: \(audioFileURL.path)", level: .info)

        Task { [weak self] in
            guard let self, let provider = self.transcriptionProvider else { return }
            do {
                let transcribedText = try await provider.transcribe(audioFileURL: audioFileURL)
                await MainActor.run {
                    self.logger?.log("Transcription completed successfully", level: .info)
                    self.handleTranscribedText(transcribedText, audioFileName: audioFileURL.lastPathComponent)
                }
            } catch {
                await MainActor.run {
                    self.logger?.logError(error, context: "Transcription failed")
                    self.logger?.log("Transcription failed: \(error.localizedDescription)", level: .error)
                    self.notificationManager?.showTranscriptionError("Transcription failed: \(error.localizedDescription)")
                    self.menuBarIconManager?.showErrorState()
                }
            }
        }
    }

    private func handleTranscribedText(_ text: String, audioFileName: String? = nil) {
        logger?.log("Handling transcribed text: \(text)", level: .info)

        // Add to history
        historyManager?.addTranscription(text, audioFileName: audioFileName)

        // Paste the transcribed text at cursor
        pasteManager?.pasteText(text) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.logger?.log("Text pasted at cursor successfully", level: .info)
                    self?.notificationManager?.showTranscriptionSuccess()
                    self?.menuBarIconManager?.showSuccessState()
                } else {
                    self?.logger?.log("Failed to paste text at cursor", level: .error)
                    self?.notificationManager?.showTranscriptionError("Failed to paste text at cursor")
                    self?.menuBarIconManager?.showErrorState()
                }
            }
        }
    }

    // MARK: - Settings Window Management
    private func openSettingsWindow() {
        logger?.log("Opening settings window", level: .info)

        if settingsWindow == nil {
            // Create settings window
            let settingsView = SettingsWindowView()
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "uttr"
            settingsWindow?.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 700, height: 500))
            settingsWindow?.center()
            settingsWindow?.delegate = self

            settingsWindowController = NSWindowController(window: settingsWindow)
        }

        // Show in dock and cmd+tab
        NSApp.setActivationPolicy(.regular)

        // Show and activate window
        settingsWindowController?.showWindow(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSettingsWindow() {
        logger?.log("Closing settings window", level: .info)

        settingsWindow = nil
        settingsWindowController = nil

        // Hide from dock and cmd+tab
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Window Delegate
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            closeSettingsWindow()
        }
    }

    // MARK: - Settings Handler
    private func handleSettingsChanged() {
        logger?.log("Settings changed, swapping transcription provider", level: .info)
        hotkeyManager?.refreshHotkeyConfiguration()

        guard let settings = settingsManager else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.transcriptionProvider?.teardown()
            self.transcriptionProvider = TranscriptionProviderFactory.make(
                id: settings.transcriptionProviderID,
                settings: settings
            )
            self.startTranscriptionProvider()
        }
    }

    // MARK: - Cleanup
    private func cleanup() {
        if isRecording {
            _ = audioRecorder?.stopRecording()
        }
        Task { await transcriptionProvider?.teardown() }
        closePopover()

        // Close settings window if open
        if settingsWindow != nil {
            settingsWindow?.close()
            settingsWindow = nil
            settingsWindowController = nil
        }

        NotificationCenter.default.removeObserver(self)
        logger?.log("App terminating")
    }
}
