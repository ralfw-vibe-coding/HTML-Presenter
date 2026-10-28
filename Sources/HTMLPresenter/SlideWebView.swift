import WebKit

/// Wofür eine WebView da ist. Der Wert landet als `data-presentation-mode` im Dokument.
enum WebMode: String {
    case beamer, presenter, snapshot
}

/// Empfängt Nachrichten der Laufzeit (`webkit.messageHandlers.presenter`) und Ladefehler.
@MainActor
final class ScriptBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let mode: WebMode
    weak var controller: PresentationController?

    init(mode: WebMode) {
        self.mode = mode
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        controller?.receive(body, from: mode)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        controller?.loadFailed(error, in: mode)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        controller?.loadFailed(error, in: mode)
    }
}

@MainActor
enum SlideWebView {
    static func make(mode: WebMode, runtime: String?, bridge: ScriptBridge) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Auch unsichtbare WebViews (Miniaturen) sollen weiterrechnen und zeichnen.
        config.preferences.inactiveSchedulingPolicy = .none
        config.mediaTypesRequiringUserActionForPlayback = []

        let scripts = config.userContentController
        scripts.addUserScript(WKUserScript(
            source: "document.documentElement.dataset.presentationMode = '\(mode.rawValue)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if mode != .beamer {
            // Ton kommt nur vom Beamer, sonst laufen Videos doppelt hörbar.
            scripts.addUserScript(WKUserScript(
                source: "document.addEventListener('play', e => { e.target.muted = true; }, true);",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let runtime {
            // Hat die Seite die Laufzeit schon selbst geladen, tut diese Kopie nichts.
            scripts.addUserScript(WKUserScript(source: runtime, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        scripts.add(bridge, name: "presenter")

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1600, height: 900), configuration: config)
        web.navigationDelegate = bridge
        web.isInspectable = true
        return web
    }
}
