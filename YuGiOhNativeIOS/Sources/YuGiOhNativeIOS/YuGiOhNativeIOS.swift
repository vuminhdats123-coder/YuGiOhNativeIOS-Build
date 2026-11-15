import UIKit
import SwiftUI

public struct Card: Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let type: String
    public let attribute: String
    public let description: String
    public let imageName: String?

    public init(id: Int, name: String, type: String, attribute: String, description: String, imageName: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.attribute = attribute; self.description = description; self.imageName = imageName
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
        return rows.map { Card(id: $0.id, name: $0.name, type: "Card", attribute: "", description: $0.description, imageName: String(format: "%04d.jpg", $0.id)) }
    }
    private struct Row: Decodable { let id: Int; let name: String; let description: String }
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

'
private enum CardImageStore {
    static func image(named name: String) -> UIImage? {
        let path = Bundle.main.path(forResource: name.replacingOccurrences(of: ".jpg", with: ""), ofType: "jpg", inDirectory: "CardImages")
        return path.flatMap { UIImage(contentsOfFile: $0) }
    }
}

'public struct ContentView: View {
    @StateObject private var store = CardStore()
    private let types = ["All", "Effect Monster", "Normal Monster"]

    public init() {}
    public var body: some View {
        NavigationStack {
            List(store.filtered) { card in
                NavigationLink(value: card) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name).font(.headline)
                        Text("\(card.type) · \(card.attribute)").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Card Catalog")
            .searchable(text: $store.query, prompt: "Search cards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Type", selection: $store.selectedType) {
                        ForEach(types, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationDestination(for: Card.self) { card in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let imageName = card.imageName, let image = CardImageStore.image(named: imageName) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320).clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16).fill(.orange.gradient).frame(height: 220)
                                .overlay(Text(card.name).font(.title2.bold()).multilineTextAlignment(.center).padding())
                        }
                        Text(card.name).font(.title.bold())
                        Label(card.type, systemImage: "rectangle.stack")
                        Label(card.attribute, systemImage: "circle.lefthalf.filled")
                        Text(card.description).font(.body)
                    }.padding()
                }.navigationTitle("Card Detail")
            }
        }
    }
}



