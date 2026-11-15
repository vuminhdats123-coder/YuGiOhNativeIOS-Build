import Foundation

struct DuelCardDefinition: Identifiable, Hashable {
    let id: Int
    let name: String
    let kindCode: Int
    let level: Int
    let atk: Int?
    let def: Int?
    let password: UInt32?

    enum Effect: String {
        case drawTwo, damage200, heal1000, judgment
        case revive, recruitNormal, destroyOpponents, destroyAll
    }

    var effect: Effect? {
        switch (kindCode, password) {
        case (13, 55_144_522): return .drawTwo
        case (13, 76_103_675): return .damage200
        case (13, 84_257_639): return .heal1000
        case (14, 41_420_027): return .judgment
        case (13, 83_764_718): return .revive
        case (13, 911_883): return .recruitNormal
        case (13, 12_580_477): return .destroyOpponents
        case (13, 53_129_443): return .destroyAll
        default: return nil
        }
    }

    var supported: Bool {
        if kindCode == 0 {
            return (1...12).contains(level) && (atk ?? -1) >= 0 && (def ?? -1) >= 0
        }
        return effect != nil
    }
}

enum DuelAction: Equatable {
    case nextPhase
    case summon(cardID: Int, tributes: [Int], set: Bool)
    case changePosition(monsterID: Int)
    case attack(attackerID: Int, targetID: Int?)
    case activateSpell(cardID: Int, targetID: Int?, targetPlayer: Int?, position: DuelState.Position)
    case chooseSpecialSummon(cardID: Int, position: DuelState.Position)
    case setTrap(cardID: Int)
    case counter(trapID: Int)
    case pass
    case discard(cardIDs: [Int])
}

/// A local two-player training ruleset, independent of SwiftUI and the Android binary.
struct DuelState {
    enum Phase: String, CaseIterable {
        case draw = "Draw", standby = "Standby", main1 = "Main 1"
        case battle = "Battle", main2 = "Main 2", end = "End"
    }
    enum Position: String { case attack, defense }
    enum DuelError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): return message }
        }
    }
    struct CardInstance: Identifiable, Equatable {
        let id: Int
        let definitionID: Int
        let owner: Int
    }
    struct Monster: Identifiable, Equatable {
        let card: CardInstance
        var position: Position
        var faceDown: Bool
        let summonedTurn: Int
        var positionChangedTurn: Int?
        var attacked = false
        var id: Int { card.id }
    }
    struct SetTrap: Identifiable, Equatable {
        let card: CardInstance
        let setTurn: Int
        var id: Int { card.id }
    }
    struct Player: Equatable {
        var lp = 8000
        var deck: [CardInstance] = []
        var hand: [CardInstance] = []
        var field: [Monster] = []
        var traps: [SetTrap] = []
        var graveyard: [CardInstance] = []
    }
    struct ChainLink: Identifiable, Equatable {
        let id: Int
        let player: Int
        let card: CardInstance
        let effect: DuelCardDefinition.Effect
        let negatesLinkID: Int?
        let targetCardID: Int?
        let targetOwner: Int?
        let summonPosition: Position
    }
    struct PendingSummonChoice: Equatable {
        let player: Int
        let candidates: [CardInstance]
    }

    let definitions: [Int: DuelCardDefinition]
    private let initialDecks: [[Int]]
    private let initialShuffleSeed: UInt64
    private struct ShuffleGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }
    private var shuffleGenerator = ShuffleGenerator(state: 1)
    private(set) var players: [Player] = []
    private(set) var activePlayer = 0
    private(set) var turn = 1
    private(set) var phase: Phase = .draw
    private(set) var winner: Int?
    private(set) var finishReason: String?
    private(set) var chain: [ChainLink] = []
    private(set) var priorityPlayer = 0
    private(set) var normalSummonUsed = false
    private(set) var log: [String] = []
    private(set) var isResolving = false
    private(set) var pendingSummonChoice: PendingSummonChoice?
    private var consecutivePasses = 0
    private var nextLinkID = 1
    private var resolutionCursor = -1
    private var negatedLinkIDs: Set<Int> = []

    init(definitions: [Int: DuelCardDefinition], decks: [[Int]], shuffle: Bool = false, shuffleSeed: UInt64? = nil) throws {
        guard decks.count == 2 else { throw DuelError.invalid("Cần hai bộ bài.") }
        for (key, definition) in definitions where key != definition.id {
            throw DuelError.invalid("ID định nghĩa thẻ không khớp: \(key).")
        }
        for deck in decks {
            guard (40...60).contains(deck.count) else {
                throw DuelError.invalid("Main Deck cần 40–60 lá.")
            }
            var counts: [Int: Int] = [:]
            for id in deck {
                guard let card = definitions[id], card.supported else {
                    throw DuelError.invalid("Chưa hỗ trợ đầy đủ lá ID \(id); không thể dùng trong trận tập.")
                }
                counts[id, default: 0] += 1
                guard counts[id, default: 0] <= 3 else {
                    throw DuelError.invalid("Một bộ bài chỉ được tối đa 3 bản của ID \(id).")
                }
            }
        }
        self.definitions = definitions
        initialDecks = decks
        initialShuffleSeed = shuffleSeed ?? (shuffle ? UInt64.random(in: 1...UInt64.max) : 1)
        restart(shuffle: shuffle)
    }

    mutating func restart(shuffle: Bool = false) {
        players = [Player(), Player()]
        activePlayer = 0; turn = 1; phase = .draw; winner = nil; finishReason = nil
        chain = []; priorityPlayer = 0; normalSummonUsed = false
        consecutivePasses = 0; nextLinkID = 1; log = []
        isResolving = false; pendingSummonChoice = nil; resolutionCursor = -1; negatedLinkIDs = []
        shuffleGenerator = ShuffleGenerator(state: initialShuffleSeed)
        var instanceID = 1
        for player in 0..<2 {
            var ids = initialDecks[player]
            if shuffle { ids.shuffle(using: &shuffleGenerator) }
            players[player].deck = ids.map { definitionID in
                defer { instanceID += 1 }
                return CardInstance(id: instanceID, definitionID: definitionID, owner: player)
            }
            drawCards(5, player: player)
        }
        log.append("Bắt đầu trận tập. Người 1 đi trước, không rút và không tấn công ở lượt đầu.")
    }

    func definition(of card: CardInstance) -> DuelCardDefinition { definitions[card.definitionID]! }

    mutating func apply(action: DuelAction, player: Int) throws {
        switch action {
        case .nextPhase: try nextPhase(player: player)
        case .summon(let cardID, let tributes, let set):
            try summon(player: player, cardID: cardID, tributes: tributes, set: set)
        case .changePosition(let monsterID): try changePosition(player: player, monsterID: monsterID)
        case .attack(let attackerID, let targetID): try attack(player: player, attackerID: attackerID, targetID: targetID)
        case .activateSpell(let cardID, let targetID, let targetPlayer, let position):
            try activateSpell(player: player, cardID: cardID, targetID: targetID, targetPlayer: targetPlayer, position: position)
        case .chooseSpecialSummon(let cardID, let position):
            try chooseSpecialSummon(player: player, cardID: cardID, position: position)
        case .setTrap(let cardID): try setTrap(player: player, cardID: cardID)
        case .counter(let trapID): try activateCounter(player: player, trapID: trapID)
        case .pass: try pass(player: player)
        case .discard(let cardIDs): try discard(player: player, cardIDs: cardIDs)
        }
    }

    mutating func nextPhase(player: Int) throws {
        try requireAction(player)
        switch phase {
        case .draw: phase = .standby
        case .standby: phase = .main1
        case .main1: phase = turn == 1 ? .end : .battle
        case .battle: phase = .main2
        case .main2: phase = .end
        case .end:
            guard players[player].hand.count <= 6 else {
                throw DuelError.invalid("Chọn bỏ bớt bài, chỉ giữ tối đa 6 lá trước khi kết thúc lượt.")
            }
            activePlayer = 1 - player
            turn += 1; phase = .draw; normalSummonUsed = false
            for i in players[activePlayer].field.indices { players[activePlayer].field[i].attacked = false }
            priorityPlayer = activePlayer
            drawCards(1, player: activePlayer)
        }
        log.append("Lượt \(turn), Người \(activePlayer + 1): \(phase.rawValue).")
    }

    mutating func discard(player: Int, cardIDs: [Int]) throws {
        try requireAction(player)
        let excess = players[player].hand.count - 6
        guard phase == .end, excess > 0, cardIDs.count == excess,
              Set(cardIDs).count == cardIDs.count,
              cardIDs.allSatisfy({ id in players[player].hand.contains(where: { $0.id == id }) }) else {
            throw DuelError.invalid("Chọn đúng số lá cần bỏ để còn 6 lá trên tay ở End Phase.")
        }
        let ids = Set(cardIDs)
        let discarded = players[player].hand.filter { ids.contains($0.id) }
        players[player].hand.removeAll { ids.contains($0.id) }
        for card in discarded { sendToGraveyard(card) }
        log.append("Người \(player + 1) bỏ \(cardIDs.count) lá vào Mộ.")
    }

    mutating func summon(player: Int, cardID: Int, tributes: [Int] = [], set: Bool = false) throws {
        try requireMain(player)
        guard !normalSummonUsed else { throw DuelError.invalid("Đã dùng lượt triệu hồi thường/úp quái.") }
        guard let handIndex = players[player].hand.firstIndex(where: { $0.id == cardID }) else {
            throw DuelError.invalid("Lá được chọn không ở trên tay.")
        }
        let card = players[player].hand[handIndex]
        let data = definition(of: card)
        guard data.kindCode == 0 else { throw DuelError.invalid("Trận tập chỉ triệu hồi quái Normal không hiệu ứng.") }
        let cost = data.level >= 7 ? 2 : data.level >= 5 ? 1 : 0
        guard tributes.count == cost, Set(tributes).count == tributes.count,
              tributes.allSatisfy({ id in players[player].field.contains(where: { $0.id == id }) }) else {
            throw DuelError.invalid("Quái này cần \(cost) quái trên sân làm vật hiến tế.")
        }
        guard players[player].field.count - cost < 5 else { throw DuelError.invalid("Đã đủ 5 ô quái.") }
        let ids = Set(tributes)
        let tributed = players[player].field.filter { ids.contains($0.id) }.map(\.card)
        players[player].field.removeAll { ids.contains($0.id) }
        for card in tributed { sendToGraveyard(card) }
        players[player].hand.remove(at: handIndex)
        players[player].field.append(Monster(card: card, position: set ? .defense : .attack,
                                            faceDown: set, summonedTurn: turn))
        normalSummonUsed = true
        log.append("Người \(player + 1) \(set ? "úp một quái phòng thủ" : "triệu hồi " + data.name).")
    }

    mutating func changePosition(player: Int, monsterID: Int) throws {
        try requireMain(player)
        guard let index = players[player].field.firstIndex(where: { $0.id == monsterID }) else {
            throw DuelError.invalid("Không tìm thấy quái trên sân.")
        }
        let monster = players[player].field[index]
        guard monster.summonedTurn != turn, !monster.attacked, monster.positionChangedTurn != turn else {
            throw DuelError.invalid("Không được đổi tư thế sau triệu hồi, tấn công hoặc đổi tư thế trong cùng lượt.")
        }
        players[player].field[index].position = monster.position == .attack ? .defense : .attack
        players[player].field[index].faceDown = false
        players[player].field[index].positionChangedTurn = turn
        log.append("Đổi tư thế \(definition(of: monster.card).name).")
    }

    mutating func attack(player: Int, attackerID: Int, targetID: Int? = nil) throws {
        try requireAction(player)
        guard phase == .battle, turn > 1 else { throw DuelError.invalid("Chỉ tấn công trong Battle Phase, từ lượt 2.") }
        guard let index = players[player].field.firstIndex(where: { $0.id == attackerID }) else {
            throw DuelError.invalid("Không tìm thấy quái tấn công.")
        }
        let attacker = players[player].field[index]
        guard attacker.position == .attack, !attacker.faceDown, !attacker.attacked else {
            throw DuelError.invalid("Quái phải ngửa ở thế công và chưa tấn công trong lượt này.")
        }
        let opponent = 1 - player
        let targetIndex = targetID.flatMap { id in players[opponent].field.firstIndex(where: { $0.id == id }) }
        if players[opponent].field.isEmpty {
            guard targetID == nil else { throw DuelError.invalid("Mục tiêu đã rời sân.") }
        } else if targetIndex == nil {
            throw DuelError.invalid("Phải chọn quái đối phương; chưa được đánh trực tiếp.")
        }
        players[player].field[index].attacked = true
        let attack = definition(of: attacker.card).atk!
        // shortcut: combat resolves immediately for Normal monsters, add battle windows when reactive effects are supported.
        guard let targetIndex else {
            players[opponent].lp = max(0, players[opponent].lp - attack)
            log.append("Đánh trực tiếp: \(attack) sát thương.")
            checkLifePoints()
            return
        }
        let defender = players[opponent].field[targetIndex]
        players[opponent].field[targetIndex].faceDown = false
        let defense = definition(of: defender.card)
        if defender.position == .attack {
            let difference = attack - defense.atk!
            if difference > 0 {
                destroy(player: opponent, instanceID: defender.id)
                players[opponent].lp = max(0, players[opponent].lp - difference)
            } else if difference < 0 {
                destroy(player: player, instanceID: attacker.id)
                players[player].lp = max(0, players[player].lp + difference)
            } else if attack > 0 {
                destroy(player: player, instanceID: attacker.id)
                destroy(player: opponent, instanceID: defender.id)
            }
        } else {
            let difference = attack - defense.def!
            if difference > 0 { destroy(player: opponent, instanceID: defender.id) }
            if difference < 0 { players[player].lp = max(0, players[player].lp + difference) }
        }
        log.append("\(definition(of: attacker.card).name) đấu với \(defense.name).")
        checkLifePoints()
    }

    mutating func activateSpell(player: Int, cardID: Int, targetID: Int? = nil,
                                targetPlayer: Int? = nil, position: Position = .attack) throws {
        try requireMain(player)
        guard players[player].traps.count < 5 else { throw DuelError.invalid("Không còn ô Phép/Bẫy trống.") }
        guard let index = players[player].hand.firstIndex(where: { $0.id == cardID }) else {
            throw DuelError.invalid("Lá Phép không ở trên tay.")
        }
        let card = players[player].hand[index]
        guard let effect = definition(of: card).effect, effect != .judgment else {
            throw DuelError.invalid("Lá này không có hiệu ứng Phép được hỗ trợ.")
        }
        guard effect != .drawTwo || players[player].deck.count >= 2 else {
            throw DuelError.invalid("Pot of Greed cần ít nhất 2 lá còn lại trong Deck để kích hoạt.")
        }
        if let targetPlayer, !(0..<2).contains(targetPlayer) {
            throw DuelError.invalid("Người chơi giữ mục tiêu không hợp lệ.")
        }
        switch effect {
        case .revive:
            guard players[player].field.count < 5, let targetID, let targetPlayer,
                  let target = players[targetPlayer].graveyard.first(where: { $0.id == targetID }),
                  definition(of: target).kindCode == 0 else {
                throw DuelError.invalid("Chọn quái Normal trong một trong hai Mộ; cần một ô quái trống.")
            }
        case .recruitNormal:
            guard players[player].field.isEmpty, !recruitCandidates(player: player).isEmpty else {
                throw DuelError.invalid("Unexpected Dai cần sân mình trống và quái Normal cấp 4 trở xuống trong Deck.")
            }
        case .destroyOpponents:
            guard !players[1 - player].field.isEmpty else {
                throw DuelError.invalid("Không có quái đối phương để dùng Raigeki.")
            }
        case .destroyAll:
            guard players.contains(where: { !$0.field.isEmpty }) else {
                throw DuelError.invalid("Không có quái trên sân để dùng Dark Hole.")
            }
        default: break
        }
        if effect != .revive, targetID != nil || targetPlayer != nil {
            throw DuelError.invalid("Hiệu ứng này không chọn mục tiêu.")
        }
        players[player].hand.remove(at: index)
        addLink(player: player, card: card, effect: effect, target: nil,
                targetCardID: targetID, targetOwner: targetPlayer, position: position)
    }

    mutating func setTrap(player: Int, cardID: Int) throws {
        try requireMain(player)
        guard players[player].traps.count < 5 else { throw DuelError.invalid("Đã đủ 5 ô Phép/Bẫy.") }
        guard let index = players[player].hand.firstIndex(where: { $0.id == cardID }),
              definition(of: players[player].hand[index]).effect == .judgment else {
            throw DuelError.invalid("Chỉ hỗ trợ úp Solemn Judgment trong trận tập.")
        }
        let card = players[player].hand.remove(at: index)
        players[player].traps.append(SetTrap(card: card, setTurn: turn))
        log.append("Người \(player + 1) úp một Bẫy.")
    }

    mutating func activateCounter(player: Int, trapID: Int) throws {
        try requireLivePlayer(player)
        guard !isResolving, !chain.isEmpty, player == priorityPlayer, let previous = chain.last else {
            throw DuelError.invalid("Chỉ phản hồi kích hoạt Phép/Bẫy khi có quyền phản hồi.")
        }
        guard let index = players[player].traps.firstIndex(where: { $0.id == trapID }),
              players[player].traps[index].setTurn < turn else {
            throw DuelError.invalid("Bẫy phải được úp từ lượt trước.")
        }
        let card = players[player].traps.remove(at: index).card
        // Half-LP payment rounds the amount paid down, leaving odd LP rounded up.
        players[player].lp -= players[player].lp / 2
        addLink(player: player, card: card, effect: .judgment, target: previous.id)
    }

    mutating func pass(player: Int) throws {
        try requireLivePlayer(player)
        guard !isResolving, !chain.isEmpty, priorityPlayer == player else {
            throw DuelError.invalid("Chưa tới quyền phản hồi chain của người này.")
        }
        consecutivePasses += 1
        priorityPlayer = 1 - player
        if consecutivePasses == 2 {
            isResolving = true; resolutionCursor = chain.count - 1; negatedLinkIDs = []
            continueResolution()
        }
    }

    mutating func chooseSpecialSummon(player: Int, cardID: Int, position: Position = .attack) throws {
        try requireLivePlayer(player)
        guard isResolving, let choice = pendingSummonChoice, choice.player == player,
              choice.candidates.contains(where: { $0.id == cardID }),
              let index = players[player].deck.firstIndex(where: { $0.id == cardID }),
              players[player].field.count < 5 else {
            throw DuelError.invalid("Chọn quái Normal hợp lệ khi Unexpected Dai đang giải quyết.")
        }
        let card = players[player].deck.remove(at: index)
        specialSummon(card, player: player, position: position)
        var remainingDeck = players[player].deck
        remainingDeck.shuffle(using: &shuffleGenerator)
        players[player].deck = remainingDeck
        pendingSummonChoice = nil
        continueResolution()
    }

    private func requireLivePlayer(_ player: Int) throws {
        guard (0..<2).contains(player) else { throw DuelError.invalid("Người chơi không hợp lệ.") }
        guard winner == nil else { throw DuelError.invalid("Trận đã kết thúc; hãy bắt đầu trận mới.") }
    }
    private func requireAction(_ player: Int) throws {
        try requireLivePlayer(player)
        guard activePlayer == player else { throw DuelError.invalid("Chưa tới lượt người chơi này.") }
        guard chain.isEmpty else { throw DuelError.invalid("Cần giải quyết chain trước.") }
    }
    private func requireMain(_ player: Int) throws {
        try requireAction(player)
        guard phase == .main1 || phase == .main2 else { throw DuelError.invalid("Thao tác này chỉ dùng ở Main Phase.") }
    }
    private mutating func addLink(player: Int, card: CardInstance, effect: DuelCardDefinition.Effect, target: Int?,
                                  targetCardID: Int? = nil, targetOwner: Int? = nil, position: Position = .attack) {
        chain.append(ChainLink(id: nextLinkID, player: player, card: card, effect: effect, negatesLinkID: target,
                               targetCardID: targetCardID, targetOwner: targetOwner, summonPosition: position))
        nextLinkID += 1; consecutivePasses = 0; priorityPlayer = 1 - player
        log.append("Chain \(chain.count): Người \(player + 1) kích hoạt \(definition(of: card).name).")
    }
    private mutating func continueResolution() {
        while resolutionCursor >= 0 && winner == nil {
            let link = chain[resolutionCursor]
            resolutionCursor -= 1
            if negatedLinkIDs.contains(link.id) {
                log.append("Bị vô hiệu hóa: \(definition(of: link.card).name).")
                continue
            }
            switch link.effect {
            case .drawTwo: drawCards(2, player: link.player)
            case .damage200:
                players[1 - link.player].lp = max(0, players[1 - link.player].lp - 200)
                checkLifePoints()
            case .heal1000: players[link.player].lp += 1000
            case .judgment:
                if let target = link.negatesLinkID { negatedLinkIDs.insert(target) }
            case .revive:
                if let owner = link.targetOwner, let id = link.targetCardID,
                   let index = players[owner].graveyard.firstIndex(where: { $0.id == id }),
                   players[link.player].field.count < 5 {
                    let card = players[owner].graveyard.remove(at: index)
                    specialSummon(card, player: link.player, position: link.summonPosition)
                } else { log.append("Monster Reborn không còn mục tiêu/ô quái hợp lệ.") }
            case .recruitNormal:
                let candidates = recruitCandidates(player: link.player)
                if players[link.player].field.count < 5 && !candidates.isEmpty {
                    pendingSummonChoice = PendingSummonChoice(player: link.player, candidates: candidates)
                    log.append("Người \(link.player + 1) chọn quái Normal cấp 4 trở xuống để triệu hồi đặc biệt.")
                    return
                }
                log.append("Unexpected Dai không còn quái hợp lệ hoặc ô quái trống.")
            case .destroyOpponents:
                for monster in players[1 - link.player].field { destroy(player: 1 - link.player, instanceID: monster.id) }
            case .destroyAll:
                for player in 0..<2 {
                    for monster in players[player].field { destroy(player: player, instanceID: monster.id) }
                }
            }
            log.append("Giải quyết: \(definition(of: link.card).name).")
        }
        // Cards remain in the chain until cleanup; a negated activation never refunds its card or cost.
        for link in chain { sendToGraveyard(link.card) }
        chain = []; consecutivePasses = 0; priorityPlayer = activePlayer
        isResolving = false; resolutionCursor = -1; negatedLinkIDs = []; pendingSummonChoice = nil
    }
    private mutating func drawCards(_ count: Int, player: Int) {
        for _ in 0..<count {
            guard winner == nil else { return }
            guard !players[player].deck.isEmpty else {
                winner = 1 - player; finishReason = "Người \(player + 1) không còn bài để rút."
                log.append(finishReason!)
                return
            }
            players[player].hand.append(players[player].deck.removeFirst())
        }
    }
    private mutating func destroy(player: Int, instanceID: Int) {
        guard let index = players[player].field.firstIndex(where: { $0.id == instanceID }) else { return }
        let card = players[player].field.remove(at: index).card
        sendToGraveyard(card)
    }
    private mutating func sendToGraveyard(_ card: CardInstance) {
        players[card.owner].graveyard.append(card)
    }
    private mutating func specialSummon(_ card: CardInstance, player: Int, position: Position) {
        players[player].field.append(Monster(card: card, position: position, faceDown: false, summonedTurn: turn))
        log.append("Người \(player + 1) triệu hồi đặc biệt \(definition(of: card).name).")
    }
    private func recruitCandidates(player: Int) -> [CardInstance] {
        players[player].deck.filter { card in
            let data = definition(of: card)
            return data.kindCode == 0 && data.level <= 4
        }
    }
    private mutating func checkLifePoints() {
        for player in 0..<2 where players[player].lp == 0 {
            winner = 1 - player; finishReason = "Người \(player + 1) hết LP."
            log.append(finishReason!)
        }
    }
}
