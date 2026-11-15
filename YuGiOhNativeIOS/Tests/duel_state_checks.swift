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
            (3, "Dian Keto the Cure Master", 13, 84_257_639), (4, "Solemn Judgment", 14, 41_420_027),
            (5, "Monster Reborn", 13, 83_764_718), (6, "Unexpected Dai", 13, 911_883),
            (7, "Raigeki", 13, 12_580_477), (8, "Dark Hole", 13, 53_129_443),
            (9, "Mystical Space Typhoon", 13, 5_318_639), (10, "Mirror Force", 14, 44_095_762)
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
    static func settle(_ state: inout DuelState) throws {
        var passes = 0
        while state.hasResponseWindow && state.chain.isEmpty && state.winner == nil && state.pendingSummonChoice == nil {
            try state.pass(player: state.decisionPlayer)
            passes += 1
            precondition(passes <= 12, "Response window did not settle")
        }
    }
    static func advance(_ state: inout DuelState, player: Int) throws {
        try state.nextPhase(player: player); try settle(&state)
    }
    static func summoned(_ state: inout DuelState, player: Int, cardID: Int, tributes: [Int] = [], set: Bool = false) throws {
        try state.summon(player: player, cardID: cardID, tributes: tributes, set: set); try settle(&state)
    }
    static func trapSet(_ state: inout DuelState, player: Int, cardID: Int) throws {
        try state.setTrap(player: player, cardID: cardID); try settle(&state)
    }
    static func battled(_ state: inout DuelState, player: Int, attackerID: Int, targetID: Int? = nil) throws {
        try state.attack(player: player, attackerID: attackerID, targetID: targetID); try settle(&state)
    }
    static func positionChanged(_ state: inout DuelState, player: Int, monsterID: Int) throws {
        try state.changePosition(player: player, monsterID: monsterID); try settle(&state)
    }
    static func mainPhase(_ state: inout DuelState) throws {
        if state.phase == .draw { try advance(&state, player: state.activePlayer) }
        if state.phase == .standby { try advance(&state, player: state.activePlayer) }
        precondition(state.phase == .main1)
    }
    static func finishTurn(_ state: inout DuelState) throws {
        while state.phase != .end { try advance(&state, player: state.activePlayer) }
        let player = state.activePlayer
        let excess = state.players[player].hand.count - 6
        if excess > 0 {
            try state.discard(player: player, cardIDs: Array(state.players[player].hand.suffix(excess)).map(\.id))
        }
        try advance(&state, player: player)
    }
    static func resolve(_ state: inout DuelState) throws {
        try state.pass(player: state.priorityPlayer)
        precondition(!state.chain.isEmpty)
        try state.pass(player: state.priorityPlayer)
        precondition(state.chain.isEmpty)
        try settle(&state)
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
        precondition(before.isResolving == state.isResolving && before.pendingSummonChoice == state.pendingSummonChoice)
        precondition(before.pendingAttack == state.pendingAttack && before.pendingSummon == state.pendingSummon)
        precondition(before.hasResponseWindow == state.hasResponseWindow && before.responseLabel == state.responseLabel)
    }
    static func conserved(_ state: DuelState, total: Int = 80) {
        var ids = state.chain.filter(\.sourceOnField).map { $0.card.id }
        if let pending = state.pendingSummon { ids.append(pending.monster.card.id) }
        for (owner, player) in state.players.enumerated() {
            ids += (player.deck + player.hand + player.graveyard).map(\.id)
            ids += player.field.map(\.id) + player.traps.map(\.id)
            precondition((player.deck + player.hand + player.graveyard).allSatisfy { $0.owner == owner }, "Wrong graveyard/hand/deck owner")
        }
        precondition(ids.count == total && Set(ids).count == total, "Lost or duplicated physical cards")
    }

    static func main() throws {
        // Runtime shuffling can be replayed with the same seed, including after restart.
        do {
            var first = try DuelState(definitions: definitions, decks: [deck([6]), deck()], shuffle: true, shuffleSeed: 42)
            let second = try DuelState(definitions: definitions, decks: [deck([6]), deck()], shuffle: true, shuffleSeed: 42)
            precondition(first.players == second.players)
            first.restart(shuffle: true)
            precondition(first.players == second.players)
            conserved(first)
        }
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
            try advance(&state, player: 0)
            precondition(state.phase == .end && state.players[0].hand.count == 5)
            try advance(&state, player: 0)
            precondition(state.turn == 2 && state.activePlayer == 1 && state.players[1].hand.count == 6)
            precondition(state.players[0].hand.count == 5)
            try mainPhase(&state)
            try advance(&state, player: 1); precondition(state.phase == .battle)
            try advance(&state, player: 1); precondition(state.phase == .main2)
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
            try summoned(&state, player: 0, cardID: small)
            reject(&state) { try $0.summon(player: 0, cardID: handID($0, 0, 101)) }
            reject(&state) { try $0.changePosition(player: 0, monsterID: small) }
            try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
            reject(&state) { try $0.summon(player: 0, cardID: high, tributes: [small, small]) }
            try summoned(&state, player: 0, cardID: tribute, tributes: [small], set: true)
            precondition(state.players[0].field.count == 1 && state.players[0].field[0].faceDown)
            precondition(state.players[0].graveyard.map(\.id) == [small])
            conserved(state)
        }

        // Full field and two-tribute summon: tribute validation frees the proper slots.
        do {
            var state = try game([100, 101, 102, 103, 105, 110])
            for monster in [100, 101, 102, 103, 110] {
                try mainPhase(&state)
                try summoned(&state, player: 0, cardID: handID(state, 0, monster))
                try finishTurn(&state); try finishTurn(&state)
            }
            try mainPhase(&state)
            reject(&state) { try $0.summon(player: 0, cardID: $0.players[0].hand.last!.id) }
            let tributes = state.players[0].field.prefix(2).map(\.id)
            try summoned(&state, player: 0, cardID: handID(state, 0, 105), tributes: tributes)
            precondition(state.players[0].field.count == 4 && state.players[0].graveyard.count >= 2)
            conserved(state)
        }

        // ATK/ATK target requirement, LP difference, destruction, and once per monster.
        do {
            var state = try game([100], [101])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 100))
            let target = state.players[0].field[0].id
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 101))
            let attacker = state.players[1].field[0].id
            try advance(&state, player: 1)
            reject(&state) { try $0.attack(player: 1, attackerID: attacker) }
            try battled(&state, player: 1, attackerID: attacker, targetID: target)
            precondition(state.players[0].lp == 7000 && state.players[0].field.isEmpty)
            reject(&state) { try $0.attack(player: 1, attackerID: attacker) }
            conserved(state)
        }

        // ATK ties destroy both except 0/0; DEF ties leave both alive.
        for id in [100, 103] {
            var state = try game([id], [id])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, id))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, id)); try advance(&state, player: 1)
            try battled(&state, player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players[0].field.count == (id == 103 ? 1 : 0))
            precondition(state.players[1].field.count == (id == 103 ? 1 : 0))
            precondition(state.players.allSatisfy { $0.lp == 8000 }); conserved(state)
        }
        for defenderID in [100, 102] {
            var state = try game([defenderID], [101])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, defenderID), set: true)
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 101)); try advance(&state, player: 1)
            try battled(&state, player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players[0].lp == 8000)
            precondition(state.players[1].lp == (defenderID == 102 ? 7500 : 8000))
            precondition(state.players[0].field.count == (defenderID == 102 ? 1 : 0))
            if defenderID == 102 { precondition(!state.players[0].field[0].faceDown) }
            conserved(state)
        }
        do {
            var state = try game([100], [100])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 100), set: true)
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 100)); try advance(&state, player: 1)
            try battled(&state, player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
            precondition(state.players.allSatisfy { $0.field.count == 1 && $0.lp == 8000 })
            try advance(&state, player: 1)
            reject(&state) { try $0.changePosition(player: 1, monsterID: $0.players[1].field[0].id) }
            try finishTurn(&state); try mainPhase(&state)
            let monsterID = state.players[0].field[0].id
            try positionChanged(&state, player: 0, monsterID: monsterID)
            precondition(state.players[0].field[0].position == .attack && !state.players[0].field[0].faceDown)
            reject(&state) { try $0.changePosition(player: 0, monsterID: monsterID) }
            conserved(state)
        }
        do {
            var state = try game([101], [100])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 101))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 100)); try advance(&state, player: 1)
            try battled(&state, player: 1, attackerID: state.players[1].field[0].id, targetID: state.players[0].field[0].id)
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
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
            let counter = state.players[0].traps[0].id
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
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
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
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
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
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
            try advance(&state, player: 0)
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
            try summoned(&state, player: 1, cardID: handID(state, 1, 106)); try advance(&state, player: 1)
            try battled(&state, player: 1, attackerID: state.players[1].field[0].id)
            precondition(state.winner == 1 && state.players[0].lp == 0)
            reject(&state) { try $0.nextPhase(player: 1) }
            conserved(state)
        }

        // Reborn respects the original owner after tribute/destruction and does not consume Normal Summon.
        do {
            var state = try game([101, 5, 5, 8, 104], [100])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 101))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 100)); try advance(&state, player: 1)
            let opponentCard = state.players[1].field[0].card
            try battled(&state, player: 1, attackerID: opponentCard.id, targetID: state.players[0].field[0].id)
            try finishTurn(&state); try mainPhase(&state)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 5), targetID: opponentCard.id, targetPlayer: 0) }
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 5), targetID: opponentCard.id, targetPlayer: 2) }
            try state.apply(action: .activateSpell(cardID: handID(state, 0, 5), targetID: opponentCard.id, targetPlayer: 1, position: .defense), player: 0)
            precondition(state.players[1].graveyard.contains(opponentCard) && state.players[0].field.count == 1)
            try resolve(&state)
            precondition(state.players[0].field.last!.card == opponentCard && state.players[0].field.last!.position == .defense)
            precondition(!state.normalSummonUsed && state.players[1].graveyard.isEmpty)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 5), targetID: opponentCard.id, targetPlayer: 1) }
            try state.apply(action: .summon(cardID: handID(state, 0, 104), tributes: [opponentCard.id], set: false), player: 0)
            try settle(&state)
            precondition(state.players[1].graveyard.contains(opponentCard) && state.normalSummonUsed)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 5), targetID: opponentCard.id, targetPlayer: 1)
            try resolve(&state)
            precondition(state.normalSummonUsed && state.players[0].field.count == 3)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 8)); try resolve(&state)
            precondition(state.players.allSatisfy { $0.field.isEmpty })
            precondition(state.players[1].graveyard == [opponentCard])
            conserved(state)
        }

        // Reborn targets only a Normal monster already in a graveyard; negation leaves it there.
        do {
            var state = try game([100, 5, 2], [101, 4])
            try mainPhase(&state)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 5)) }
            try state.activateSpell(player: 0, cardID: handID(state, 0, 2)); try resolve(&state)
            let spellInGrave = state.players[0].graveyard[0].id
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 5), targetID: spellInGrave, targetPlayer: 0) }
            try summoned(&state, player: 0, cardID: handID(state, 0, 100))
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
            try summoned(&state, player: 1, cardID: handID(state, 1, 101)); try advance(&state, player: 1)
            let target = state.players[0].field[0].card
            try battled(&state, player: 1, attackerID: state.players[1].field[0].id, targetID: target.id)
            try finishTurn(&state); try mainPhase(&state)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 5), targetID: target.id, targetPlayer: 0)
            try state.activateCounter(player: 1, trapID: state.players[1].traps[0].id); try resolve(&state)
            precondition(state.players[0].field.isEmpty && state.players[0].graveyard.contains(target))
            conserved(state)
        }
        do {
            var state = try game([100, 101, 102, 104, 5])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 100))
            let target = state.players[0].field[0].id
            try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 0, cardID: handID(state, 0, 101))
            try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 0, cardID: handID(state, 0, 104), tributes: [target])
            for _ in 0..<3 {
                try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
                let normal = state.players[0].hand.first { state.definition(of: $0).kindCode == 0 && state.definition(of: $0).level <= 4 }!
                try summoned(&state, player: 0, cardID: normal.id)
            }
            precondition(state.players[0].field.count == 5)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 5), targetID: target, targetPlayer: 0) }
            conserved(state)
        }

        // Dai has no target at activation: selection happens only after both players pass.
        do {
            var state = try game([6, 6, 100])
            try mainPhase(&state)
            let dai = handID(state, 0, 6)
            reject(&state) { try $0.activateSpell(player: 0, cardID: dai, targetID: $0.players[0].deck[0].id, targetPlayer: 0) }
            try state.apply(action: .activateSpell(cardID: dai, targetID: nil, targetPlayer: nil, position: .attack), player: 0)
            precondition(state.pendingSummonChoice == nil && !state.isResolving)
            try state.pass(player: 1); try state.pass(player: 0)
            precondition(state.isResolving && !state.chain.isEmpty && state.pendingSummonChoice?.player == 0)
            let choice = state.pendingSummonChoice!
            precondition(choice.candidates.allSatisfy { state.definition(of: $0).kindCode == 0 && state.definition(of: $0).level <= 4 })
            let selected = choice.candidates[0]
            reject(&state) { try $0.pass(player: 0) }
            reject(&state) { try $0.nextPhase(player: 0) }
            reject(&state) { try $0.chooseSpecialSummon(player: 1, cardID: selected.id) }
            reject(&state) { try $0.chooseSpecialSummon(player: 0, cardID: handID($0, 0, 100)) }
            let deckBefore = Set(state.players[0].deck.map(\.id))
            try state.apply(action: .chooseSpecialSummon(cardID: selected.id, position: .defense), player: 0)
            try settle(&state)
            precondition(!state.isResolving && state.pendingSummonChoice == nil && state.chain.isEmpty)
            precondition(!state.normalSummonUsed && state.players[0].field[0].position == .defense && !state.players[0].field[0].faceDown)
            precondition(Set(state.players[0].deck.map(\.id)) == deckBefore.subtracting([selected.id]))
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 6)) }
            try summoned(&state, player: 0, cardID: handID(state, 0, 100))
            precondition(state.normalSummonUsed && state.players[0].field.count == 2)
            conserved(state)
        }

        // A negated Dai never asks for a summon and does not touch the deck; restart cancels a pending choice.
        do {
            var state = try game([4], [6])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try mainPhase(&state)
            let deckBefore = state.players[1].deck
            try state.activateSpell(player: 1, cardID: handID(state, 1, 6))
            try state.activateCounter(player: 0, trapID: state.players[0].traps[0].id); try resolve(&state)
            precondition(state.pendingSummonChoice == nil && state.players[1].deck == deckBefore && state.players[1].field.isEmpty)
            state = try game([6]); try mainPhase(&state)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 6)); try state.pass(player: 1); try state.pass(player: 0)
            precondition(state.isResolving)
            state.restart()
            precondition(!state.isResolving && state.pendingSummonChoice == nil && state.chain.isEmpty && state.players[0].deck.count == 35)
            conserved(state)
        }
        do {
            var highOnly = definitions
            for id in 100...129 {
                highOnly[id] = DuelCardDefinition(id: id, name: "High Normal \(id)", kindCode: 0,
                                                 level: 5, atk: 2000, def: 1000, password: nil)
            }
            var state = try DuelState(definitions: highOnly, decks: [deck([6]), deck()])
            try mainPhase(&state)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 6)) }
            conserved(state)
        }

        // Mass destruction includes face-down monsters, never causes battle damage, and costs a real spell.
        do {
            var state = try game([101, 7, 8], [100])
            try mainPhase(&state)
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 7)) }
            reject(&state) { try $0.activateSpell(player: 0, cardID: handID($0, 0, 8)) }
            try summoned(&state, player: 0, cardID: handID(state, 0, 101))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 100), set: true)
            let defender = state.players[1].field[0].card
            try finishTurn(&state); try mainPhase(&state)
            try state.activateSpell(player: 0, cardID: handID(state, 0, 7))
            precondition(state.players[1].field.count == 1)
            try resolve(&state)
            precondition(state.players[1].field.isEmpty && state.players[1].graveyard.contains(defender))
            precondition(state.players[0].field.count == 1 && state.players.allSatisfy { $0.lp == 8000 })
            try state.activateSpell(player: 0, cardID: handID(state, 0, 8)); try resolve(&state)
            precondition(state.players.allSatisfy { $0.field.isEmpty && $0.lp == 8000 })
            conserved(state)
        }
        // A phase exit exposes off-turn set MST; resolving that chain cancels the requested exit.
        do {
            var state = try game([9], [4])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 9))
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
            let target = state.players[1].traps[0].id
            try state.nextPhase(player: 1)
            precondition(state.phase == .main1 && state.decisionPlayer == 0)
            reject(&state) { try $0.summon(player: 1, cardID: $0.players[1].hand[0].id) }
            try state.activateSpell(player: 0, cardID: state.players[0].traps[0].id, targetID: target, targetPlayer: 1)
            try resolve(&state)
            precondition(state.phase == .main1 && state.players[1].traps.isEmpty)
            precondition(state.players[0].graveyard.count == 1 && state.players[1].graveyard.count == 1)
            try advance(&state, player: 1)
            precondition(state.phase == .battle); conserved(state)
        }

        // MST destroys an active source, not its effect; the card reaches the GY exactly once.
        do {
            var state = try game([1, 9])
            try mainPhase(&state)
            let pot = handID(state, 0, 1), mst = handID(state, 0, 9)
            try state.activateSpell(player: 0, cardID: pot)
            try state.pass(player: 1)
            reject(&state) { try $0.activateSpell(player: 0, cardID: mst, targetID: mst, targetPlayer: 0) }
            try state.activateSpell(player: 0, cardID: mst, targetID: pot, targetPlayer: 0)
            try resolve(&state)
            precondition(state.players[0].deck.count == 33 && state.players[0].hand.count == 5)
            precondition(state.players[0].graveyard.filter { $0.id == pot }.count == 1)
            precondition(state.players[0].graveyard.count == 2); conserved(state)
        }

        // A newly set MST cannot activate this turn; a Quick-Play hand card cannot answer on the opponent's turn.
        do {
            var state = try game([9, 2], [9])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 9))
            let sparks = handID(state, 0, 2)
            try state.activateSpell(player: 0, cardID: sparks)
            reject(&state) { try $0.activateSpell(player: 1, cardID: handID($0, 1, 9), targetID: sparks, targetPlayer: 0) }
            try state.pass(player: 1)
            reject(&state) { try $0.activateSpell(player: 0, cardID: $0.players[0].traps[0].id, targetID: sparks, targetPlayer: 0) }
            try state.pass(player: 0); try settle(&state)
            precondition(state.players[1].lp == 7800 && state.players[0].traps.count == 1); conserved(state)
        }
        do {
            var state = try game([4], [9])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try advance(&state, player: 1)
            precondition(state.phase == .standby && !state.hasResponseWindow)
            try state.activateSpell(player: 1, cardID: handID(state, 1, 9), targetID: state.players[0].traps[0].id, targetPlayer: 0)
            try resolve(&state)
            precondition(state.phase == .standby && state.players[0].traps.isEmpty)
            conserved(state)
        }

        // Judgment negates a would-be summon after tribute/quota payment, before the monster reaches the field.
        do {
            var state = try game([4], [100])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try mainPhase(&state)
            let monster = handID(state, 1, 100)
            try state.summon(player: 1, cardID: monster)
            precondition(state.pendingSummon?.monster.id == monster && state.players[1].field.isEmpty)
            precondition(state.normalSummonUsed && state.decisionPlayer == 0)
            conserved(state)
            try state.activateCounter(player: 0, trapID: state.players[0].traps[0].id); try resolve(&state)
            precondition(state.pendingSummon == nil && state.players[1].field.isEmpty && state.players[0].lp == 4000)
            precondition(state.players[1].graveyard.contains { $0.id == monster })
            reject(&state) { try $0.summon(player: 1, cardID: $0.players[1].hand[0].id) }
            conserved(state)
        }
        do {
            var state = try game([100, 104], [4])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 100))
            let tribute = state.players[0].field[0].card
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
            try finishTurn(&state); try mainPhase(&state)
            let high = handID(state, 0, 104)
            try state.summon(player: 0, cardID: high, tributes: [tribute.id])
            precondition(state.players[0].graveyard.contains(tribute) && state.players[0].field.isEmpty)
            precondition(state.pendingSummon?.monster.id == high && state.normalSummonUsed)
            conserved(state)
            try state.activateCounter(player: 1, trapID: state.players[1].traps[0].id); try resolve(&state)
            precondition(state.players[0].graveyard.contains(tribute) && state.players[0].graveyard.contains { $0.id == high })
            precondition(state.players[0].field.isEmpty && state.normalSummonUsed)
            conserved(state)
        }
        do {
            var state = try game([100], [4])
            try mainPhase(&state); try summoned(&state, player: 0, cardID: handID(state, 0, 100), set: true)
            let flipped = state.players[0].field[0].card
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
            try finishTurn(&state); try mainPhase(&state)
            try state.changePosition(player: 0, monsterID: flipped.id)
            precondition(state.pendingSummon?.isFlip == true && state.players[0].field.isEmpty && !state.normalSummonUsed)
            conserved(state)
            try state.activateCounter(player: 1, trapID: state.players[1].traps[0].id); try resolve(&state)
            precondition(state.players[0].graveyard.contains(flipped) && state.players[0].field.isEmpty)
            precondition(!state.normalSummonUsed)
            conserved(state)
        }

        // Mirror Force responds to declaration, destroys attackers, and prevents damage without negating an attack.
        do {
            var state = try game([10], [101])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 10))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 101)); try advance(&state, player: 1)
            let attacker = state.players[1].field[0].id
            try state.attack(player: 1, attackerID: attacker)
            precondition(state.players[0].lp == 8000 && state.pendingAttack?.declarationOpen == true)
            try state.pass(player: 1)
            try state.activateSpell(player: 0, cardID: state.players[0].traps[0].id)
            try resolve(&state)
            precondition(state.players[0].lp == 8000 && state.players[1].field.isEmpty && state.pendingAttack == nil)
            precondition(state.players[1].graveyard.contains { $0.id == attacker }); conserved(state)
        }
        do {
            var state = try game([10], [101, 9])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 10))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 101)); try advance(&state, player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id); try state.pass(player: 1)
            let mirror = state.players[0].traps[0].id
            try state.activateSpell(player: 0, cardID: mirror)
            try state.activateSpell(player: 1, cardID: handID(state, 1, 9), targetID: mirror, targetPlayer: 0)
            try resolve(&state)
            precondition(state.players[1].field.isEmpty && state.players[0].lp == 8000)
            precondition(state.players[0].graveyard.filter { $0.id == mirror }.count == 1)
            conserved(state)
        }

        // Mirror Force loses its declaration timing after a different chain has resolved.
        do {
            var state = try game([10, 4], [101, 9])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 10))
            try trapSet(&state, player: 0, cardID: handID(state, 0, 4))
            try finishTurn(&state); try mainPhase(&state)
            try summoned(&state, player: 1, cardID: handID(state, 1, 101)); try advance(&state, player: 1)
            try state.attack(player: 1, attackerID: state.players[1].field[0].id)
            let judgment = state.players[0].traps.first { state.definition(of: $0.card).effect == .judgment }!.id
            try state.activateSpell(player: 1, cardID: handID(state, 1, 9), targetID: judgment, targetPlayer: 0)
            try state.pass(player: 0); try state.pass(player: 1)
            precondition(state.pendingAttack?.declarationOpen == false && state.players[0].lp == 8000)
            try state.pass(player: 1)
            reject(&state) { try $0.activateSpell(player: 0, cardID: $0.players[0].traps[0].id) }
            try settle(&state)
            precondition(state.players[0].lp == 6000); conserved(state)
        }

        // A counter negating Mirror Force allows the declared attack to continue; Speed 2 cannot follow it.
        do {
            var state = try game([10], [4, 101, 9])
            try mainPhase(&state); try trapSet(&state, player: 0, cardID: handID(state, 0, 10))
            try finishTurn(&state); try mainPhase(&state)
            try trapSet(&state, player: 1, cardID: handID(state, 1, 4))
            try summoned(&state, player: 1, cardID: handID(state, 1, 101))
            try finishTurn(&state); try finishTurn(&state); try mainPhase(&state)
            try advance(&state, player: 1)
            let attacker = state.players[1].field[0].id
            try state.attack(player: 1, attackerID: attacker); try state.pass(player: 1)
            try state.activateSpell(player: 0, cardID: state.players[0].traps[0].id)
            try state.activateCounter(player: 1, trapID: state.players[1].traps[0].id)
            try state.pass(player: 0)
            reject(&state) { try $0.activateSpell(player: 1, cardID: handID($0, 1, 9), targetID: $0.chain.last!.card.id, targetPlayer: 1) }
            try state.pass(player: 1); try settle(&state)
            precondition(state.players[0].lp == 6000 && state.players[1].lp == 4000)
            precondition(state.players[1].field.count == 1); conserved(state)
        }
        print("DuelState: all behavioral checks passed")
    }
}
