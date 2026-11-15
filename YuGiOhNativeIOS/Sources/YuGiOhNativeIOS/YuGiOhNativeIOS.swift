import UIKit
import SwiftUI

public struct Card: Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let type: String
    public let attribute: String
    public let description: String
    public let imageName: String?
    public let intID: Int?
    public let konamiID: Int?
    public let atk: Int?
    public let def: Int?
    public let kind: String?
    public let attributeName: String?
    public let race: String?
    public let level: Int?
    public let genres: [String]

    public init(id: Int, name: String, type: String, attribute: String, description: String, imageName: String? = nil, intID: Int? = nil, konamiID: Int? = nil, atk: Int? = nil, def: Int? = nil, kind: String? = nil, attributeName: String? = nil, race: String? = nil, level: Int? = nil, genres: [String] = []) {
        self.id = id; self.name = name; self.type = type; self.attribute = attribute; self.description = description; self.imageName = imageName; self.intID = intID; self.konamiID = konamiID; self.atk = atk; self.def = def; self.kind = kind; self.attributeName = attributeName; self.race = race; self.level = level; self.genres = genres
    }
}

public struct CardCatalog {
    public static let sample: [Card] = [
        Card(id: 1, name: "Exodia the Forbidden One", type: "Monster", attribute: "DARK", description: "If you have all 5 pieces of Exodia in your hand, you win the Duel."),
        Card(id: 2, name: "Blue-Eyes White Dragon", type: "Monster", attribute: "LIGHT", description: "This legendary dragon is a powerful engine of destruction."),
        Card(id: 3, name: "Dark Magician", type: "Monster", attribute: "DARK", description: "The ultimate wizard in terms of attack and defense.")
    ]
    public static func load() -> [Card] {
        guard let url = Bundle.main.url(forResource: "cards_en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return sample }
        let index = loadIndex()
        return rows.map { row in
            let meta = index[row.sourceIndex]
            let imageName = meta.map { String(format: "%04d.jpg", $0.konamiID) }
            return Card(id: row.id, name: row.name, type: meta?.race ?? "Card", attribute: meta?.attribute ?? "", description: row.description, imageName: imageName, intID: meta?.intID, konamiID: meta?.konamiID, atk: meta?.atk, def: meta?.def, kind: meta?.kind, attributeName: meta?.attribute, race: meta?.race, level: meta?.level, genres: meta?.genres ?? [])
        }
    }
    private struct Row: Decodable {
        let sourceIndex: Int
        let name: String
        let description: String
        var id: Int { sourceIndex + 1 }
        enum CodingKeys: String, CodingKey { case sourceIndex, id, name, description }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sourceIndex = try c.decodeIfPresent(Int.self, forKey: .sourceIndex) ?? (c.decode(Int.self, forKey: .id) - 1)
            name = try c.decode(String.self, forKey: .name)
            description = try c.decode(String.self, forKey: .description)
        }
    }
    private struct IndexRow: Decodable { let sourceIndex: Int; let intID: Int?; let propFirst: UInt32; let atk: Int?; let def: Int?; let kind: String?; let attribute: String?; let level: Int?; let race: String?; let genres: [String]; var konamiID: Int { Int(propFirst & 0x3FFF) } }
    private static func loadIndex() -> [Int: IndexRow] { guard let url=Bundle.main.url(forResource: "card-index", withExtension: "json"), let data=try? Data(contentsOf:url), let rows=try? JSONDecoder().decode([IndexRow].self,from:data) else { return [:] }; return Dictionary(uniqueKeysWithValues: rows.map { ($0.sourceIndex,$0) }) }
}

@MainActor public final class CardStore: ObservableObject {
    @Published public var query = ""
    @Published public var selectedType = "All"
    public let cards: [Card]
    public init(cards: [Card] = CardCatalog.load()) { self.cards = cards }
    public var filtered: [Card] {
        cards.filter { card in
            (selectedType == "All" || card.type == selectedType) &&
            (query.isEmpty || card.name.localizedCaseInsensitiveContains(query) || card.description.localizedCaseInsensitiveContains(query))
        }
    }
}

private enum CardImageStore {
    static func image(named name: String) -> UIImage? {
        let path = Bundle.main.path(forResource: name.replacingOccurrences(of: ".jpg", with: ""), ofType: "jpg", inDirectory: "CardImages")
        return path.flatMap { UIImage(contentsOfFile: $0) }
    }
}

public struct ContentView: View {
    @StateObject private var store = CardStore()
    private let types = ["All", "Effect Monster", "Normal Monster"]

    public init() {}
    public var body: some View {
        NavigationStack {
            List(store.filtered) { card in
                NavigationLink(value: card) { CardRow(card: card) }
            }
            .navigationTitle("Card Catalog")
            .searchable(text: $store.query, prompt: "Search cards")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavigationLink(destination: DeckListView()) { Label("Decks", systemImage: "rectangle.stack") } }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Type", selection: $store.selectedType) {
                        ForEach(types, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationDestination(for: Card.self) { CardDetailView(card: $0) }
        }
    }
}

private struct CardRow: View {
    let card: Card
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.name).font(.headline)
            Text("\(card.kind ?? card.type) | \(card.attributeName ?? card.attribute)").font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct CardDetailView: View {
    let card: Card
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageName = card.imageName, let image = CardImageStore.image(named: imageName) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320).clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16).fill(.orange.gradient).frame(height: 220).overlay(Text(card.name).font(.title2.bold()).multilineTextAlignment(.center).padding())
                }
                Text(card.name).font(.title.bold())
                Label(card.kind ?? card.type, systemImage: "rectangle.stack")
                Label(card.attributeName ?? card.attribute, systemImage: "circle.lefthalf.filled")
                if let race = card.race { Text("Race: \(race)") }
                if let level = card.level { Text("Level: \(level) | ATK: \(card.atk.map(String.init) ?? "?") | DEF: \(card.def.map(String.init) ?? "?")") }
                Text(card.description).font(.body)
                if !card.genres.isEmpty { Text(card.genres.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                if let pack = CardPackStore.summary, pack.status == "empty" { Text("Pack assignment: unavailable in source table").font(.caption).foregroundStyle(.secondary) }
                if let relation = CardRelationStore.relation(for: card.konamiID) {
                    if !relation.archetypes.isEmpty { Text("Archetype codes: " + relation.archetypes.map(String.init).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    if !relation.links.isEmpty { Text("Related links: " + relation.links.map { "\($0.target) (\($0.kind))" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    if let same = relation.same { Text("Same name as: \(same.target) [\(same.mode)]").font(.caption).foregroundStyle(.secondary) }
                }
            }.padding()
        }.navigationTitle("Card Detail")
    }
}

