import AppKit
import Observation
import WebKit

/// Die eine Wahrheit über die laufende Präsentation: welche Datei, welche Folien, welche ist aktuell.
/// Beamer und Pult zeigen nur an, was hier steht.
@MainActor
@Observable
final class PresentationController {
    private(set) var source: URL?
    private(set) var documentTitle = ""
    private(set) var slides: [Slide] = []
    private(set) var current = 0
    private(set) var currentStep = 0
    /// Steht der Cursor in einem Eingabefeld einer Folie? Dann gehören die Tasten der Folie.
    private(set) var isTypingInSlide = false
    private(set) var thumbnails: [Int: NSImage] = [:]
    private(set) var stageSize = CGSize(width: 1600, height: 900)
    private(set) var problem: String?
    private(set) var timerStart = Date()
    private(set) var timerPausedAt: Date?

    var mode: ConsoleMode = .speaker
    var selection: Int?
    var typed = ""
    var notesFontSize: CGFloat = 22
    var beamerDescription = ""
    var hideBarInMirror = false
    var overviewCardWidth: CGFloat = 220
    var isEditingDeadline = false
    var deadline: Date? {
        didSet { prepareWarnings() }
    }
    private(set) var warning: DeadlineWarning?
    var isBlack = false {
        didSet { onBlackChange?(isBlack) }
    }

    @ObservationIgnored let beamerWeb: WKWebView
    @ObservationIgnored let liveWeb: WKWebView
    @ObservationIgnored let snapshotWeb: WKWebView
    @ObservationIgnored var onBlackChange: ((Bool) -> Void)?
    @ObservationIgnored var onStageSizeChange: ((CGSize) -> Void)?
    @ObservationIgnored var onTitleChange: ((String) -> Void)?
    @ObservationIgnored private let bridges: [ScriptBridge]
    @ObservationIgnored private let snapshotWindow: NSWindow
    @ObservationIgnored private var snapshotGeneration = 0
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var lastModified: Date?
    @ObservationIgnored private var notesCache: [String: NSAttributedString] = [:]
    @ObservationIgnored private var passedWarnings: Set<Int> = []
    @ObservationIgnored private var clockTimer: Timer?

    init() {
        let runtime = Self.loadRuntime()
        let beamerBridge = ScriptBridge(mode: .beamer)
        let liveBridge = ScriptBridge(mode: .presenter)
        let snapshotBridge = ScriptBridge(mode: .snapshot)
        beamerWeb = SlideWebView.make(mode: .beamer, runtime: runtime, bridge: beamerBridge)
        liveWeb = SlideWebView.make(mode: .presenter, runtime: runtime, bridge: liveBridge)
        snapshotWeb = SlideWebView.make(mode: .snapshot, runtime: runtime, bridge: snapshotBridge)
        bridges = [beamerBridge, liveBridge, snapshotBridge]

        // Die Miniaturen entstehen in einem Fenster weit außerhalb jedes Bildschirms.
        snapshotWindow = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 1600, height: 900),
                                  styleMask: .borderless, backing: .buffered, defer: false)
        snapshotWindow.isReleasedWhenClosed = false
        snapshotWindow.ignoresMouseEvents = true
        snapshotWindow.isExcludedFromWindowsMenu = true
        snapshotWindow.contentView = snapshotWeb

        bridges.forEach { $0.controller = self }
        if runtime == nil { problem = "Die Laufzeit presentation.js wurde nicht gefunden." }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDeadline() }
        }
    }

    // MARK: Öffnen und Neuladen

    func open(_ url: URL) {
        source = url
        current = 0
        currentStep = 0
        isTypingInSlide = false
        slides = []
        thumbnails = [:]
        notesCache = [:]
        selection = nil
        typed = ""
        problem = nil
        isBlack = false
        restartTimer()
        snapshotWindow.orderFrontRegardless()
        for web in [beamerWeb, liveWeb, snapshotWeb] { load(url, into: web) }
        if url.isFileURL { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        startWatching()
    }

    func reload() {
        guard let source else { return }
        thumbnails = [:]
        notesCache = [:]
        problem = nil
        for web in [beamerWeb, liveWeb, snapshotWeb] { load(source, into: web) }
    }

    private func load(_ url: URL, into web: WKWebView) {
        if url.isFileURL {
            // Lesezugriff aufs ganze Dateisystem, damit z. B. ../runtime/presentation.js erreichbar ist.
            web.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            web.load(URLRequest(url: url))
        }
    }

    private static func loadRuntime() -> String? {
        resourceText("presentation.js", projectPath: "runtime/presentation.js")
    }

    /// Text einer Datei aus dem App-Bündel – oder, beim Start per `swift run`, aus dem Projektordner.
    static func resourceText(_ name: String, projectPath: String) -> String? {
        let url = URL(fileURLWithPath: name)
        let bundled = Bundle.main.url(forResource: url.deletingPathExtension().lastPathComponent, withExtension: url.pathExtension)
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(projectPath)
        return [bundled, project].compactMap { $0 }.lazy.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first
    }

    // MARK: Hinweise im Pult

    /// Kurze Bestätigung, die nach ein paar Sekunden von selbst verschwindet.
    private(set) var toast: String?

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            MainActor.assumeIsolated {
                if self?.toast == text { self?.toast = nil }
            }
        }
    }

    /// Legt SCHEMA.md in die Zwischenablage, z. B. um sie einer KI vorzulegen.
    func copySchemaToPasteboard() {
        guard let schema = Self.resourceText("SCHEMA.md", projectPath: "SCHEMA.md") else {
            NSSound.beep()
            showToast("Schema nicht gefunden")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(schema, forType: .string)
        showToast("Präsentationsschema in der Zwischenablage")
    }

    // MARK: Nachrichten der Laufzeit

    func receive(_ body: [String: Any], from mode: WebMode) {
        switch body["type"] as? String {
        case "ready":
            let list = (body["slides"] as? [[String: Any]] ?? []).compactMap(Slide.init)
            if list != slides { slides = list }
            if let size = body["size"] as? [String: Any],
               let width = size["width"] as? Double, let height = size["height"] as? Double,
               CGSize(width: width, height: height) != stageSize {
                stageSize = CGSize(width: width, height: height)
                onStageSizeChange?(stageSize)
            }
            problem = list.isEmpty ? "Keine Folien gefunden. Folien brauchen das Attribut data-slide (siehe SCHEMA.md)." : nil
            current = min(current, max(0, list.count - 1))
            currentStep = min(currentStep, list.indices.contains(current) ? list[current].steps : 0)
            switch mode {
            case .beamer:
                documentTitle = body["title"] as? String ?? beamerWeb.title ?? ""
                onTitleChange?(documentTitle)
                push(to: beamerWeb)
            case .presenter:
                push(to: liveWeb)
            case .snapshot:
                makeThumbnails()
            }
        case "change":
            // Die Miniaturen-WebView blättert nur für Fotos, das ist kein Folienwechsel.
            guard mode != .snapshot, let index = body["index"] as? Int else { return }
            goto(index, step: body["step"] as? Int ?? 0)
        case "action":
            guard mode != .snapshot, let name = body["name"] as? String else { return }
            relayAction(name, detail: body["detail"] ?? NSNull(), from: mode)
        case "typing":
            guard mode != .snapshot else { return }
            isTypingInSlide = body["active"] as? Bool ?? false
        default:
            break
        }
    }

    /// Eine Aktion aus einem Fenster (z. B. „Timer starten“) läuft auch im jeweils anderen ab.
    private func relayAction(_ name: String, detail: Any, from mode: WebMode) {
        let targets = mode == .beamer ? [liveWeb] : [beamerWeb]
        for web in targets {
            web.callAsyncJavaScript("window.presentation && presentation.receiveAction(name, detail); return true;",
                                    arguments: ["name": name, "detail": detail], in: nil, in: .page, completionHandler: nil)
        }
    }

    func loadFailed(_ error: Error, in mode: WebMode) {
        guard mode == .beamer, (error as NSError).code != NSURLErrorCancelled else { return }
        problem = "Die Präsentation konnte nicht geladen werden: \(error.localizedDescription)"
    }

    // MARK: Navigation

    var currentSlide: Slide? { slides.indices.contains(current) ? slides[current] : nil }
    var nextSlide: Slide? { slides.indices.contains(current + 1) ? slides[current + 1] : nil }

    /// Zeigt Folie `index` mit `step` Einblendungen (Int.max = alle) auf Beamer und Pult.
    func goto(_ index: Int, step: Int = 0) {
        guard slides.indices.contains(index) else { return }
        current = index
        currentStep = min(max(0, step), slides[index].steps)
        typed = ""
        push(to: beamerWeb)
        push(to: liveWeb)
    }

    /// Erst die Einblendungen der Folie, dann die nächste Folie.
    func next() {
        if let slide = currentSlide, currentStep < slide.steps { goto(current, step: currentStep + 1) } else { goto(current + 1) }
    }

    func prev() {
        if currentStep > 0 { goto(current, step: currentStep - 1) } else { goto(current - 1, step: .max) }
    }
    func first() { goto(0) }
    func last() { goto(slides.count - 1) }

    func nextSection() {
        if let index = slides.firstIndex(where: { $0.index > current && $0.level == 1 }) { goto(index) }
    }

    func prevSection() {
        guard let slide = currentSlide else { return }
        if slide.level > 1 {
            goto(section(of: current))
        } else if let index = slides[..<current].lastIndex(where: { $0.level == 1 }) {
            goto(index)
        }
    }

    /// Springt zur eingetippten Nummer („4.2.1“); gibt es die nicht, gilt sie als laufende Position.
    func jumpToTyped() {
        defer { typed = "" }
        if let slide = slides.first(where: { $0.number == typed }) {
            goto(slide.index)
        } else if let position = Int(typed), slides.indices.contains(position - 1) {
            goto(position - 1)
        } else {
            NSSound.beep()
        }
    }

    private func push(to web: WKWebView) {
        web.evaluateJavaScript("window.presentation && presentation.goto(\(current), \(currentStep))", completionHandler: nil)
    }

    // MARK: Übersicht

    static let overviewCardWidths: ClosedRange<CGFloat> = 120...640

    func zoomOverview(by factor: CGFloat) {
        setOverviewCardWidth(overviewCardWidth * factor)
    }

    func setOverviewCardWidth(_ width: CGFloat) {
        overviewCardWidth = min(Self.overviewCardWidths.upperBound, max(Self.overviewCardWidths.lowerBound, width))
    }

    // MARK: Gliederung

    func section(of index: Int) -> Int {
        var k = index
        while let parent = slides[k].parent { k = parent }
        return k
    }

    /// Rückgrat-Folien mit allen ihren Unterfolien, in Dokumentreihenfolge.
    var sections: [[Slide]] {
        var result: [[Slide]] = []
        for slide in slides {
            if slide.level == 1 || result.isEmpty { result.append([slide]) } else { result[result.count - 1].append(slide) }
        }
        return result
    }

    /// Titel der aktuellen Folie und aller übergeordneten Folien, vom Rückgrat aus.
    var path: [Slide] {
        guard var slide = currentSlide else { return [] }
        var result = [slide]
        while let parent = slide.parent {
            slide = slides[parent]
            result.insert(slide, at: 0)
        }
        return result
    }

    // MARK: Timer

    func restartTimer() {
        timerStart = Date()
        timerPausedAt = nil
    }

    func toggleTimer() {
        if let pausedAt = timerPausedAt {
            timerStart += Date().timeIntervalSince(pausedAt)
            timerPausedAt = nil
        } else {
            timerPausedAt = Date()
        }
    }

    func elapsed(at now: Date) -> TimeInterval {
        (timerPausedAt ?? now).timeIntervalSince(timerStart)
    }

    // MARK: Deadline

    /// Minuten vor der Deadline, zu denen das Pult warnt; 0 = Zeit ist um.
    static let warningMinutes = [10, 5, 1, 0]

    func remaining(at now: Date) -> TimeInterval? {
        deadline.map { $0.timeIntervalSince(now) }
    }

    func dismissWarning() {
        warning = nil
    }

    private func prepareWarnings() {
        warning = nil
        passedWarnings = []
        guard let deadline else { return }
        // Schwellen, die beim Festlegen schon unterschritten sind, melden sich nicht nachträglich.
        let left = deadline.timeIntervalSinceNow
        passedWarnings = Set(Self.warningMinutes.filter { left <= Double($0 * 60) })
    }

    private func checkDeadline() {
        guard let left = remaining(at: Date()) else { return }
        let due = Self.warningMinutes.filter { !passedWarnings.contains($0) && left <= Double($0 * 60) }
        guard let minutes = due.min() else { return }
        passedWarnings.formUnion(due)
        let shown = DeadlineWarning(minutes: minutes)
        warning = shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            MainActor.assumeIsolated {
                if self?.warning == shown { self?.warning = nil }
            }
        }
    }

    // MARK: Notizen

    /// Schriftgröße für Notizen, die nur zur Orientierung dienen (nächste Folie).
    var smallNotesFontSize: CGFloat { max(12, (notesFontSize * 0.68).rounded()) }

    func notes(for index: Int, size: CGFloat? = nil, dimmed: Bool = false) -> NSAttributedString {
        guard slides.indices.contains(index) else { return NSAttributedString() }
        let html = slides[index].notes
        let fontSize = size ?? notesFontSize
        let key = "\(fontSize)|\(dimmed)|\(html)"
        if let cached = notesCache[key] { return cached }

        let text: NSAttributedString
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = NSAttributedString(string: "Keine Notizen zu dieser Folie.", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(white: 0.45, alpha: 1)
            ])
        } else {
            let page = """
            <html><head><meta charset="utf-8"><style>
            body { font-family: -apple-system, 'Helvetica Neue', sans-serif; font-size: \(Int(fontSize))px; line-height: 1.4; color: \(dimmed ? "#9C9C9C" : "#E6E6E6"); }
            strong, b { color: \(dimmed ? "#C4C4C4" : "#FFFFFF"); }
            code { font-family: Menlo, monospace; font-size: 0.85em; color: #F2C47E; }
            p { margin: 0 0 0.6em; }
            li { margin-bottom: 0.3em; }
            </style></head><body>\(html)</body></html>
            """
            text = (try? NSAttributedString(
                data: Data(page.utf8),
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)) ?? NSAttributedString(string: html)
        }
        notesCache[key] = text
        return text
    }

    // MARK: Miniaturen

    private func makeThumbnails() {
        snapshotGeneration += 1
        let generation = snapshotGeneration
        let count = slides.count
        snapshotWindow.setContentSize(stageSize)
        Task { @MainActor in
            for index in 0..<count {
                guard generation == snapshotGeneration else { return }
                do {
                    _ = try await snapshotWeb.callAsyncJavaScript(
                        "presentation.goto(i); await document.fonts.ready; await new Promise(r => setTimeout(r, 60)); return true;",
                        arguments: ["i": index], in: nil, contentWorld: .page)
                    let config = WKSnapshotConfiguration()
                    config.snapshotWidth = 640
                    let image = try await snapshotWeb.takeSnapshot(configuration: config)
                    guard generation == snapshotGeneration else { return }
                    thumbnails[index] = image
                } catch {
                    NSLog("Miniatur %d fehlgeschlagen: %@", index, error.localizedDescription)
                }
            }
        }
    }

    // MARK: Datei beobachten

    private func startWatching() {
        watchTimer?.invalidate()
        guard let source, source.isFileURL else { return }
        lastModified = Self.modificationDate(of: source)
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChanged() }
        }
    }

    private func reloadIfChanged() {
        guard let source, let date = Self.modificationDate(of: source), date != lastModified else { return }
        lastModified = date
        reload()
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
