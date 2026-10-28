import AppKit
import WebKit

/// Das Fenster für das Publikum: randlos im Vollbild auf einem zweiten Bildschirm,
/// oder – wenn keiner da ist – als verschiebbares Probefenster.
@MainActor
final class BeamerController {
    enum Placement: Equatable {
        case automatic
        case probe
        case screen(CGDirectDisplayID)
    }

    let window: NSWindow
    var aspect = CGSize(width: 16, height: 9) {
        didSet { if isProbe { window.contentAspectRatio = aspect } }
    }
    var onDescriptionChange: ((String) -> Void)?

    private weak var consoleWindow: NSWindow?
    private let blackout = NSView()
    private var choice: Placement = .automatic
    private var isProbe = false
    private var probeFrame: NSRect?

    init(webView: WKWebView, consoleWindow: NSWindow) {
        self.consoleWindow = consoleWindow
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isExcludedFromWindowsMenu = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        blackout.wantsLayer = true
        blackout.layer?.backgroundColor = NSColor.black.cgColor
        blackout.frame = container.bounds
        blackout.autoresizingMask = [.width, .height]
        blackout.isHidden = true
        container.addSubview(blackout)

        window.contentView = container
    }

    func setBlack(_ black: Bool) {
        blackout.isHidden = !black
    }

    /// Bildschirme, die als Beamer infrage kommen: alle außer dem, auf dem das Pult steht.
    private var candidates: [NSScreen] {
        let consoleScreen = consoleWindow?.screen ?? NSScreen.main
        return NSScreen.screens.filter { $0 != consoleScreen }
    }

    /// Wählt den Bildschirm neu – beim Start und immer, wenn Bildschirme an- oder abgesteckt werden.
    func place() {
        let options = candidates
        var target: NSScreen?
        switch choice {
        case .automatic: target = options.first
        case .probe: target = nil
        case .screen(let id): target = options.first { $0.displayID == id } ?? options.first
        }
        if let target { show(on: target) } else { showProbe() }
    }

    /// Schaltet reihum durch alle anderen Bildschirme und das Probefenster.
    func cycleScreen() {
        let order: [Placement] = candidates.map { .screen($0.displayID) } + [.probe]
        let now: Placement = isProbe ? .probe : .screen(window.screen?.displayID ?? 0)
        let position = order.firstIndex(of: now) ?? -1
        choice = order[(position + 1) % order.count]
        place()
    }

    private func show(on screen: NSScreen) {
        if isProbe { probeFrame = window.frame }
        isProbe = false
        window.styleMask = [.borderless]
        window.contentAspectRatio = .zero
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        onDescriptionChange?("Beamer: \(screen.localizedName)")
    }

    private func showProbe() {
        let wasProbe = isProbe
        isProbe = true
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.title = "Beamer – Probefenster"
        window.level = .floating
        window.collectionBehavior = []
        window.hasShadow = true
        window.contentAspectRatio = aspect
        if !wasProbe {
            let area = (consoleWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let width = min(640, area.width * 0.4)
            let content = NSRect(x: 0, y: 0, width: width, height: width * aspect.height / aspect.width)
            var frame = probeFrame ?? window.frameRect(forContentRect: content)
            if probeFrame == nil {
                frame.origin = NSPoint(x: area.maxX - frame.width - 24, y: area.maxY - frame.height - 24)
            }
            window.setFrame(frame, display: true)
        }
        window.orderFront(nil)
        onDescriptionChange?("Beamer: Probefenster (kein zweiter Bildschirm)")
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
