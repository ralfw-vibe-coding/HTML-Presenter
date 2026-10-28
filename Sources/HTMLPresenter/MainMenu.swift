import AppKit

/// Menüleiste, von Hand gebaut (es gibt kein Storyboard). Die Befehle landen über die
/// Responder-Kette beim AppDelegate.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let bar = NSMenu()

        bar.addSubmenu("HTML Presenter") {
            $0.item("Über HTML Presenter", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            $0.addItem(.separator())
            $0.item("HTML Presenter ausblenden", #selector(NSApplication.hide(_:)), "h")
            $0.item("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            $0.item("Alle einblenden", #selector(NSApplication.unhideAllApplications(_:)))
            $0.addItem(.separator())
            $0.item("HTML Presenter beenden", #selector(NSApplication.terminate(_:)), "q")
        }

        bar.addSubmenu("Ablage") {
            $0.item("Öffnen …", #selector(AppDelegate.openDocument(_:)), "o")
            $0.item("URL öffnen …", #selector(AppDelegate.openLocation(_:)), "l")
            $0.item("Neu laden", #selector(AppDelegate.reloadPresentation(_:)), "r")
            $0.addItem(.separator())
            $0.item("Schließen", #selector(NSWindow.performClose(_:)), "w")
        }

        bar.addSubmenu("Bearbeiten") {
            $0.item("Kopieren", #selector(NSText.copy(_:)), "c")
            $0.item("Einsetzen", #selector(NSText.paste(_:)), "v")
            $0.item("Alles auswählen", #selector(NSText.selectAll(_:)), "a")
        }

        bar.addSubmenu("Darstellung") {
            $0.item("Referent", #selector(AppDelegate.showSpeaker(_:)), "1")
            $0.item("Übersicht", #selector(AppDelegate.showOverview(_:)), "2")
            $0.item("Spiegel", #selector(AppDelegate.showMirror(_:)), "3")
            $0.item("Spiegel ohne Kopfleiste ein/aus", #selector(AppDelegate.toggleMirrorBar(_:)), "t", [.command, .option])
            $0.addItem(.separator())
            $0.item("Notizen größer", #selector(AppDelegate.biggerNotes(_:)), "+")
            $0.item("Notizen kleiner", #selector(AppDelegate.smallerNotes(_:)), "-")
            $0.addItem(.separator())
            $0.item("Vollbild", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }

        bar.addSubmenu("Präsentation") {
            $0.item("Beamer schwarz (B)", #selector(AppDelegate.toggleBlack(_:)))
            $0.item("Beamer-Bildschirm wechseln", #selector(AppDelegate.cycleBeamerScreen(_:)), "b", [.command, .shift])
            $0.addItem(.separator())
            $0.item("Deadline festlegen …", #selector(AppDelegate.editDeadline(_:)), "d", [.command, .shift])
            $0.item("Timer anhalten / fortsetzen", #selector(AppDelegate.toggleTimer(_:)), "p", [.command, .shift])
            $0.item("Timer zurücksetzen", #selector(AppDelegate.resetTimer(_:)), "t", [.command, .shift])
        }

        let windowMenu = bar.addSubmenu("Fenster") {
            $0.item("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m")
        }
        NSApp.windowsMenu = windowMenu

        bar.addSubmenu("Hilfe") {
            $0.item("Präsentationsschema kopieren (für KI)", #selector(AppDelegate.copySchema(_:)))
            $0.addItem(.separator())
            $0.item("Tastenkürzel", #selector(AppDelegate.showShortcuts(_:)), "?")
        }
        return bar
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ fill: (NSMenu) -> Void) -> NSMenu {
        let menu = NSMenu(title: title)
        fill(menu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        addItem(item)
        return menu
    }

    func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        addItem(item)
    }
}
