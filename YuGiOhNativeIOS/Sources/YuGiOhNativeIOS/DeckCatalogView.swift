import SwiftUI

private struct Deck: Identifiable, Decodable {
    let file: String
    let unknown: UInt64
    let main: [Int]
    let extra: [Int]
    let side: [Int]
    var id: String { file }
}

private enum DeckCatalog {
    static func load() -> [Deck] {
        guard let url = Bundle.main.url(forResource: "ydc-decks", withExtension: "json", subdirectory: "GeneratedData"),
              let data = try? Data(contentsOf: url),
              let decks = try? JSONDecoder().decode([Deck].self, from: data) else { return [] }
        return decks
    }
    static func loadNames() -> [Int: String] {
        guard let url = Bundle.main.url(forResource: "card-id-names", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.compactMap { key, name in
            Int(key).map { ($0, name) }
        })
    }
}

struct DeckListView: View {
    private let decks = DeckCatalog.load()
    private let names = DeckCatalog.loadNames()
    private func label(_ id: Int) -> String { names[id].map { "\($0) (Konami ID \(id))" } ?? "Unknown card (Konami ID \(id))" }
    var body: some View {
        List(decks) { deck in
            NavigationLink(value: deck.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.file).font(.headline)
                    Text("Main \(deck.main.count) | Extra \(deck.extra.count) | Side \(deck.side.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Decks")
        .navigationDestination(for: String.self) { id in
            if let deck = decks.first(where: { $0.id == id }) {
                List {
                    Section("Main (\(deck.main.count))") {
                        ForEach(Array(deck.main.enumerated()), id: \.offset) { row in
                            Text("\(row.offset + 1). \(label(row.element))")
                        }
                    }
                    Section("Extra (\(deck.extra.count))") {
                        ForEach(Array(deck.extra.enumerated()), id: \.offset) { row in
                            Text("\(row.offset + 1). \(label(row.element))")
                        }
                    }
                    Section("Side (\(deck.side.count))") {
                        ForEach(Array(deck.side.enumerated()), id: \.offset) { row in
                            Text("\(row.offset + 1). \(label(row.element))")
                        }
                    }
                }
                .navigationTitle(deck.file)
            }
        }
    }
}

