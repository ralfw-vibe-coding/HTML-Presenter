import Foundation

/// Eine Folie, wie die Laufzeit (`presentation.slides`) sie meldet.
struct Slide: Identifiable, Equatable {
    let index: Int
    let number: String
    let level: Int
    let key: String
    let title: String
    let notes: String
    /// Anzahl der Einblendungen innerhalb der Folie (`data-step`), 0 = keine.
    let steps: Int
    let parent: Int?
    let children: [Int]

    var id: Int { index }

    init?(_ dict: [String: Any]) {
        guard let index = dict["index"] as? Int, let number = dict["number"] as? String else { return nil }
        self.index = index
        self.number = number
        level = dict["level"] as? Int ?? 1
        key = dict["id"] as? String ?? number
        title = dict["title"] as? String ?? ""
        notes = dict["notes"] as? String ?? ""
        steps = dict["steps"] as? Int ?? 0
        parent = dict["parent"] as? Int
        children = dict["children"] as? [Int] ?? []
    }
}

struct DeadlineWarning: Equatable {
    let minutes: Int
    let id = UUID()

    var text: String {
        switch minutes {
        case 0: "Die Zeit ist um"
        case 1: "Noch 1 Minute"
        default: "Noch \(minutes) Minuten"
        }
    }
}

/// Anordnung der Übersicht: je Rückgrat-Folie eine Zeile, oder alle Folien fortlaufend umbrechend.
enum OverviewLayout: String, CaseIterable, Identifiable {
    case rows, matrix

    var id: String { rawValue }
}

enum ConsoleMode: Int, CaseIterable, Identifiable {
    case speaker, overview, mirror

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .speaker: "Referent"
        case .overview: "Übersicht"
        case .mirror: "Spiegel"
        }
    }
}
