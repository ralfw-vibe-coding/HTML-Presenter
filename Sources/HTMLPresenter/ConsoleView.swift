import SwiftUI
import WebKit

extension Color {
    static let consoleBackground = Color(white: 0.085)
    static let consolePanel = Color(white: 0.14)
    static let consoleAccent = Color(red: 0.96, green: 0.63, blue: 0.22)
    /// Ausgewählte Folie in der Übersicht – das Türkis aus dem App-Symbol.
    static let consoleSelection = Color(red: 0.33, green: 0.80, blue: 0.84)
}

/// Das Pult auf dem Mac: Kopfleiste plus eine von drei Ansichten.
struct ConsoleView: View {
    @Bindable var controller: PresentationController
    let onOpen: () -> Void

    /// Spiegel ohne Kopfleiste: Das Pult darf dann selbst gezeigt werden, also keine privaten Einblendungen.
    private var isPresentingMirror: Bool {
        controller.mode == .mirror && controller.hideBarInMirror
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isPresentingMirror {
                TopBar(controller: controller)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.consoleBackground)
        .overlay {
            if !controller.typed.isEmpty && !isPresentingMirror {
                JumpOverlay(typed: controller.typed)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = controller.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.ultraThickMaterial, in: Capsule())
                    .padding(.bottom, 28)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controller.toast)
        .overlay(alignment: .top) {
            if let warning = controller.warning, !isPresentingMirror {
                WarningBanner(warning: warning) { controller.dismissWarning() }
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPresentingMirror {
                // Gleicher Platz wie in der Kopfleiste, damit der Knopf beim Umschalten nicht springt.
                BarToggle(barVisible: false) { controller.hideBarInMirror = false }
                    .frame(height: TopBar.height)
                    .padding(.trailing, TopBar.sidePadding)
            }
        }
        .sheet(isPresented: $controller.isEditingDeadline) {
            DeadlineEditor(controller: controller)
        }
        .animation(.easeOut(duration: 0.25), value: controller.warning)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if controller.source == nil {
            EmptyState(onOpen: onOpen, onCopySchema: controller.copySchemaToPasteboard)
        } else if let problem = controller.problem {
            Text(problem)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(40)
        } else {
            switch controller.mode {
            case .speaker: SpeakerView(controller: controller)
            case .overview: OverviewView(controller: controller)
            case .mirror: MirrorView(controller: controller, presenting: isPresentingMirror)
            }
        }
    }
}

// MARK: - Kopfleiste

private struct TopBar: View {
    @Bindable var controller: PresentationController

    static let height: CGFloat = 50
    static let sidePadding: CGFloat = 18

    var body: some View {
        HStack(spacing: 18) {
            Picker("Ansicht", selection: $controller.mode) {
                ForEach(ConsoleMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            if let slide = controller.currentSlide {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(slide.number)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.consoleAccent)
                    Text("\(controller.current + 1) / \(controller.slides.count)")
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if slide.steps > 0 {
                        Text("Schritt \(controller.currentStep) / \(slide.steps)")
                            .font(.system(size: 14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(controller.currentStep < slide.steps ? Color.consoleSelection : Color.secondary)
                    }
                }
            }

            if controller.mode == .overview {
                HStack(spacing: 2) {
                    Button { controller.zoomOverview(by: 1 / 1.25) } label: { Image(systemName: "minus") }
                        .help("Miniaturen kleiner (auch per Trackpad zusammenziehen)")
                    Button { controller.zoomOverview(by: 1.25) } label: { Image(systemName: "plus") }
                        .help("Miniaturen größer (auch per Trackpad aufziehen)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            if controller.isBlack {
                Label("Beamer schwarz", systemImage: "rectangle.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.75)))
            }

            Text(controller.beamerDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 16) {
                    Button { controller.toggleTimer() } label: {
                        Text(Self.format(controller.elapsed(at: context.date)))
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(controller.timerPausedAt == nil ? Color.primary : Color.consoleAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Vortragsdauer – Klick: anhalten oder fortsetzen")

                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 22, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .help("Uhrzeit")

                    Button { controller.isEditingDeadline = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 15, weight: .medium))
                            if let deadline = controller.deadline {
                                Text(deadline, format: .dateTime.hour().minute())
                                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .help(controller.deadline == nil ? "Deadline festlegen" : "Deadline ändern")

                    if let left = controller.remaining(at: context.date) {
                        Text(Self.remainingText(left))
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Self.remainingColor(left))
                            .help("Restzeit bis zur Deadline")
                    }
                }
            }

            if controller.mode == .mirror {
                BarToggle(barVisible: true) { controller.hideBarInMirror = true }
            }
        }
        .padding(.horizontal, Self.sidePadding)
        .frame(height: Self.height)
        .background(Color(white: 0.12))
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    static func remainingText(_ left: TimeInterval) -> String {
        let total = Int(abs(left).rounded(.down))
        let clock = String(format: "%d:%02d", total / 60, total % 60)
        return left >= 0 ? "−\(clock)" : "+\(clock)"
    }

    static func remainingColor(_ left: TimeInterval) -> Color {
        switch left {
        case ..<60: .red
        case ..<300: .orange
        case ..<600: .yellow
        default: .primary
        }
    }
}

private struct DeadlineEditor: View {
    @Bindable var controller: PresentationController
    @State private var end = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Deadline", systemImage: "hourglass").font(.title3.bold())
            Text("Das Pult warnt 10, 5 und 1 Minute vorher und bei Ablauf – nur hier, nie auf dem Beamer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Ende um")
                DatePicker("Ende um", selection: $end, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                Text("Uhr")
                Spacer()
                Button("Festlegen") { apply(Self.upcoming(end)) }
                    .keyboardShortcut(.defaultAction)
            }

            HStack {
                Text("oder in")
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes)") { apply(Date().addingTimeInterval(Double(minutes * 60))) }
                }
                Text("Min.")
            }

            Divider()

            HStack {
                if let deadline = controller.deadline {
                    Text("Aktuell: \(deadline.formatted(date: .omitted, time: .shortened)) Uhr")
                    Button("Entfernen") {
                        controller.deadline = nil
                        controller.isEditingDeadline = false
                    }
                } else {
                    Text("Keine Deadline gesetzt").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen") { controller.isEditingDeadline = false }
                    .keyboardShortcut(.cancelAction)
            }

            HStack {
                Text("Vortragsdauer")
                Spacer()
                Button(controller.timerPausedAt == nil ? "Anhalten" : "Fortsetzen") { controller.toggleTimer() }
                Button("Auf 0 setzen") { controller.restartTimer() }
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear { end = controller.deadline ?? Date().addingTimeInterval(45 * 60) }
    }

    private func apply(_ date: Date) {
        controller.deadline = date
        controller.isEditingDeadline = false
    }

    /// Eine Uhrzeit, die heute schon vorbei ist, meint morgen.
    private static func upcoming(_ time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let today = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: Date()) ?? time
        return today < Date().addingTimeInterval(-3600) ? today.addingTimeInterval(86_400) : today
    }
}

private struct WarningBanner: View {
    let warning: DeadlineWarning
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: warning.minutes == 0 ? "alarm.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 30))
            Text(warning.text)
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .foregroundStyle(warning.minutes > 5 ? Color.black : Color.white)
        .padding(.horizontal, 34).padding(.vertical, 18)
        .background(color, in: Capsule())
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .onTapGesture(perform: onDismiss)
        .help("Klick: ausblenden")
    }

    private var color: Color {
        switch warning.minutes {
        case 0, 1: .red
        case 5: .orange
        default: .yellow
        }
    }
}

// MARK: - Referent: aktuelle Folie mit Notizen, daneben die nächste

private struct SpeakerView: View {
    @Bindable var controller: PresentationController

    var body: some View {
        GeometryReader { geo in
            let column = geo.size.width * 0.62
            let ratio = controller.stageSize.height / controller.stageSize.width
            // So breit wie die Spalte, aber höchstens 62 % der Höhe, damit die Notizen Platz behalten.
            let liveHeight = min(column * ratio, (geo.size.height - 48) * 0.62)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Jetzt auf dem Beamer")
                    WebSlot(web: controller.liveWeb)
                        .frame(width: liveHeight / ratio, height: liveHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.consoleAccent, lineWidth: 2))

                    HStack {
                        SectionLabel("Notizen")
                        Spacer()
                        NotesSizeButtons(controller: controller)
                    }
                    .padding(.top, 6)

                    NotesView(text: controller.notes(for: controller.current), slideIndex: controller.current)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: column)

                VStack(alignment: .leading, spacing: 10) {
                    if let slide = controller.currentSlide, controller.currentStep < slide.steps {
                        let left = slide.steps - controller.currentStep
                        Text(left == 1 ? "Noch 1 Einblendung auf dieser Folie" : "Noch \(left) Einblendungen auf dieser Folie")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.consoleSelection)
                    }
                    if let next = controller.nextSlide {
                        SectionLabel("Als Nächstes · \(next.number)")
                        Thumbnail(image: controller.thumbnails[next.index], aspect: controller.stageSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        NotesView(text: controller.notes(for: next.index, size: controller.smallNotesFontSize, dimmed: true),
                                  slideIndex: next.index)
                            .frame(maxHeight: .infinity)
                    } else {
                        SectionLabel("Als Nächstes")
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.consolePanel)
                            .aspectRatio(controller.stageSize, contentMode: .fit)
                            .overlay(Text("Ende der Präsentation").foregroundStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
        }
    }
}

private struct NotesSizeButtons: View {
    @Bindable var controller: PresentationController

    var body: some View {
        HStack(spacing: 10) {
            Button { controller.notesFontSize = max(14, controller.notesFontSize - 2) } label: {
                Text("A").font(.system(size: 12, weight: .semibold))
            }
            .help("Notizen kleiner (⌘−)")
            Button { controller.notesFontSize = min(48, controller.notesFontSize + 2) } label: {
                Text("A").font(.system(size: 17, weight: .semibold))
            }
            .help("Notizen größer (⌘+)")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Übersicht: alle Folien, je Rückgrat-Folie eine Zeile, daneben Notizen

private struct OverviewView: View {
    @Bindable var controller: PresentationController
    @State private var pinchStartWidth: CGFloat?

    private var cardWidth: CGFloat { controller.overviewCardWidth }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartWidth ?? controller.overviewCardWidth
                pinchStartWidth = start
                controller.setOverviewCardWidth(start * value.magnification)
            }
            .onEnded { _ in pinchStartWidth = nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            ForEach(controller.sections, id: \.first!.index) { section in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 14) {
                                        ForEach(section) { slide in
                                            card(for: slide)
                                            if slide.level == 1 && section.count > 1 {
                                                Rectangle()
                                                    .fill(Color.white.opacity(0.15))
                                                    .frame(width: 1, height: cardWidth * controller.stageSize.height / controller.stageSize.width)
                                            }
                                        }
                                    }
                                    .padding(8)
                                }
                            }
                        }
                        .padding(20)
                    }
                    .simultaneousGesture(pinch)
                    .onAppear { proxy.scrollTo(controller.current, anchor: .center) }
                    .onChange(of: controller.current) { _, index in
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
                Text("Klick: Notizen ansehen  ·  Doppelklick oder ⏎: auf den Beamer  ·  esc: Auswahl aufheben")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)

            OverviewNotes(controller: controller)
                .frame(width: 360)
        }
    }

    private func card(for slide: Slide) -> some View {
        let isCurrent = slide.index == controller.current
        let isSelected = slide.index == controller.selection
        return VStack(alignment: .leading, spacing: 6) {
            Thumbnail(image: controller.thumbnails[slide.index], aspect: controller.stageSize)
                .frame(width: cardWidth)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.consoleAccent : Color.white.opacity(0.12), lineWidth: isCurrent ? 3 : 1)
                )
                // Auswahl als eigener Ring außen herum – so bleibt sichtbar, wenn die Beamer-Folie zugleich ausgewählt ist.
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.consoleSelection, lineWidth: 4)
                        .padding(-6)
                        .opacity(isSelected ? 1 : 0)
                )
                .overlay(alignment: .topLeading) {
                    if isCurrent {
                        Text("BEAMER")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.consoleAccent, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.black)
                            .padding(6)
                    }
                }
            SlideCaption(slide: slide, highlight: isCurrent)
                .frame(width: cardWidth, alignment: .leading)
        }
        .id(slide.index)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            controller.goto(slide.index)
            controller.selection = nil
        }
        // Gleichzeitig statt nachrangig: Die Auswahl erscheint sofort, ohne auf einen möglichen Doppelklick zu warten.
        .simultaneousGesture(TapGesture().onEnded { controller.selection = slide.index })
    }
}

private struct OverviewNotes: View {
    @Bindable var controller: PresentationController

    var body: some View {
        let shown = controller.selection ?? controller.current
        let onBeamer = shown == controller.current
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(onBeamer ? "Auf dem Beamer" : "Ausgewählt")
                Spacer()
                NotesSizeButtons(controller: controller)
            }
            if controller.slides.indices.contains(shown) {
                let slide = controller.slides[shown]
                Thumbnail(image: controller.thumbnails[shown], aspect: controller.stageSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(onBeamer ? Color.consoleAccent : Color.consoleSelection, lineWidth: 3)
                    )
                    .padding(.bottom, 4)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(slide.number)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(shown == controller.current ? Color.consoleAccent : Color.consoleSelection)
                    Text(slide.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                }
                NotesView(text: controller.notes(for: shown, size: max(14, controller.notesFontSize - 4)), slideIndex: shown)
                    .frame(maxHeight: .infinity)
                if shown != controller.current {
                    Button {
                        controller.goto(shown)
                        controller.selection = nil
                    } label: {
                        Label("Auf den Beamer", systemImage: "play.rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help("Auch mit ⏎ oder Doppelklick")
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Spiegel: genau das, was das Publikum sieht

private struct MirrorView: View {
    @Bindable var controller: PresentationController
    let presenting: Bool

    var body: some View {
        ZStack {
            Color.black
            WebSlot(web: controller.liveWeb)
                .aspectRatio(controller.stageSize, contentMode: .fit)
                .opacity(controller.isBlack ? (presenting ? 0 : 0.25) : 1)
        }
    }
}

// MARK: - Bausteine

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

private struct SlideCaption: View {
    let slide: Slide
    let highlight: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(slide.number)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(highlight ? Color.consoleAccent : Color.secondary)
            Text(slide.title)
                .font(.system(size: 13))
                .lineLimit(1)
        }
    }
}

private struct Thumbnail: View {
    let image: NSImage?
    let aspect: CGSize

    var body: some View {
        ZStack {
            Color.consolePanel
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

private struct EmptyState: View {
    let onOpen: () -> Void
    let onCopySchema: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("Keine Präsentation geöffnet")
                .font(.title2)
            Button("Präsentation öffnen …", action: onOpen)
                .keyboardShortcut("o")
                .controlSize(.large)
            Button(action: onCopySchema) {
                Label("Präsentationsschema für KI kopieren", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.link)
            .padding(.top, 8)
            .help("Legt SCHEMA.md in die Zwischenablage – zum Einfügen in einen Chat mit einer KI")
        }
    }
}

/// Chevron ganz rechts: in der Kopfleiste blendet es sie aus, im reinen Spiegel an derselben Stelle wieder ein.
private struct BarToggle: View {
    let barVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: barVisible ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(barVisible ? Color.white.opacity(0.12) : Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .help(barVisible ? "Kopfleiste ausblenden – nur die Präsentation zeigen" : "Kopfleiste einblenden")
    }
}

private struct JumpOverlay: View {
    let typed: String

    var body: some View {
        VStack(spacing: 6) {
            Text("Gehe zu Folie")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(typed)
                .font(.system(size: 54, weight: .bold, design: .rounded))
            Text("⏎ springen  ·  esc abbrechen")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40).padding(.vertical, 24)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Bettet eine vorhandene WebView ein, ohne sie neu zu laden.
/// Wechselt die Ansicht, zieht die WebView einfach in den neuen Platz um.
struct WebSlot: NSViewRepresentable {
    let web: WKWebView

    func makeNSView(context: Context) -> NSView {
        let slot = NSView()
        adopt(into: slot)
        return slot
    }

    func updateNSView(_ slot: NSView, context: Context) {
        // Nur eine verwaiste WebView zurückholen – sonst stiehlt eine gerade verschwindende
        // Ansicht sie der neuen in ihrem letzten Update.
        if web.superview == nil { adopt(into: slot) }
    }

    static func dismantleNSView(_ slot: NSView, coordinator: ()) {
        slot.subviews.forEach { $0.removeFromSuperview() }
    }

    private func adopt(into slot: NSView) {
        web.removeFromSuperview()
        web.frame = slot.bounds
        web.autoresizingMask = [.width, .height]
        slot.addSubview(web)
    }
}

/// Notizen als formatierter Text (HTML aus `data-notes`), scroll- und markierbar.
struct NotesView: NSViewRepresentable {
    let text: NSAttributedString
    let slideIndex: Int

    final class Coordinator {
        var shown: NSAttributedString?
        var index = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 6)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.shown !== text, let textView = scroll.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(text)
        if context.coordinator.index != slideIndex { textView.scrollToBeginningOfDocument(nil) }
        context.coordinator.shown = text
        context.coordinator.index = slideIndex
    }
}
