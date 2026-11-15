import Foundation

// Authored for later execution with DuelState.swift + DuelAI.swift; not run while builds are paused.
@main
enum DuelAIChecks {
    static let definitions: [Int: DuelCardDefinition] = {
        var result: [Int: DuelCardDefinition] = [:]
        for id in 100...139 {
            result[id] = DuelCardDefinition(id: id, name: "Normal \(id)", kindCode: 0,
                                           level: id < 130 ? 4 : 7,
                                           atk: 1_000 + (id % 10) * 100, def: 900 + (id % 7) * 200,
                                           password: nil)
        }
        let effects: [(Int, UInt32, Int)] = [
            (1, 55_144_522, 13), (2, 76_103_675, 13), (3, 84_257_639, 13), (4, 41_420_027, 14),
            (5, 83_764_718, 13), (6, 911_883, 13), (7, 12_580_477, 13), (8, 53_129_443, 13),
            (9, 5_318_639, 13), (10, 44_095_762, 14)
        ]
        for (id, password, kind) in effects {
            result[id] = DuelCardDefinition(id: id, name: "Effect \(id)", kindCode: kind,
                                           level: 0, atk: nil, def: nil, password: password)
        }
        return result
    }()

    static func deck(_ prefix: [Int] = [], fillers: [Int] = Array(110...129)) -> [Int] {
        var cards = prefix
        for id in fillers {
            while cards.count < 40 && cards.filter({ $0 == id }).count < 3 { cards.append(id) }
        }
        precondition(cards.count == 40)
        return cards
    }
    static func state(_ first: [Int] = [], _ second: [Int] = []) throws -> DuelState {
        try DuelState(definitions: definitions, decks: [deck(first), deck(second)])
    }
    static func mainPhase(_ game: inout DuelState) throws {
        try settle(&game)
        if game.phase == .draw { try advance(&game) }
        if game.phase == .standby { try advance(&game) }
        precondition(game.phase == .main1)
    }
    static func settle(_ game: inout DuelState) throws {
        var steps = 0
        while game.hasResponseWindow && game.winner == nil {
            precondition(game.pendingSummonChoice == nil, "Choose a search target explicitly in this test")
            try game.pass(player: game.decisionPlayer)
            steps += 1
            precondition(steps < 160, "Unbounded response-window continuation")
        }
    }
    static func advance(_ game: inout DuelState) throws {
        try settle(&game)
        try game.nextPhase(player: game.activePlayer)
        try settle(&game)
    }
    static func finishTurn(_ game: inout DuelState) throws {
        try settle(&game)
        while game.phase != .end { try advance(&game) }
        let player = game.activePlayer, excess = game.players[game.activePlayer].hand.count - 6
        if excess > 0 { try game.discard(player: player, cardIDs: game.players[player].hand.suffix(excess).map(\.id)) }
        try advance(&game)
    }
    static func hand(_ game: DuelState, player: Int, definition: Int) -> Int {
        game.players[player].hand.first { $0.definitionID == definition }!.id
    }
    static func conserved(_ game: DuelState) {
        var ids = game.chain.filter(\.sourceOnField).map { $0.card.id }
        if let summon = game.pendingSummon { ids.append(summon.monster.card.id) }
        for player in game.players {
            ids += (player.deck + player.hand + player.graveyard).map(\.id)
            ids += player.field.map(\.id) + player.traps.map(\.id)
        }
        precondition(ids.count == 80 && Set(ids).count == 80, "AI action lost or duplicated cards")
    }
    static func controller(_ game: DuelState) -> Int {
        game.decisionPlayer
    }
    static func shuffled(_ cards: [Int], seed: UInt64) -> [Int] {
        var values = cards, next = seed
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            next = next &* 6_364_136_223_846_793_005 &+ 1
            values.swapAt(index, Int(next % UInt64(index + 1)))
        }
        return values
    }

    static func main() throws {
        // The AI stops when it lacks priority; a choice is deterministic and accepted by the real core.
        do {
            var game = try state()
            precondition(DuelAI.chooseAction(state: game, player: 1) == nil)
            precondition(DuelAI.chooseAction(state: game, player: -1) == nil)
            try finishTurn(&game)
            let action = DuelAI.chooseAction(state: game, player: 1)!
            precondition(action == DuelAI.chooseAction(state: game, player: 1))
            try game.apply(action: action, player: 1)
            conserved(game)
        }

        // Different opponent hands, Deck order and set-monster identities produce the same AI attack.
        do {
            var first = try DuelState(definitions: definitions,
                decks: [deck([100, 101, 102, 103, 104]), deck([109])])
            var second = try DuelState(definitions: definitions,
                decks: [deck([108, 107, 106, 105, 100], fillers: Array((110...129).reversed())), deck([109])])
            for index in 0..<2 {
                var game = index == 0 ? first : second
                try mainPhase(&game)
                try game.summon(player: 0, cardID: game.players[0].hand[0].id, set: true)
                try finishTurn(&game); try mainPhase(&game)
                try game.summon(player: 1, cardID: hand(game, player: 1, definition: 109))
                try advance(&game)
                if index == 0 { first = game } else { second = game }
            }
            precondition(DuelAI.observe(first, player: 1)!.opponentField[0].definition == nil)
            precondition(DuelAI.observe(second, player: 1)!.opponentField[0].definition == nil)
            let action = DuelAI.chooseAction(state: first, player: 1)!
            precondition(action == DuelAI.chooseAction(state: second, player: 1))
            precondition(action == .attack(attackerID: first.players[1].field[0].id,
                                          targetID: first.players[0].field[0].id))
            try first.apply(action: action, player: 1)
            try second.apply(action: action, player: 1)
            conserved(first); conserved(second)
        }

        // Own future draw order must not affect strategy before the legal Dai search opens.
        do {
            let own = deck([6, 100, 101, 102, 103, 104])
            let reordered = Array(own.prefix(6)) + Array(own.dropFirst(6).reversed())
            var first = try DuelState(definitions: definitions, decks: [deck(), own])
            var second = try DuelState(definitions: definitions, decks: [deck(), reordered])
            try finishTurn(&first); try mainPhase(&first)
            try finishTurn(&second); try mainPhase(&second)
            precondition(DuelAI.observe(first, player: 1)!.searchCandidates == nil)
            precondition(DuelAI.observe(first, player: 1)!.daiActivationLegal)
            let action = DuelAI.chooseAction(state: first, player: 1)!
            precondition(action == DuelAI.chooseAction(state: second, player: 1))
            try first.apply(action: action, player: 1)
            precondition(DuelAI.chooseAction(state: first, player: 1) == nil)
            try first.pass(player: 0); try first.pass(player: 1)
            precondition(first.pendingSummonChoice != nil)
            let choice = DuelAI.chooseAction(state: first, player: 1)!
            try first.apply(action: choice, player: 1)
            precondition(first.pendingSummonChoice == nil && !first.isResolving)
            precondition(first.players[1].field.count == 1)
            conserved(first)
        }

        // Dai is not offered when the remaining Deck contains no legal Normal <=4 target.
        do {
            let own = deck([6, 100, 101, 102, 103, 104], fillers: Array(130...139) + Array(1...5))
            var game = try DuelState(definitions: definitions, decks: [deck(), own])
            try finishTurn(&game); try mainPhase(&game)
            precondition(!DuelAI.observe(game, player: 1)!.daiActivationLegal)
            let action = DuelAI.chooseAction(state: game, player: 1)!
            precondition(action != .activateSpell(cardID: hand(game, player: 1, definition: 6),
                                                 targetID: nil, targetPlayer: nil, position: .attack))
            try game.apply(action: action, player: 1)
            conserved(game)
        }

        // A previously set counter reacts to a useful opponent Spell, then waits for human priority.
        do {
            var game = try state([1], [4])
            try finishTurn(&game); try mainPhase(&game)
            try game.setTrap(player: 1, cardID: hand(game, player: 1, definition: 4))
            try finishTurn(&game); try mainPhase(&game)
            try game.activateSpell(player: 0, cardID: hand(game, player: 0, definition: 1))
            let action = DuelAI.chooseAction(state: game, player: 1)!
            precondition(action == .counter(trapID: game.players[1].traps[0].id))
            try game.apply(action: action, player: 1)
            precondition(game.players[1].lp == 4000 && game.chain.count == 2)
            precondition(DuelAI.chooseAction(state: game, player: 1) == nil)
            conserved(game)
        }

        // A set MST can answer a phase-exit request. Opponent set-card identities do not affect its target.
        do {
            var decisions: [DuelAction] = []
            for hiddenCard in [4, 9] {
                var game = try state([hiddenCard], [9])
                try mainPhase(&game)
                try game.setTrap(player: 0, cardID: hand(game, player: 0, definition: hiddenCard))
                try finishTurn(&game); try mainPhase(&game)
                try game.setTrap(player: 1, cardID: hand(game, player: 1, definition: 9))
                try finishTurn(&game); try mainPhase(&game)
                let oldPhase = game.phase
                try game.nextPhase(player: 0)
                precondition(game.hasResponseWindow && game.decisionPlayer == 1)
                let action = DuelAI.chooseAction(state: game, player: 1)!
                decisions.append(action)
                precondition(action == .activateSpell(cardID: game.players[1].traps[0].id,
                    targetID: game.players[0].traps[0].id, targetPlayer: 0, position: .attack))
                try game.apply(action: action, player: 1)
                try settle(&game)
                precondition(game.phase == oldPhase && game.players[0].traps.isEmpty)
                conserved(game)
            }
            precondition(decisions[0] == decisions[1])
        }

        // Do not spend MST on a Spell already activated; destruction is not negation.
        do {
            var game = try state([1], [9])
            try finishTurn(&game); try mainPhase(&game)
            try game.setTrap(player: 1, cardID: hand(game, player: 1, definition: 9))
            try finishTurn(&game); try mainPhase(&game)
            try game.activateSpell(player: 0, cardID: hand(game, player: 0, definition: 1))
            precondition(DuelAI.chooseAction(state: game, player: 1) == .pass)
            try settle(&game)
            precondition(game.players[1].traps.count == 1)
            conserved(game)
        }

        // Mirror Force answers an opposing attack; even MST destroying its source does not negate it.
        do {
            var game = try state([109, 9], [10])
            try mainPhase(&game)
            try game.summon(player: 0, cardID: hand(game, player: 0, definition: 109))
            try finishTurn(&game); try mainPhase(&game)
            try game.setTrap(player: 1, cardID: hand(game, player: 1, definition: 10))
            try finishTurn(&game); try mainPhase(&game); try advance(&game)
            try game.attack(player: 0, attackerID: game.players[0].field[0].id)
            precondition(DuelAI.chooseAction(state: game, player: 1) == nil)
            try game.pass(player: 0)
            let mirror = game.players[1].traps[0].id
            let action = DuelAI.chooseAction(state: game, player: 1)!
            precondition(action == .activateSpell(cardID: mirror, targetID: nil, targetPlayer: nil, position: .attack))
            try game.apply(action: action, player: 1)
            try game.activateSpell(player: 0, cardID: hand(game, player: 0, definition: 9),
                                   targetID: mirror, targetPlayer: 1)
            conserved(game); try settle(&game)
            precondition(game.players[0].field.isEmpty && game.players[1].lp == 8000)
            precondition(game.players[1].graveyard.contains { $0.id == mirror })
            conserved(game)
        }

        // Judgment responds before the opposing summon succeeds; no AI privilege bypasses the cost/window.
        do {
            var game = try state([109], [4])
            try finishTurn(&game); try mainPhase(&game)
            try game.setTrap(player: 1, cardID: hand(game, player: 1, definition: 4))
            try finishTurn(&game); try mainPhase(&game)
            let monster = hand(game, player: 0, definition: 109)
            try game.summon(player: 0, cardID: monster)
            precondition(game.pendingSummon != nil && game.players[0].field.isEmpty)
            conserved(game)
            let action = DuelAI.chooseAction(state: game, player: 1)!
            precondition(action == .counter(trapID: game.players[1].traps[0].id))
            try game.apply(action: action, player: 1); try settle(&game)
            precondition(game.players[1].lp == 4000 && game.players[0].field.isEmpty)
            precondition(game.players[0].graveyard.contains { $0.id == monster })
            conserved(game)
        }

        // Speed 2 MST cannot answer speed 3, and hand MST cannot activate during the opponent's turn.
        do {
            var game = try state([1, 4, 4], [9])
            try mainPhase(&game)
            for _ in 0..<2 {
                try game.setTrap(player: 0, cardID: hand(game, player: 0, definition: 4))
                try settle(&game)
            }
            try finishTurn(&game); try mainPhase(&game)
            try game.setTrap(player: 1, cardID: hand(game, player: 1, definition: 9))
            try finishTurn(&game); try mainPhase(&game)
            try game.activateSpell(player: 0, cardID: hand(game, player: 0, definition: 1))
            try game.pass(player: 1)
            try game.activateCounter(player: 0, trapID: game.players[0].traps[0].id)
            precondition(!game.players[0].traps.isEmpty)
            precondition(DuelAI.chooseAction(state: game, player: 1) == .pass)
            try settle(&game); conserved(game)
        }
        do {
            var game = try state([4], [9])
            try mainPhase(&game)
            try game.setTrap(player: 0, cardID: hand(game, player: 0, definition: 4))
            try settle(&game)
            try game.nextPhase(player: 0)
            precondition(game.decisionPlayer == 1)
            precondition(DuelAI.chooseAction(state: game, player: 1) == .pass)
            conserved(game)
        }

        // Multiple full matches: every decision uses production apply, makes legal progress, and conserves cards.
        // The UI has a separate 160-action continuation budget; this test also guards against strategy loops.
        let pool = deck([1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 9, 9, 10, 130, 131])
        for seed in UInt64(1)...UInt64(12) {
            var game = try DuelState(definitions: definitions,
                                    decks: [shuffled(pool, seed: seed), shuffled(pool, seed: seed + 100)])
            var actions = 0, sameControllerSteps = 0, previousController = -1
            while game.winner == nil && actions < 10_000 {
                let player = controller(game)
                sameControllerSteps = player == previousController ? sameControllerSteps + 1 : 1
                precondition(sameControllerSteps <= 160, "AI continuation exceeded UI budget")
                previousController = player
                guard let action = DuelAI.chooseAction(state: game, player: player) else {
                    preconditionFailure("AI stopped while it had legal priority")
                }
                try game.apply(action: action, player: player)
                conserved(game)
                actions += 1
            }
            precondition(game.winner != nil && actions < 10_000, "AI match did not terminate")
            precondition(DuelAI.chooseAction(state: game, player: 0) == nil)
            precondition(DuelAI.chooseAction(state: game, player: 1) == nil)
        }
        print("DuelAI: decision, privacy and legal-match checks passed")
    }
}
