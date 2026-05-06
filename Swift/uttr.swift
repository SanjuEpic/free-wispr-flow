import SwiftUI
import Cocoa
import AVFoundation

@main
struct uttr: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindowView(settings: appDelegate.settingsManager)
        }
        .defaultSize(width: 520, height: 480)
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
    let settingsManager = SettingsManager()
    private var notificationManager: NotificationManager?
    private var popoverViewModel = PopoverViewModel()
    private var popover: NSPopover?
    private var menuBarIconManager: MenuBarIconManager?
    private var eventMonitor: Any?

    // History window
    private var historyWindow: NSWindow?
    private var historyWindowController: NSWindowController?

    // Settings window
    private var settingsWindow: NSWindow?
    private var settingsWindowController: NSWindowController?

    private var isRecording = false

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
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

        notificationManager = NotificationManager()
        audioRecorder = AudioRecorder()

        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        pasteManager = PasteManager()
        transcriptionProvider = TranscriptionProviderFactory.make(
            id: settingsManager.transcriptionProviderID,
            settings: settingsManager
        )
        logger?.log("TranscriptionProvider initialized: \(settingsManager.transcriptionProviderID)", level: .debug)

        hotkeyManager?.onTranscribeHotkeyPressed = { [weak self] in
            self?.handleTranscribeHotkeyPress()
        }

        // Wire popover callbacks
        popoverViewModel.hotkeyDisplay = settingsManager.getHotkeyDisplayString()
        popoverViewModel.onStartRecording = { [weak self] in self?.startRecording() }
        popoverViewModel.onStopRecording  = { [weak self] in self?.stopRecording() }
        popoverViewModel.onOpenSettings   = { [weak self] in self?.openSettingsWindow() }
        popoverViewModel.onOpenHistory    = { [weak self] in self?.openHistoryWindow() }

        NotificationCenter.default.addObserver(
            forName: .transcriptionProviderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.handleSettingsChanged() }

        NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.refreshHotkeyConfiguration()
            self?.popoverViewModel.hotkeyDisplay = self?.settingsManager.getHotkeyDisplayString() ?? ""
        }

        // Show dock icon whenever a titled window is active
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow,
               window.styleMask.contains(.titled) {
                NSApp.setActivationPolicy(.regular)
            }
        }

        // Reset activation policy to accessory when all titled windows have closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.dismissIfNoWindows()
            }
        }

        logger?.log("App Components Initialized", level: .debug)
    }

    private func startTranscriptionProvider() {
        settingsManager.providerStatus = "Loading…"
        Task { [weak self] in
            guard let self, let provider = self.transcriptionProvider else { return }
            do {
                try await provider.prepare()
                await MainActor.run {
                    self.logger?.log("Transcription provider ready: \(provider.displayName)", level: .info)
                    self.updateProviderStatus()
                    self.notificationManager?.showAppInitializationSuccess()
                    self.menuBarIconManager?.playStartupAnimation()
                }
            } catch {
                await MainActor.run {
                    self.logger?.log("Failed to prepare transcription provider: \(error)", level: .error)
                    self.settingsManager.providerStatus = "Failed — \(error.localizedDescription)"
                    self.notificationManager?.showAppInitializationError("Failed to prepare transcription provider")
                    self.menuBarIconManager?.showErrorState()
                }
            }
        }
    }

    private func updateProviderStatus() {
        if settingsManager.transcriptionProviderID == "python.whisper" {
            settingsManager.providerStatus = "Sidecar running · port \(settingsManager.pythonWhisper.serverPort)"
        } else {
            settingsManager.providerStatus = "Loaded · ~600 MB"
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.imagePosition = .imageLeft
            button.action = #selector(menuBarClicked)
            button.target = self
        }

        menuBarIconManager = MenuBarIconManager(statusItem: statusItem!)
        setupPopover()
    }

    private func setupPopover() {
        let popoverView = MenuBarPopoverView(viewModel: popoverViewModel)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 220, height: 46)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: popoverView)
        popover?.delegate = self

        logger?.log("MenuBarPopoverView setup complete", level: .debug)
    }

    // MARK: - Event Handlers
    @objc private func menuBarClicked() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover?.isShown == true { self?.closePopover() }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleTranscribeHotkeyPress() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        do {
            try audioRecorder?.startRecording()
            isRecording = true
            popoverViewModel.isRecording = true
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
        popoverViewModel.isRecording = false
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
                    self.notificationManager?.showTranscriptionError("Transcription failed: \(error.localizedDescription)")
                    self.menuBarIconManager?.showErrorState()
                }
            }
        }
    }

    private func handleTranscribedText(_ text: String, audioFileName: String? = nil) {
        logger?.log("Handling transcribed text: \(text)", level: .info)
        HistoryManager.shared.addTranscription(text, audioFileName: audioFileName)
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

    // MARK: - Window Management

    /// Public entry point used by the popover button and the SwiftUI Settings command.
    func showSettings() {
        openSettingsWindow()
    }

    private func openSettingsWindow() {
        logger?.log("Opening settings window", level: .info)
        closePopover()

        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsWindowView(settings: settingsManager)
            )
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 520, height: 480))
            settingsWindow?.center()
            settingsWindow?.delegate = self
            settingsWindowController = NSWindowController(window: settingsWindow)
        }

        NSApp.setActivationPolicy(.regular)
        settingsWindowController?.showWindow(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistoryWindow() {
        logger?.log("Opening history window", level: .info)

        if historyWindow == nil {
            let hostingController = NSHostingController(rootView: HomeTabView())
            historyWindow = NSWindow(contentViewController: hostingController)
            historyWindow?.title = "History"
            historyWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            historyWindow?.setContentSize(NSSize(width: 520, height: 500))
            historyWindow?.center()
            historyWindow?.delegate = self
            historyWindowController = NSWindowController(window: historyWindow)
        }

        NSApp.setActivationPolicy(.regular)
        historyWindowController?.showWindow(nil)
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissIfNoWindows() {
        let hasVisibleTitledWindow = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasVisibleTitledWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Window Delegate
    func windowWillClose(_ notification: Notification) {
        switch notification.object as? NSWindow {
        case historyWindow:
            historyWindow = nil
            historyWindowController = nil
        case settingsWindow:
            settingsWindow = nil
            settingsWindowController = nil
        default:
            break
        }
    }

    // MARK: - Settings Handler
    private func handleSettingsChanged() {
        logger?.log("Settings changed, swapping transcription provider", level: .info)
        hotkeyManager?.refreshHotkeyConfiguration()

        settingsManager.providerStatus = "Loading…"
        Task { [weak self] in
            guard let self else { return }
            await self.transcriptionProvider?.teardown()
            self.transcriptionProvider = TranscriptionProviderFactory.make(
                id: settingsManager.transcriptionProviderID,
                settings: settingsManager
            )
            self.startTranscriptionProvider()
        }
    }

    // MARK: - Cleanup
    private func cleanup() {
        if isRecording { _ = audioRecorder?.stopRecording() }
        Task { await transcriptionProvider?.teardown() }
        closePopover()
        historyWindow?.close()
        historyWindow = nil
        historyWindowController = nil
        settingsWindow?.close()
        settingsWindow = nil
        settingsWindowController = nil
        NotificationCenter.default.removeObserver(self)
        logger?.log("App terminating")
    }
}
