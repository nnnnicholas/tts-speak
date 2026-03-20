import AppKit
import Darwin
import Foundation

enum StatusUI: String {
    case menubar
    case floating
}

final class TTSStatusController: NSObject, NSApplicationDelegate {
    private let targetPID: pid_t
    private let stateFile: String
    private let ui: StatusUI
    private var statusItem: NSStatusItem?
    private var floatingPanel: NSPanel?
    private var floatingButton: NSButton?
    private var floatingBackgroundView: NSVisualEffectView?
    private var timer: Timer?

    init(targetPID: pid_t, stateFile: String, ui: StatusUI) {
        self.targetPID = targetPID
        self.stateFile = stateFile
        self.ui = ui
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        switch ui {
        case .menubar:
            setupStatusItem()
        case .floating:
            setupFloatingPanel()
        }
        refreshUI()

        timer = Timer.scheduledTimer(timeInterval: 0.4, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    @objc private func tick() {
        guard processIsAlive(targetPID) else {
            NSApp.terminate(nil)
            return
        }

        refreshUI()
    }

    @objc private func stopTTS() {
        kill(targetPID, SIGTERM)
    }

    private func currentState() -> String {
        let rawState = try? String(contentsOfFile: stateFile, encoding: .utf8)
        return rawState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "active"
    }

    private func labels(for state: String) -> (title: String, toolTip: String) {
        switch state {
        case "processing":
            return ("Stop", "TTS is generating audio. Click to stop.")
        case "playing":
            return ("Stop", "TTS is speaking. Click to stop.")
        default:
            return ("Stop", "Click to stop text-to-speech.")
        }
    }

    private func refreshUI() {
        let state = currentState()
        let labels = labels(for: state)

        if let button = statusItem?.button {
            button.toolTip = labels.toolTip
        }

        if let button = floatingButton {
            button.title = labels.title
            button.toolTip = labels.toolTip
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: state == "playing" ? "stop.circle.fill" : "waveform.circle.fill", accessibilityDescription: labels.title)
            }
        }

        if let backgroundView = floatingBackgroundView {
            backgroundView.toolTip = labels.toolTip
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            NSApp.terminate(nil)
            return
        }

        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop TTS")
        } else {
            button.title = "Stop"
        }

        button.target = self
        button.action = #selector(stopTTS)
        button.sendAction(on: [.leftMouseUp])
    }

    private func setupFloatingPanel() {
        guard let screenFrame = screenFrame() else {
            setupStatusItem()
            return
        }

        let panelWidth: CGFloat = 116
        let panelHeight: CGFloat = 34
        let panelRect = NSRect(
            x: screenFrame.maxX - panelWidth - 12,
            y: screenFrame.maxY - panelHeight - 8,
            width: panelWidth,
            height: panelHeight
        )

        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        let backgroundView = NSVisualEffectView(frame: contentView.bounds)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = panelHeight / 2
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.borderWidth = 1
        backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let button = NSButton(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        button.isBordered = false
        button.focusRingType = .none
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = #selector(stopTTS)
        button.contentTintColor = .white
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true

        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Stop TTS")
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = .white
        }

        backgroundView.addSubview(button)
        contentView.addSubview(backgroundView)
        panel.contentView = contentView
        panel.orderFrontRegardless()

        floatingPanel = panel
        floatingButton = button
        floatingBackgroundView = backgroundView
    }

    private func screenFrame() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        if let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return activeScreen.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
    }

    private func processIsAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }
}

func parseArguments() -> (pid: pid_t, stateFile: String, ui: StatusUI)? {
    var pidValue: pid_t?
    var stateFile: String?
    var ui: StatusUI = .menubar
    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--pid":
            guard let value = iterator.next(), let intValue = Int32(value) else { return nil }
            pidValue = intValue
        case "--state-file":
            guard let value = iterator.next() else { return nil }
            stateFile = value
        case "--ui":
            guard let value = iterator.next(), let parsedUI = StatusUI(rawValue: value) else { return nil }
            ui = parsedUI
        default:
            return nil
        }
    }

    guard let pidValue, let stateFile else { return nil }
    return (pidValue, stateFile, ui)
}

guard let arguments = parseArguments() else {
    fputs("usage: tts-speak-status --pid <pid> --state-file <path> [--ui menubar|floating]\n", stderr)
    exit(2)
}

let app = NSApplication.shared
let delegate = TTSStatusController(targetPID: arguments.pid, stateFile: arguments.stateFile, ui: arguments.ui)
app.delegate = delegate
app.run()
