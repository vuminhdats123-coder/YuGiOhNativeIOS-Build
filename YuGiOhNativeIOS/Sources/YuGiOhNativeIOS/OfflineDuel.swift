import Foundation
import SwiftUI

@MainActor
final class OfflineDuelEngine: ObservableObject {
    struct DuelDeck: Decodable { let file: String; let main: [Int]; let extra: [Int]; let side: [Int] }
    struct Meta: Decodable { let propFirst: UInt32; let atk: Int? }
    @Published private(set) var playerLP = 8000
    @Published private(set) var opponentLP = 8000
    @Published private(set) var playerHand: [Int] = []
    @Published private(set) var opponentHand: [Int] = []
    @Published private(set) var playerField: [Int] = []
    @Published private(set) var opponentField: [Int] = []
    @Published private(set) var log: [String] = []
    @Published private(set) var started = false
    let deckName: String
    private var playerDeck: [Int]
    private var opponentDeck: [Int]
    private let names: [String: String]
    private let atkByKonamiID: [Int: Int]

    init() {
        let decks = Self.loadDecks()
        let deck = decks.first ?? DuelDeck(file: "No deck", main: [], extra: [], side: [])
        deckName = deck.file
        playerDeck = deck.main.shuffled()
        opponentDeck = deck.main.shuffled()
        names = Self.loadNames()
        atkByKonamiID = Self.loadAttack()
    }

    func start() {
        playerLP = 8000; opponentLP = 8000; playerHand = []; opponentHand = []
        playerField = []; opponentField = []; log = []; started = true
        for _ in 0..<5 { draw(player: true); draw(player: false) }
        log.append("Duel started with \(deckName)")
    }

    func draw(player: Bool) {
        if player { if let card = playerDeck.popLast() { playerHand.append(card) } }
        else if let card = opponentDeck.popLast() { opponentHand.append(card) }
    }

    func summonFirstCard() {
        guard started, playerField.isEmpty, let card = playerHand.first else { return }
        playerHand.removeFirst(); playerField.append(card); log.append("Summoned \(name(card))")
    }

    func attack() {
        guard started, let attacker = playerField.first else { return }
        let damage = atkByKonamiID[attacker] ?? 0
        opponentLP = max(0, opponentLP - damage)
        log.append("Attacked for \(damage) with \(name(attacker))")
    }

    func name(_ id: Int) -> String { names[String(id)] ?? "Card \(id)" }
    func attackValue(_ id: Int) -> Int { atkByKonamiID[id] ?? 0 }

    private static func loadDecks() -> [DuelDeck] {
        guard let url = Bundle.main.url(forResource: "ydc-decks", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let decks = try? JSONDecoder().decode([DuelDeck].self, from: data) else { return [] }
        return decks
    }
    private static func loadNames() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "card-id-names", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }
    private static func loadAttack() -> [Int: Int] {
        guard let url = Bundle.main.url(forResource: "card-index", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let rows = try? JSONDecoder().decode([Meta].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.atk.map { (Int(row.propFirst & 0x3FFF), $0) } })
    }
}

struct OfflineDuelView: View {
    @StateObject private var game = OfflineDuelEngine()
    var body: some View {
        VStack(spacing: 14) {
            Text("Offline Duel").font(.title.bold())
            HStack { Text("Opponent LP \(game.opponentLP)"); Spacer(); Text("Your LP \(game.playerLP)") }
            GroupBox("Field") {
                HStack {
                    Text(game.opponentField.first.map(game.name) ?? "Opponent field empty")
                    Spacer()
                    Text(game.playerField.first.map { "\(game.name($0)) (\(game.attackValue($0)) ATK)" } ?? "Your field empty")
                }
            }
            Text("Hand: \(game.playerHand.count) cards")
            HStack {
                Button("Start", action: game.start).buttonStyle(.borderedProminent)
                Button("Summon", action: game.summonFirstCard).buttonStyle(.bordered)
                Button("Attack", action: game.attack).buttonStyle(.bordered)
            }
            List(game.log.reversed(), id: \.self) { Text($0).font(.caption) }
        }
        .padding()
        .navigationTitle("Duel")
    }
}
