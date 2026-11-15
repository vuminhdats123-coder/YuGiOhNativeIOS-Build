import Foundation

/// A bounded, deterministic training opponent. The UI executes one returned action at a time.
enum DuelAI {
    struct KnownCard {
        let id: Int
        let definition: DuelCardDefinition
        let canRevive: Bool
    }
    struct KnownMonster {
        let card: KnownCard
        let position: DuelState.Position
        let faceDown: Bool
        let summonedTurn: Int
        let positionChangedTurn: Int?
        let attacked: Bool
    }
    struct PublicMonster {
        let id: Int
        let position: DuelState.Position
        // A face-down opponent's identity and stats never enter the observation.
        let definition: DuelCardDefinition?
    }
    struct KnownSetCard {
        let card: KnownCard
        let setTurn: Int
        var id: Int { card.id }
    }
    struct ExtraChoice {
        let card: KnownCard
        let materialSets: [[Int]]
    }
    struct Replay {
        let attackerID: Int
        let targetIDs: [Int]
        let canAttackDirectly: Bool
    }
    struct Observation {
        let player: Int
        let activePlayer: Int
        let turn: Int
        let phase: DuelState.Phase
        let normalSummonUsed: Bool
        let life: Int
        let opponentLife: Int
        let deckCount: Int
        let hand: [KnownCard]
        let field: [KnownMonster]
        let traps: [KnownSetCard]
        let spellTrapZoneCount: Int
        let opponentField: [PublicMonster]
        let opponentSetIDs: [Int]
        let graveyards: [[KnownCard]]
        let chainEffect: DuelCardDefinition.Effect?
        let chainPlayer: Int?
        let counterTargetsAI: Bool
        let searchCandidates: [KnownCard]?
        let daiActivationLegal: Bool
        let fusionActivationLegal: Bool
        let fusionChoices: [ExtraChoice]?
        let synchroChoices: [ExtraChoice]
        let replay: Replay?
        let damageStage: DuelState.DamageStage?
        let battleDamage: Int
        let kuribohPending: Bool
        let hasResponseWindow: Bool
        let pendingAttacker: Int?
        let attackDeclarationOpen: Bool
        let pendingSummoner: Int?
        let pendingMonster: DuelCardDefinition?
    }

    static func chooseAction(state: DuelState, player: Int = 1) -> DuelAction? {
        guard let observation = observe(state, player: player) else { return nil }
        return chooseAction(observation)
    }

    static func observe(_ state: DuelState, player: Int) -> Observation? {
        guard (0..<2).contains(player), state.winner == nil, state.decisionPlayer == player else { return nil }
        guard !state.isResolving || state.pendingSummonChoice != nil || state.pendingFusionChoice != nil else { return nil }
        func known(_ card: DuelState.CardInstance) -> KnownCard {
            KnownCard(id: card.id, definition: state.definition(of: card), canRevive: state.canRevive(card))
        }
        // Pending selection is the only time the AI is allowed to inspect its own Deck contents.
        let search: [KnownCard]?
        if let pending = state.pendingSummonChoice {
            guard pending.player == player else { return nil }
            search = pending.candidates.map(known)
        } else {
            search = nil
        }
        let own = state.players[player]
        let opponent = state.players[1 - player]
        // Ask the production validator for legality only; never inspect its resulting state or Deck order.
        var daiActivationLegal = false
        var fusionActivationLegal = false
        if search == nil && !state.hasResponseWindow && (state.phase == .main1 || state.phase == .main2),
           let dai = own.hand.first(where: { state.definition(of: $0).effect == .recruitNormal }) {
            var trial = state
            do {
                try trial.apply(action: .activateSpell(cardID: dai.id, targetID: nil,
                                                      targetPlayer: nil, position: .attack), player: player)
                daiActivationLegal = true
            } catch { daiActivationLegal = false }
        }
        if !state.hasResponseWindow && !state.isResolving && (state.phase == .main1 || state.phase == .main2),
           let poly = own.hand.first(where: { state.definition(of: $0).effect == .fusion }) {
            var trial = state
            do {
                try trial.apply(action: .activateSpell(cardID: poly.id, targetID: nil,
                                                      targetPlayer: nil, position: .attack), player: player)
                fusionActivationLegal = true
            } catch { fusionActivationLegal = false }
        }
        let fusionChoices = state.pendingFusionChoice.map { choice in
            choice.candidates.map { ExtraChoice(card: known($0.extraCard), materialSets: $0.materialPairs) }
        }
        let synchroChoices = own.extraDeck.compactMap { card -> ExtraChoice? in
            let sets = state.synchroMaterialSets(player: player, extraCardID: card.id)
            return sets.isEmpty ? nil : ExtraChoice(card: known(card), materialSets: sets)
        }
        let damage = state.damageStep
        let prospectiveDamage = damage?.stage == .calculation && damage?.attack.player != player
            ? state.battleDamage(player: player) : 0
        let counterTarget = state.chain.last.flatMap { $0.negatesLinkID }
        let counterTargetsAI = counterTarget.flatMap { target in
            state.chain.first(where: { $0.id == target })?.player
        } == player || (state.chain.last?.negatesSummon == true && state.pendingSummon?.player == player)
        return Observation(
            player: player, activePlayer: state.activePlayer, turn: state.turn, phase: state.phase,
            normalSummonUsed: state.normalSummonUsed, life: own.lp,
            opponentLife: opponent.lp, deckCount: own.deck.count,
            hand: own.hand.map(known),
            field: own.field.map {
                KnownMonster(card: known($0.card), position: $0.position, faceDown: $0.faceDown,
                             summonedTurn: $0.summonedTurn, positionChangedTurn: $0.positionChangedTurn,
                             attacked: $0.attacked)
            },
            traps: own.traps.map { KnownSetCard(card: known($0.card), setTurn: $0.setTurn) },
            spellTrapZoneCount: own.traps.count + state.chain.filter { $0.player == player && $0.sourceOnField }.count,
            opponentField: opponent.field.map {
                PublicMonster(id: $0.id, position: $0.position,
                              definition: $0.faceDown ? nil : state.definition(of: $0.card))
            },
            opponentSetIDs: opponent.traps.map(\.id).sorted(),
            graveyards: state.players.map { $0.graveyard.map(known) },
            chainEffect: state.chain.last?.effect, chainPlayer: state.chain.last?.player,
            counterTargetsAI: counterTargetsAI,
            searchCandidates: search, daiActivationLegal: daiActivationLegal,
            fusionActivationLegal: fusionActivationLegal, fusionChoices: fusionChoices,
            synchroChoices: synchroChoices,
            replay: state.pendingReplay.map { Replay(attackerID: $0.attackerID,
                targetIDs: $0.targetIDs, canAttackDirectly: $0.canAttackDirectly) },
            damageStage: damage?.stage, battleDamage: prospectiveDamage,
            kuribohPending: state.chain.contains { $0.player == player && $0.effect == .kuriboh },
            hasResponseWindow: state.hasResponseWindow,
            pendingAttacker: state.pendingAttack?.player,
            attackDeclarationOpen: state.pendingAttack?.declarationOpen ?? false,
            pendingSummoner: state.pendingSummon?.player,
            pendingMonster: state.pendingSummon.map { state.definition(of: $0.monster.card) }
        )
    }

    static func chooseAction(_ view: Observation) -> DuelAction {
        if let choices = view.fusionChoices, let choice = bestExtraChoice(choices, view) {
            return .chooseFusion(extraCardID: choice.card.id, materialIDs: choice.materials,
                                 position: preferredPosition(choice.card.definition, view))
        }
        if let candidates = view.searchCandidates, let card = strongest(candidates) {
            return .chooseSpecialSummon(cardID: card.id, position: preferredPosition(card.definition, view))
        }
        if let replay = view.replay {
            guard let attacker = view.field.first(where: { $0.card.id == replay.attackerID }) else { return .cancelAttack }
            if let action = bestAttack([attacker], view: view), case .attack(_, let target) = action {
                if let target, replay.targetIDs.contains(target) { return .replayAttack(targetID: target) }
                if target == nil && replay.canAttackDirectly { return .replayAttack(targetID: nil) }
            }
            return .cancelAttack
        }
        if view.hasResponseWindow { return responseAction(view) }
        switch view.phase {
        case .draw, .standby: return .nextPhase
        case .main1, .main2: return mainAction(view)
        case .battle: return battleAction(view)
        case .end:
            let excess = view.hand.count - 6
            if excess > 0 {
                let cards = view.hand.sorted {
                    let left = handValue($0.definition, view), right = handValue($1.definition, view)
                    return left == right ? $0.id < $1.id : left < right
                }
                return .discard(cardIDs: cards.prefix(excess).map(\.id))
            }
            return .nextPhase
        }
    }

    private static func responseAction(_ view: Observation) -> DuelAction {
        if view.damageStage != nil {
            if view.damageStage == .calculation, view.battleDamage > 0, !view.kuribohPending,
               view.chainEffect != .judgment,
               let kuriboh = view.hand.sorted(by: { $0.id < $1.id }).first(where: { $0.definition.effect == .kuriboh }) {
                return .activateKuriboh(cardID: kuriboh.id)
            }
            return .pass
        }
        let ready = view.traps.filter { $0.setTurn < view.turn }.sorted { $0.id < $1.id }
        let judgment = ready.first { $0.card.definition.effect == .judgment }
        if let effect = view.chainEffect, view.chainPlayer != view.player,
           shouldCounter(effect, view), let judgment {
            return .counter(trapID: judgment.id)
        }
        if view.pendingSummoner != nil {
            if view.chainEffect == nil, view.pendingSummoner != view.player,
               let monster = view.pendingMonster, power(monster) >= 1_800, let judgment {
                return .counter(trapID: judgment.id)
            }
            return .pass
        }
        // Only Counter Traps (speed 3) may answer a Counter Trap.
        guard view.chainEffect != .judgment else { return .pass }
        if view.attackDeclarationOpen && view.pendingAttacker != nil && view.pendingAttacker != view.player,
           view.opponentField.contains(where: { $0.position == .attack && $0.definition != nil }),
           let mirror = ready.first(where: { $0.card.definition.effect == .mirrorForce }) {
            return .activateSpell(cardID: mirror.id, targetID: nil, targetPlayer: nil, position: .attack)
        }
        if let ced = ready.first(where: { $0.card.definition.effect == .returnMonster }),
           let target = view.opponentField.filter({ $0.definition != nil }).max(by: {
               let left = power($0.definition!), right = power($1.definition!)
               return left == right ? $0.id > $1.id : left < right
           }), power(target.definition!) >= 1_800 {
            return .activateSpell(cardID: ced.id, targetID: target.id,
                                  targetPlayer: 1 - view.player, position: .attack)
        }
        // Destroy a still-set card; destroying a source already on the Chain would not negate its effect.
        if let target = view.opponentSetIDs.first {
            if let mst = ready.first(where: { $0.card.definition.effect == .destroySpellTrap }) {
                return .activateSpell(cardID: mst.id, targetID: target,
                                      targetPlayer: 1 - view.player, position: .attack)
            }
            if view.activePlayer == view.player, view.spellTrapZoneCount < 5,
               let mst = view.hand.sorted(by: { $0.id < $1.id }).first(where: { $0.definition.effect == .destroySpellTrap }) {
                return .activateSpell(cardID: mst.id, targetID: target,
                                      targetPlayer: 1 - view.player, position: .attack)
            }
        }
        return .pass
    }

    private static func mainAction(_ view: Observation) -> DuelAction {
        var best: (score: Int, action: DuelAction)?
        func offer(_ score: Int, _ action: DuelAction) {
            if score > 0 && score > (best?.score ?? 0) { best = (score, action) }
        }
        let weakest = view.field.sorted {
            let left = power($0.card.definition), right = power($1.card.definition)
            return left == right ? $0.card.id < $1.card.id : left < right
        }
        for card in view.hand.sorted(by: { $0.id < $1.id }) {
            let definition = card.definition
            if definition.effect == .cyberDragon && view.field.isEmpty && !view.opponentField.isEmpty {
                offer(6_000 + power(definition), .specialSummonFromHand(cardID: card.id,
                      position: preferredPosition(definition, view)))
            }
            if definition.normalSummonable && !view.normalSummonUsed {
                let cost = definition.level >= 7 ? 2 : definition.level >= 5 ? 1 : 0
                if weakest.count >= cost && view.field.count - cost < 5 {
                    let tributes = Array(weakest.prefix(cost))
                    let lost = tributes.reduce(0) { $0 + power($1.card.definition) }
                    let gain = power(definition) - lost
                    if cost == 0 || gain > 0 {
                        offer(3_000 + gain - cost * 100,
                              .summon(cardID: card.id, tributes: tributes.map { $0.card.id },
                                      set: preferredPosition(definition, view) == .defense))
                    }
                }
                continue
            }
            guard let effect = definition.effect else { continue }
            if effect == .judgment || effect == .mirrorForce || effect == .returnMonster {
                if view.traps.count < 5 { offer(1_000, .setTrap(cardID: card.id)) }
                continue
            }
            guard view.traps.count < 5 else { continue }
            func spell(_ score: Int, target: Int? = nil, owner: Int? = nil,
                       position: DuelState.Position = .attack) {
                offer(score, .activateSpell(cardID: card.id, targetID: target,
                                           targetPlayer: owner, position: position))
            }
            switch effect {
            case .drawTwo: if view.deckCount >= 2 { spell(9_000) }
            case .damage200: spell(view.opponentLife <= 200 ? 100_000 : 2_000)
            case .heal1000: if view.life <= 7_000 { spell(2_500) }
            case .destroyOpponents:
                if !view.opponentField.isEmpty { spell(10_000 + view.opponentField.count * 500) }
            case .destroyAll:
                let ownPower = view.field.reduce(0) { $0 + power($1.card.definition) }
                let opposingPower = view.opponentField.reduce(0) { $0 + ($1.definition.map(power) ?? 1_500) }
                if !view.opponentField.isEmpty && opposingPower > ownPower {
                    spell(8_000 + opposingPower - ownPower)
                }
            case .revive:
                if view.field.count < 5 {
                    let targets = view.graveyards.enumerated().flatMap { owner, cards in
                        cards.filter(\.canRevive).map { (owner, $0) }
                    }.sorted {
                        let left = power($0.1.definition), right = power($1.1.definition)
                        return left == right ? $0.1.id < $1.1.id : left > right
                    }
                    if let (owner, target) = targets.first {
                        spell(7_000 + power(target.definition), target: target.id, owner: owner,
                              position: preferredPosition(target.definition, view))
                    }
                }
            case .recruitNormal:
                if view.daiActivationLegal { spell(7_500) }
            case .destroySpellTrap:
                if let target = view.opponentSetIDs.first {
                    spell(6_500, target: target, owner: 1 - view.player)
                } else { offer(1_000, .setTrap(cardID: card.id)) }
            case .fusion:
                if view.fusionActivationLegal { spell(6_500) }
            case .judgment, .mirrorForce, .kuriboh, .cyberDragon, .returnMonster: break
            }
        }
        if let choice = bestExtraChoice(view.synchroChoices, view) {
            let materialPower = materialValue(choice.materials, view)
            offer(5_000 + power(choice.card.definition) - materialPower,
                  .synchroSummon(extraCardID: choice.card.id, materialIDs: choice.materials,
                                 position: preferredPosition(choice.card.definition, view)))
        }
        if let target = view.opponentSetIDs.first,
           let mst = view.traps.filter({ $0.setTurn < view.turn && $0.card.definition.effect == .destroySpellTrap })
                .min(by: { $0.id < $1.id }) {
            offer(6_500, .activateSpell(cardID: mst.id, targetID: target,
                                       targetPlayer: 1 - view.player, position: .attack))
        }
        if let best { return best.action }
        for monster in view.field.sorted(by: { $0.card.id < $1.card.id }) {
            guard monster.summonedTurn != view.turn, monster.positionChangedTurn != view.turn,
                  !monster.attacked else { continue }
            let desired = preferredPosition(monster.card.definition, view)
            if desired != monster.position {
                return .changePosition(monsterID: monster.card.id)
            }
        }
        return .nextPhase
    }

    private static func battleAction(_ view: Observation) -> DuelAction {
        let attackers = view.field.filter { $0.position == .attack && !$0.faceDown && !$0.attacked }
            .sorted {
                let left = $0.card.definition.atk ?? 0, right = $1.card.definition.atk ?? 0
                return left == right ? $0.card.id < $1.card.id : left > right
            }
        return bestAttack(attackers, view: view) ?? .nextPhase
    }

    private static func bestAttack(_ attackers: [KnownMonster], view: Observation) -> DuelAction? {
        var best: (score: Int, action: DuelAction)?
        for attacker in attackers {
            let attack = attacker.card.definition.atk ?? 0
            if view.opponentField.isEmpty {
                return .attack(attackerID: attacker.card.id, targetID: nil)
            }
            for target in view.opponentField.sorted(by: { $0.id < $1.id }) {
                let score: Int
                if let definition = target.definition {
                    let stat = target.position == .attack ? definition.atk ?? 0 : definition.def ?? 0
                    if attack > stat {
                        score = 2_000 + power(definition) + (target.position == .attack ? attack - stat : 0)
                    } else if attack == stat && target.position == .attack && attack > 0 {
                        score = 50
                    } else { continue }
                } else {
                    // shortcut: probe unknown defenders with >=1000 ATK, replace with richer public-history reasoning later.
                    if attack < 1_000 { continue }
                    score = 100
                }
                if score > (best?.score ?? 0) {
                    best = (score, .attack(attackerID: attacker.card.id, targetID: target.id))
                }
            }
        }
        return best?.action
    }

    private static func materialValue(_ ids: [Int], _ view: Observation) -> Int {
        let cards = view.hand + view.field.map(\.card)
        return ids.reduce(0) { total, id in
            total + (cards.first(where: { $0.id == id }).map { power($0.definition) } ?? 100_000)
        }
    }

    private static func bestExtraChoice(_ choices: [ExtraChoice], _ view: Observation) -> (card: KnownCard, materials: [Int])? {
        var best: (card: KnownCard, materials: [Int], score: Int)?
        for choice in choices.sorted(by: { $0.card.id < $1.card.id }) {
            for materials in choice.materialSets.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                let score = power(choice.card.definition) - materialValue(materials, view)
                if best == nil || score > best!.score { best = (choice.card, materials, score) }
            }
        }
        return best.map { ($0.card, $0.materials) }
    }

    private static func strongest(_ cards: [KnownCard]) -> KnownCard? {
        cards.sorted {
            let left = power($0.definition), right = power($1.definition)
            return left == right ? $0.id < $1.id : left > right
        }.first
    }
    private static func power(_ card: DuelCardDefinition) -> Int { max(card.atk ?? 0, card.def ?? 0) }
    private static func preferredPosition(_ card: DuelCardDefinition, _ view: Observation) -> DuelState.Position {
        let attack = card.atk ?? 0, defense = card.def ?? 0
        let threats = view.opponentField.compactMap { $0.definition?.atk }.max() ?? 0
        if threats > attack || (defense > attack && (view.turn == 1 || attack == 0)) { return .defense }
        return .attack
    }
    private static func shouldCounter(_ effect: DuelCardDefinition.Effect, _ view: Observation) -> Bool {
        switch effect {
        case .damage200: return view.life <= 200
        case .heal1000: return false
        case .destroyOpponents, .destroyAll: return !view.field.isEmpty
        case .drawTwo, .revive, .recruitNormal: return true
        case .judgment: return view.counterTargetsAI
        case .destroySpellTrap: return false
        case .mirrorForce: return view.field.contains { $0.position == .attack && !$0.faceDown }
        case .kuriboh, .cyberDragon: return false
        case .returnMonster: return !view.field.isEmpty
        case .fusion: return true
        }
    }
    private static func handValue(_ card: DuelCardDefinition, _ view: Observation) -> Int {
        if card.effect == .kuriboh { return view.life <= 2_000 ? 4_000 : 1_500 }
        if card.normalSummonable {
            let cost = card.level >= 7 ? 2 : card.level >= 5 ? 1 : 0
            return power(card) - (view.field.count < cost ? 2_000 : cost * 500)
        }
        switch card.effect {
        case .drawTwo: return view.deckCount >= 2 ? 5_000 : 0
        case .revive, .recruitNormal, .destroyOpponents: return 4_000
        case .destroyAll: return 3_000
        case .judgment: return view.traps.count < 3 ? 2_500 : 500
        case .mirrorForce: return view.traps.count < 3 ? 3_000 : 500
        case .destroySpellTrap: return view.opponentSetIDs.isEmpty ? 1_000 : 3_000
        case .heal1000: return view.life < 4_000 ? 2_000 : 300
        case .damage200: return view.opponentLife <= 200 ? 10_000 : 200
        case .returnMonster: return view.traps.count < 3 ? 3_000 : 500
        case .fusion: return view.fusionActivationLegal ? 3_500 : 500
        case .kuriboh, .cyberDragon: return 1_500
        case nil: return 0
        }
    }
}
