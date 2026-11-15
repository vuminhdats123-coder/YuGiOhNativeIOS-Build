import Foundation

// Run together with DuelState.swift only when Swift test execution is authorized.
// These checks exercise the production state machine, not a second rules implementation.
@main
enum DuelStateChecks {
    static let definitions: [Int: DuelCardDefinition] = {
        var result: [Int: DuelCardDefinition] = [:]
        for id in 100...129 {
            result[id] = DuelCardDefinition(id: id, name: "Normal \(id)", kindCode: 0,
                                           level: 4, atk: 1000, def: 1000, password: nil)
        }
        func normal(_ id: Int, _ level: Int, _ atk: Int, _ def: Int) {
            result[id] = DuelCardDefinition(id: id, name: "Normal \(id)", kindCode: 0,
                                           level: level, atk: atk, def: def, password: nil)
        }
        normal(101, 4, 2000, 1000); normal(102, 4, 500, 2500); normal(103, 4, 0, 0)
        normal(104, 5, 2400, 1500); normal(105, 7, 3000, 2500); normal(106, 4, 8000, 0)
        let spells: [(Int, String, Int, UInt32)] = [
            (1, "Pot of Greed", 13, 55_144_522), (2, "Sparks", 13, 76_103_675),
            (3, "Dian Keto the Cure Master", 13, 84_257_639), (4, "Solemn Judgment", 14, 41_420_027)
        ]
        for (id, name, kind, password) in spells {
            result[id] = DuelCardDefinition(id: id, name: name, kindCode: kind,
                                           level: 0, atk: nil, def: nil, password: password)
        }
        return result
    }()

    static func deck(_ prefix: [Int] = [], size: Int = 40) -> [Int] {
        var result = prefix
        for id in 110...129 {
            while result.count < size && result.filter({ $0 == id }).count < 3 { result.append(id) }
        }
        precondition(result.count == size)
        return result
    }
    static func game(_ first: [Int] = [], _ second: [Int] = []) throws -> DuelState {
        try DuelState(definitions: definitions, decks: [deck(first), deck(second)])
    }
    static func handID(_ state: DuelState, _ player: Int, _ definition: Int) -> Int {
        state.players[player].hand.first { $0.definitionID == definition }!.id
    }
    static func mainPhase(_ state: inout DuelState) throws {
        if state.phase == .draw { try state.nextPhase(player: state.activePlayer) }
        if state.phase == .standby { try state.nextPhase(player: state.activePlayer) }
        precondition(state.phase == .main1)
    }
    static func finishTurn(_ state: inout DuelState) throws {
        while state.phase != .end { try state.nextPhase(player: state.activePlayer) }
        let player = state.activePlayer
        let excess = state.players[player].hand.count - 6
        if excess > 0 {
            try state.discard(player: player, cardIDs: Array(state.players[player].hand.suffix(excess)).map(\.id))
        }
        try state.nextPhase(player: player)
    }
    static func resolve(_ state: inout DuelState) throws {
        try state.pass(player: state.priorityPlayer)
        precondition(!state.chain.isEmpty)
        try state.pass(player: state.priorityPlayer)
        precondition(state.chain.isEmpty)
    }
    static func reject(_ state: inout DuelState, _ operation: (inout DuelState) throws -> Void) {
        let before = state
        do { try operation(&state); preconditionFailure("Expected rejected action") }
        catch is DuelState.DuelError { }
        catch { preconditionFailure("Unexpected error: \(error)") }
        precondition(before.players == state.players && before.chain == state.chain)
        precondition(before.activePlayer == state.activePlayer && before.turn == state.turn)
        precondition(before.phase == state.phase && before.winner == state.winner)
        precondition(before.priorityPlayer == state.priorityPlayer && before.log == state.log)
    }
    static func conserved(_ state: DuelState, total: Int = 80) {
        var ids = state.chain.map { $0.card.id }
        for player in state.players {
            ids += (player.deck + player.hand + player.graveyard).map(\.id)
            ids += player.field.map(\.id) + player.traps.map(\.id)
        }
        precondition(ids.count == total && Set(ids).count == total, "Lost or duplicated physical cards")
    }

    static func main() throws {
        // Strict subset and deck size limits: no ignored or silently broken card effects.
        do {
            var invalid = definitions
            invalid[100] = DuelCardDefinition(id: 100, name: "Unsupported effect", kindCode: 1,
                                             level: 4, atk: 1000, def: 1000, password: nil)
            for (defs, decks) in [(invalid, [deck([100]), deck()]),
                                  (definitions, [deck([100, 100, 100, 100]), deck()]),
                                  (definitions, [Array(deck().dropLast()), deck()])] {
                do { _ = try DuelState(definitions: defs, decks: decks); preconditionFailure("Invalid deck accepted") }
                catch is DuelState.DuelError { }
            }
        }

        // First turn skips draw/Battle/Main2; exactly one player draws on each later turn.
        do {
            var state = try game()
            let initial = state.players
            precondition(state.players[0].hand.count == 5 && state.players[1].deck.count == 35)
            try mainPhase(&state)
            try state.nextPhase(player: 0)
            precondition(state.phase == .end && state.players[0].hand.count == 5)
            try state.nextPhase(player: 0)
            precondition(state.turn == 2 && state.activePlayer == 1 && state.players[1].hand.count == 6)
            precondition(state.players[0].hand.count == 5)
            try mainPhase(&state)
            try state.nextPhase(player: 1); precondition(state.phase == .battle)
            try state.nextPhase(player: 1); precondition(state.phase == .main2)
            try finishTurn(&state)
            precondition(state.turn == 3 && state.activePlayer == 0 && state.players[0].hand.count == 6)
            state.restart()
            precondition(state.players == initial && state.turn == 1 && state.winner == nil && state.chain.isEmpty)
            conserved(state)
        }

        // Summon validation is atomic; no spell-as-monster, duplicate tributes, or summon spam.
        do {
            var state = try game([100, 101, 104, 105, 2])
            let small = handID(state, 0, 100), tribute = handID(state, 0, 104), high = handID(state, 0, 105)
            reject(&state) { try $0.summon(player: 0, cardID: small) }
            try mainPhase(&state)
            reject(&state) { try $0.summon(player: 1, cardID: small) }
            reject(&state) { try $0.summon(player: 0, cardID: handID($0, 0, 2)) }
            reject(&state) { try $0.summon(player: 0, cardID: tribute) }
            try state.summon(player: 0, cardID: small)
            reject(&state) { try $0.summon(player: 0, cardID: handID($0, 0, 101)) }
            reject(&state) { try $0.changePosition(player: 0, monsterID: small) }
            try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
            reject(&state) { try $0.summon(player: 0, cardID: high, tributes: [small, small]) }
            try state.summon(player: 0, cardID: tribute, tributes: [small], set: true)
            precondition(state.players[0].field.count == 1 && state.players[0].field[0].faceDown)
            precondition(state.players[0].graveyard.map(\.id) == [small])
            conserved(state)
        }

        // Full field and two-tribute summon: tribute validation frees the proper slots.
        do {
            var state = try game([100, 101, 102, 103, 105, 110])
            for monster in [100, 101, 102, 103, 110] {
                try mainPhase(&state)
                try state.summon(player: 0, cardID: handID(state, 0, monster))
                try finishTurn(&state); try finishTurn(&state)
            }
            try mainPhase(&state)
            reject(&state) { try $0.summon(player: 0, cardID: $0.players[0].hand.last!.id) }
            let tributes = state.players[0].field.prefix(2).map(\.id)
            try state.summon(player: 0, cardID: handID(state, 0, 105), tributes: tributes)
            precondition(state.players[0].field.count == 4 && state.players[0].graveyard.count >= 2)
            conserved(state)
        }

        // ATK/ATK target requirement, LP difference, destruction, and once per monster.
        do {
            var state = try game([100], [101])
            try mainPhase(&state); try state.summon(player: 0, cardID: handID(state, 0, 100))
            let target = state.players[0].field[0].id
            try finishTurn(&state); try mainPhase(&state)
            try state.summon(player: 1, cardID: handID(state, 1, 101))
            let attacker = state.players[1].field[0].id
            try state.nextPhase(player: 1)
            reject(&state) { try $0.attack(player: 1, attackerID: attacker) }
            try state.attack(player: 1, attackerID: attacker, targetID: target)
            precondition(state.players[0].lp == 7000 && state.players[0].field.isEmpty)
            reject(&state) { try $0.attack(player: 1, attackerID: attacker) }
            conserved(state)
        }

        // ATK ties destroy both except 0/0; DEF ties leave both alive.
        for id in [100, 103] {
            var state = try game([id], [id])
            try mainPhase(&state); try state.summon(player: 0, cardID: handID(state, 0, id))
            try finishTurn(&state); try mainPhase(&state)
            try state.summon(player: 1, cardID: handID(state, 1, id)); try state.nextPhase(player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players[0].field.count == (id == 103 ? 1 : 0))
            precondition(state.players[1].field.count == (id == 103 ? 1 : 0))
            precondition(state.players.allSatisfy { $0.lp == 8000 }); conserved(state)
        }
        for defenderID in [100, 102] {
            var state = try game([defenderID], [101])
            try mainPhase(&state); try state.summon(player: 0, cardID: handID(state, 0, defenderID), set: true)
            try finishTurn(&state); try mainPhase(&state)
            try state.summon(player: 1, cardID: handID(state, 1, 101)); try state.nextPhase(player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players[0].lp == 8000)
            precondition(state.players[1].lp == (defenderID == 102 ? 7500 : 8000))
            precondition(state.players[0].field.count == (defenderID == 102 ? 1 : 0))
            if defenderID == 102 { precondition(!state.players[0].field[0].faceDown) }
            conserved(state)
        }
        do {
            var state = try game([100], [100])
            try mainPhase(&state); try state.summon(player: 0, cardID: handID(state, 0, 100), set: true)
            try finishTurn(&state); try mainPhase(&state)
            try state.summon(player: 1, cardID: handID(state, 1, 100)); try state.nextPhase(player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players.allSatisfy { $0.field.count == 1 && $0.lp == 8000 })
            try state.nextPhase(player: 1)
            reject(&state) { try $0.changePosition(player: 1, monsterID: $0.players[1].field[0].id) }
            try finishTurn(&state); try mainPhase(&state)
            let monsterID = state.players[0].field[0].id
            try state.changePosition(player: 0, monsterID: monsterID)
            precondition(state.players[0].field[0].position == .attack && !state.players[0].field[0].faceDown)
            reject(&state) { try $0.changePosition(player: 0, monsterID: monsterID) }
            conserved(state)
        }
        do {
            var state = try game([101], [100])
            try mainPhase(&state); try state.summon(player: 0, cardID: handID(state, 0, 101))
            try finishTurn(&state); try mainPhase(&state)
            try state.summon(player: 1, cardID: handID(state, 1, 100)); try state.nextPhase(player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players[1].lp == 7000 && state.players[1].field.isEmpty)
            precondition(state.players[0].lp == 8000 && state.players[0].field.count == 1)
            conserved(state)
        }

        // Activations reserve real cards but do not apply effects until both players pass.
        do {
            var state = try game([1, 2, 3])
            try mainPhase(&state)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 1))
            precondition(state.players[0].hand.count == 4 && state.players[0].deck.count == 35)
            reject(&state) { try $0.nextPhase(player: 0) }
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 2)) }
            reject(&state) { try $0.pass(player: 0) }
            conserved(state); try resolve(&state)
            precondition(state.players[0].hand.count == 6 && state.players[0].deck.count == 33)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 2)); try resolve(&state)
            precondition(state.players[1].lp == 7800)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 3)); try resolve(&state)
            precondition(state.players[0].lp == 9000 && state.players[0].graveyard.count == 3)
            conserved(state)
        }

        // A counter costs LP, remains pending, and negates the actual prior link on resolution.
        do {
            var state = try game([4], [1, 4])
            try mainPhase(&state); try state.setTrap(player: 0, cardID: handID(state, 0, 4))
            let counter = state.players[0].traps[0].id
            try finishTurn(&state); try mainPhase(&state)
            try state.setTrap(player: 1, cardID: handID(state, 1, 4))
            let sameTurnTrap = state.players[1].traps[0].id
            try state.activateSpell(player: 1, cardID: handID(state, 1, 1))
            try state.activateCounter(player: 0, trapID: counter)
            precondition(state.players[0].lp == 4000 && state.chain.count == 2 && state.players[1].deck.count == 34)
            reject(&state) { try $0.activateCounter(player: 1, trapID: sameTurnTrap) }
            try resolve(&state)
            precondition(state.players[1].deck.count == 34 && state.players[1].graveyard.count == 1)
            precondition(state.players[0].graveyard.count == 1); conserved(state)
        }

        // Three links: the last Judgment negates the first Judgment, so the original spell resolves.
        do {
            var state = try game([4, 1], [4])
            try mainPhase(&state); try state.setTrap(player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try mainPhase(&state)
            try state.setTrap(player: 1, cardID: handID(state, 1, 4))
            try finishTurn(&state); try mainPhase(&state)
            let cardsBefore = state.players[0].hand.count
            try state.activateSpell(player: 0, cardID: handID(state, 0, 1))
            try state.activateCounter(player: 1, trapID: state.players[1].traps[0].id)
            try state.activateCounter(player: 0, trapID: state.players[0].traps[0].id)
            precondition(state.chain.count == 3 && state.players.allSatisfy { $0.lp == 4000 })
            conserved(state); try resolve(&state)
            precondition(state.players[0].hand.count == cardsBefore + 1)
            precondition(state.players[0].graveyard.count == 2 && state.players[1].graveyard.count == 1)
            conserved(state)
        }

        // A player can counter their own activation after the opponent passes; payment is not refunded.
        do {
            var state = try game([4, 2])
            try mainPhase(&state); try state.setTrap(player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 2))
            try state.pass(player: 1)
            try state.activateCounter(player: 0, trapID: state.players[0].traps[0].id)
            try resolve(&state)
            precondition(state.players[0].lp == 4000 && state.players[1].lp == 8000)
            conserved(state)
        }

        // Pot cannot be activated without two cards available; rejection preserves hand/deck/priority.
        do {
            var state = try game([1])
            while state.players[0].deck.count > 1 || state.activePlayer != 0 { try finishTurn(&state) }
            try mainPhase(&state)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 1)) }
            conserved(state)
        }

        // End-phase discard is explicit; an exhausted deck and zero LP end actions until restart.
        do {
            var state = try game([1, 1])
            try mainPhase(&state)
            for _ in 0..<2 { try state.activateSpell(player: 0, cardID: handID(state, 0, 1)); try resolve(&state) }
            try state.nextPhase(player: 0)
            precondition(state.players[0].hand.count == 7)
            reject(&state) { try $0.nextPhase(player: 0) }
            reject(&state) { try $0.discard(player: 0, cardIDs: []) }
            try finishTurn(&state)
            while state.winner == nil { try finishTurn(&state) }
            precondition(state.finishReason?.contains("rút") == true)
            reject(&state) { try $0.nextPhase(player: $0.activePlayer) }
            conserved(state); state.restart(); precondition(state.winner == nil && state.turn == 1)
        }
        do {
            var state = try game([], [106])
            try finishTurn(&state); try mainPhase(&state)
            try state.summon(player: 1, cardID: handID(state, 1, 106)); try state.nextPhase(player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id)
            precondition(state.winner == 1 && state.players[0].lp == 0)
            reject(&state) { try $0.nextPhase(player: 1) }
            conserved(state)
        }
        print("DuelState: all behavioral checks passed")
    }
}
