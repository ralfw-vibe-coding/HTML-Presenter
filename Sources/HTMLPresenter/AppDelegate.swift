import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let controller = PresentationController()
    private var consoleWindow: NSWindow!
    private var beamer: BeamerController!
    private var pendingURL: URL?
    private var activity: NSObjectProtocol?
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        consoleWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
        consoleWindow.title = "HTML Presenter"
        consoleWindow.minSize = NSSize(width: 900, height: 560)
        consoleWindow.isReleasedWhenClosed = false
        consoleWindow.delegate = self
        consoleWindow.contentView = NSHostingView(rootView: ConsoleView(controller: controller) { [weak self] in
            self?.openDocument(nil)
        })
        if let area = NSScreen.main?.visibleFrame {
            consoleWindow.setFrame(area.insetBy(dx: area.width * 0.04, dy: area.height * 0.04), display: false)
        }
        consoleWindow.makeKeyAndOrderFront(nil)

        beamer = BeamerController(webView: controller.beamerWeb, consoleWindow: consoleWindow)
        beamer.onDescriptionChange = { [weak self] in self?.controller.beamerDescription = $0 }
        controller.onBlackChange = { [weak self] in self?.beamer.setBlack($0) }
        controller.onStageSizeChange = { [weak self] in self?.beamer.aspect = $0 }
        controller.onTitleChange = { [weak self] title in
            self?.consoleWindow.title = title.isEmpty ? "HTML Presenter" : "\(title) – HTML Presenter"
        }
        beamer.place()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beamer.place() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) == true }
            return handled ? nil : event
        }
        // Während der Präsentation geht der Bildschirm nicht schlafen.
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                         reason: "Präsentation läuft")
        NSApp.activate(ignoringOtherApps: true)
        consoleWindow.makeKeyAndOrderFront(nil)

        if let url = pendingURL ?? Self.urlFromArguments() {
            controller.open(url)
        } else {
            openDocument(nil)
        }    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if consoleWindow == nil { pendingURL = url } else { controller.open(url) }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private static func urlFromArguments() -> URL? {
        guard let argument = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
        if argument.hasPrefix("http://") || argument.hasPrefix("https://") { return URL(string: argument) }
        return URL(fileURLWithPath: argument).standardizedFileURL
    }

    // MARK: Tastatur – gilt in Pult und Beamer, egal welches Fenster vorn ist

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === consoleWindow || event.window === beamer.window else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        // Während die Deadline eingegeben wird, gehören Ziffern und ⏎ dem Eingabefeld.
        guard !controller.isEditingDeadline else { return false }
        // Steht der Cursor in einem Eingabefeld einer Folie, tippt man dort – Esc gibt die Tastatur zurück.
        guard !controller.isTypingInSlide else { return false }
        guard controller.source != nil, !controller.slides.isEmpty else { return false }
        let c = controller
        let shift = event.modifierFlags.contains(.shift)

        switch event.specialKey {
        case .rightArrow?, .downArrow?, .pageDown?:
            shift ? c.nextSection() : c.next()
            return true
        case .leftArrow?, .upArrow?, .pageUp?:
            shift ? c.prevSection() : c.prev()
            return true
        case .home?:
            c.first()
            return true
        case .end?:
            c.last()
            return true
        case .carriageReturn?, .enter?, .newline?:
            if !c.typed.isEmpty {
                c.jumpToTyped()
            } else if c.mode == .overview, let selection = c.selection {
                c.goto(selection)
                c.selection = nil
            } else {
                c.next()
            }
            return true
        case .delete?, .backspace?:
            if !c.typed.isEmpty { c.typed.removeLast() }
            return true
        default:
            break
        }

        guard let key = event.charactersIgnoringModifiers, key.count == 1 else { return false }
        switch key {
        case " ":
            shift ? c.prev() : c.next()
        case "0"..."9":
            c.typed.append(key)
        case ".", ",":
            // Viele Presenter-Fernbedienungen schicken „.“ für Schwarzbild.
            if c.typed.isEmpty { c.isBlack.toggle() } else { c.typed.append(".") }
        case "b", "B":
            c.isBlack.toggle()
        case "\u{1b}":
            c.typed = ""
            c.selection = nil
            c.isBlack = false
        default:
            return false
        }
        return true
    }

    // MARK: Menübefehle

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "HTML-Präsentation wählen"
        panel.beginSheetModal(for: consoleWindow) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.controller.open(url) }
        }
    }

    @objc func openLocation(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Präsentation über URL öffnen"
        alert.informativeText = "Zum Beispiel eine Präsentation, die ein lokaler Server ausliefert."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "http://localhost:8000/praesentation.html"
        alert.accessoryView = field
        alert.addButton(withTitle: "Öffnen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: consoleWindow) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn,
                      let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespaces)),
                      url.scheme != nil else { return }
                self?.controller.open(url)
            }
        }
    }

    @objc func reloadPresentation(_ sender: Any?) { controller.reload() }
    @objc func showSpeaker(_ sender: Any?) { controller.mode = .speaker }
    @objc func showOverview(_ sender: Any?) { controller.mode = .overview }
    @objc func showMirror(_ sender: Any?) { controller.mode = .mirror }
    @objc func biggerNotes(_ sender: Any?) { controller.notesFontSize = min(48, controller.notesFontSize + 2) }
    @objc func smallerNotes(_ sender: Any?) { controller.notesFontSize = max(14, controller.notesFontSize - 2) }
    @objc func toggleBlack(_ sender: Any?) { controller.isBlack.toggle() }
    @objc func cycleBeamerScreen(_ sender: Any?) { beamer.cycleScreen() }
    @objc func resetTimer(_ sender: Any?) { controller.restartTimer() }

    @objc func toggleMirrorBar(_ sender: Any?) {
        if controller.mode == .mirror {
            controller.hideBarInMirror.toggle()
        } else {
            controller.mode = .mirror
            controller.hideBarInMirror = true
        }
    }

    @objc func editDeadline(_ sender: Any?) {
        controller.isEditingDeadline = true
    }
    @objc func toggleTimer(_ sender: Any?) { controller.toggleTimer() }

    @objc func showShortcuts(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Tastenkürzel"
        alert.informativeText = """
        →  Leertaste  Bild↓   nächste Folie
        ←  Bild↑                    vorige Folie
        ⇧→                           nächste Rückgrat-Folie
        ⇧←                           zur eigenen / vorigen Rückgrat-Folie
        Pos1 / Ende               erste / letzte Folie
        4.2.1 ⏎                     zu Folie 4.2.1 springen
        B  oder  .                   Beamer schwarz
        esc                            Eingabe abbrechen, Schwarzbild aus

        ⌘1 / ⌘2 / ⌘3              Referent / Übersicht / Spiegel
        ⌥⌘T                          Spiegel ohne Kopfleiste ein/aus
        ⌘+ / ⌘−                    Notizen größer / kleiner
        ⇧⌘B                         Beamer-Bildschirm wechseln
        ⇧⌘D                         Deadline festlegen
        ⌘R                            neu laden (passiert auch beim Speichern)
        """
        alert.beginSheetModal(for: consoleWindow)
    }
}
