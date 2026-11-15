import Foundation
import SwiftUI

@MainActor
final class OfflineDuelEngine: ObservableObject {
    enum Phase: String { case draw = "Draw"; case standby = "Standby"; case main = "Main"; case battle = "Battle"; case end = "End" }
    struct DuelDeck: Decodable { let file: String; let main: [Int]; let extra: [Int]; let side: [Int] }
    struct Meta: Decodable { let propFirst: UInt32; let atk: Int? }
    @Published private(set) var playerLP = 8000
    @Published private(set) var opponentLP = 8000
    @Published private(set) var playerHand: [Int] = []
    @Published private(set) var opponentHand: [Int] = []
    @Published private(set) var playerField: [Int] = []
    @Published private(set) var opponentField: [Int] = []
    @Published private(set) var log: [String] = []
    @Published private(set) var chain: [String] = []
    @Published private(set) var turn = 1
    @Published private(set) var phase: Phase = .draw
    @Published private(set) var started = false
    @Published private(set) var normalSummonUsed = false
    @Published private(set) var attackUsed = false
    let deckName: String
    private var playerDeck: [Int]
    private var opponentDeck: [Int]
    private let names: [String: String]
    private let atkByKonamiID: [Int: Int]

    init() {
        let decks = Self.loadDecks()
        let deck = decks.first ?? DuelDeck(file: "No deck", main: [], extra: [], side: [])
        deckName = deck.file
        playerDeck = deck.main.shuffled(); opponentDeck = deck.main.shuffled()
        names = Self.loadNames(); atkByKonamiID = Self.loadAttack()
    }

    func start() {
        playerLP = 8000; opponentLP = 8000; playerHand = []; opponentHand = []
        playerField = []; opponentField = []; log = []; chain = []; turn = 1
        normalSummonUsed = false; attackUsed = false; started = true; phase = .draw
        for _ in 0..<5 { draw(player: true); draw(player: false) }
        log.append("Duel started with \(deckName)")
    }

    func nextPhase() {
        guard started else { return }
        switch phase {
        case .draw: phase = .standby
        case .standby: phase = .main
        case .main: phase = .battle
        case .battle: phase = .end
        case .end: endTurn()
        }
        log.append("Turn \(turn): \(phase.rawValue) Phase")
    }

    func endTurn() {
        guard started else { return }
        turn += 1; phase = .draw; normalSummonUsed = false; attackUsed = false
        draw(player: true); draw(player: false)
        log.append("Turn \(turn): Draw Phase")
    }

    func draw(player: Bool) {
        if player { if let card = playerDeck.popLast() { playerHand.append(card) } }
        else if let card = opponentDeck.popLast() { opponentHand.append(card) }
    }

    func summonFirstCard() {
        guard started, phase == .main, !normalSummonUsed, let card = playerHand.first else { return }
        playerHand.removeFirst(); playerField.append(card); normalSummonUsed = true
        log.append("Summoned \(name(card))")
    }

    func attack() {
        guard started, phase == .battle, !attackUsed, let attacker = playerField.first else { return }
        attackUsed = true; let damage = atkByKonamiID[attacker] ?? 0
        beginChain("Attack: \(name(attacker))")
        opponentLP = max(0, opponentLP - damage)
        resolveChain(); log.append("Attacked for \(damage) damage")
    }

    func activateDrawEffect() {
        guard started, phase == .main else { return }
        beginChain("Draw 1"); draw(player: true); resolveChain(); log.append("Effect resolved: drew 1 card")
    }

    func activateDamageEffect() {
        guard started, phase == .main else { return }
        beginChain("Deal 500 damage"); opponentLP = max(0, opponentLP - 500); resolveChain(); log.append("Effect resolved: 500 damage")
    }

    func negateTopChain() {
        guard !chain.isEmpty else { return }
        let effect = chain.removeLast(); log.append("Negated: \(effect)")
    }

    private func beginChain(_ effect: String) { chain.append("Chain \(chain.count + 1): \(effect)"); log.append(chain.last ?? effect) }
    private func resolveChain() { chain.removeAll() }
    func name(_ id: Int) -> String { names[String(id)] ?? "Card \(id)" }
    func attackValue(_ id: Int) -> Int { atkByKonamiID[id] ?? 0 }

    private static func loadDecks() -> [DuelDeck] {
        guard let url = Bundle.main.url(forResource: "ydc-decks", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let decks = try? JSONDecoder().decode([DuelDeck].self, from: data) else { return [] }; return decks
    }
    private static func loadNames() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "card-id-names", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }; return map
    }
    private static func loadAttack() -> [Int: Int] {
        guard let url = Bundle.main.url(forResource: "card-index", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let rows = try? JSONDecoder().decode([Meta].self, from: data) else { return [:] }; return Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.atk.map { (Int(row.propFirst & 0x3FFF), $0) } })
    }
}

struct OfflineDuelView: View {
    @StateObject private var game = OfflineDuelEngine()
    var body: some View {
        VStack(spacing: 12) {
            Text("Offline Duel").font(.title.bold())
            HStack { Text("Turn \(game.turn) · \(game.phase.rawValue)"); Spacer(); Text("Opponent LP \(game.opponentLP)"); Text("Your LP \(game.playerLP)") }.font(.caption)
            GroupBox("Field") { HStack { Text(game.opponentField.first.map(game.name) ?? "Opponent empty"); Spacer(); Text(game.playerField.first.map { "\(game.name($0)) (\(game.attackValue($0)) ATK)" } ?? "Your field empty") } }
            Text("Hand: \(game.playerHand.count) · Chain: \(game.chain.count)")
            HStack { Button("Start", action: game.start).buttonStyle(.borderedProminent); Button("Next Phase", action: game.nextPhase).buttonStyle(.bordered); Button("Summon", action: game.summonFirstCard).buttonStyle(.bordered) }
            HStack { Button("Attack", action: game.attack); Button("Draw Effect", action: game.activateDrawEffect); Button("500 Damage", action: game.activateDamageEffect); Button("Negate", action: game.negateTopChain) }.buttonStyle(.bordered)
            List(game.log.reversed(), id: \.self) { Text($0).font(.caption) }
        }.padding().navigationTitle("Duel")
    }
}
