import Foundation
import SwiftUI

@MainActor
final class OfflineDuelEngine: ObservableObject {
    enum Opponent: String, CaseIterable { case computer = "Đấu với AI", local = "Hai người cùng máy" }
    @Published private(set) var state: DuelState?
    @Published private(set) var setupError: String?
    @Published var actionError: String?
    @Published private(set) var deckNames: [String] = []
    @Published var opponent: Opponent = .computer
    @Published private(set) var aiThinking = false
    @Published private(set) var aiPaused = false
    private var definitions: [Int: DuelCardDefinition] = [:]
    private var decks: [[Int]] = []
    private var extraDecks: [[Int]] = []
    private var aiTask: Task<Void, Never>?
    private var aiRunID = UUID()

    private struct Deck: Decodable { let file: String; let main: [Int]; let extra: [Int]; let side: [Int] }
    private struct Meta: Decodable {
        let propFirst: UInt32
        let kindCode: Int
        let level: Int
        let atk: Int?
        let def: Int?
        let password: UInt32?
    }

    init() {
        do {
            let rows: [Meta] = try Self.read("card-index")
            let names: [String: String] = try Self.read("card-id-names", directory: "GeneratedData")
            let practice: [Deck] = try Self.read("offline-practice-decks", directory: "GeneratedData")
            guard practice.count == 2, practice.allSatisfy({ $0.extra.count <= 15 && $0.side.isEmpty }) else {
                throw DuelState.DuelError.invalid("Cần hai bộ bài luyện tập, tối đa 15 lá Extra mỗi bộ và Side trống.")
            }
            for row in rows {
                let id = Int(row.propFirst & 0x3FFF)
                if id == 0 { continue }
                guard definitions[id] == nil, let name = names[String(id)] else {
                    throw DuelState.DuelError.invalid("ID thẻ trùng hoặc thiếu tên: \(id).")
                }
                definitions[id] = DuelCardDefinition(id: id, name: name, kindCode: row.kindCode,
                    level: row.level, atk: row.atk, def: row.def, password: row.password)
            }
            decks = practice.map(\.main)
            extraDecks = practice.map(\.extra)
            deckNames = practice.map(\.file)
        } catch { setupError = error.localizedDescription }
    }

    private static func read<T: Decodable>(_ name: String, directory: String? = nil) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: directory) else {
            throw DuelState.DuelError.invalid("Thiếu dữ liệu \(name).json trong ứng dụng.")
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    func start() {
        guard setupError == nil else { return }
        stopAI()
        do {
            state = try DuelState(definitions: definitions, decks: decks, extraDecks: extraDecks, shuffle: true)
            actionError = nil
            aiPaused = false
            resumeAI()
        } catch { actionError = error.localizedDescription }
    }

    func perform(_ action: (inout DuelState) throws -> Void) {
        guard var next = state else { return }
        guard opponent != .computer || controller(next) == 0 else {
            actionError = "Đang tới lượt xử lý của AI."
            return
        }
        do {
            try action(&next)
            state = next
            actionError = nil
            resumeAI()
        } catch { actionError = error.localizedDescription }
    }

    func name(_ card: DuelState.CardInstance) -> String {
        definitions[card.definitionID]?.name ?? "Thẻ \(card.definitionID)"
    }

    func controller(_ state: DuelState) -> Int {
        state.decisionPlayer
    }

    func stopAI() {
        aiRunID = UUID()
        aiTask?.cancel()
        aiTask = nil
        aiThinking = false
    }

    func resumeAI() {
        guard opponent == .computer, !aiThinking,
              let state, state.winner == nil, controller(state) == 1 else { return }
        aiPaused = false
        aiThinking = true
        let token = aiRunID
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.aiRunID == token { self.aiThinking = false; self.aiTask = nil }
            }
            // Bound each run so a policy bug cannot lock the UI in an endless turn.
            for _ in 0..<160 {
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
                guard !Task.isCancelled, self.aiRunID == token,
                      var current = self.state, current.winner == nil, self.controller(current) == 1 else { return }
                guard let action = DuelAI.chooseAction(state: current, player: 1) else {
                    self.actionError = "AI chưa chọn được hành động hợp lệ. Trận đã tạm dừng."
                    self.aiPaused = true
                    return
                }
                do {
                    try current.apply(action: action, player: 1)
                    self.state = current
                    self.actionError = nil
                } catch {
                    self.actionError = "AI đã dừng: \(error.localizedDescription)"
                    self.aiPaused = true
                    return
                }
            }
            if let current = self.state, current.winner == nil, self.controller(current) == 1 {
                self.aiPaused = true
                self.actionError = "AI đã đạt giới hạn thao tác của một đợt. Bạn có thể cho AI tiếp tục."
            }
        }
    }
}

struct OfflineDuelView: View {
    @StateObject private var game = OfflineDuelEngine()
    @State private var visiblePlayer: Int?
    @State private var tributes: Set<Int> = []
    @State private var discards: Set<Int> = []
    @State private var confirmRestart = false

    var body: some View {
        List {
            Section("Đấu tập offline") {
                Picker("Đối thủ", selection: $game.opponent) {
                    ForEach(OfflineDuelEngine.Opponent.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.disabled(game.state != nil)
                Text("Có AI, Damage Step, chọn lại mục tiêu, Kuriboh, Cyber Dragon và hai lá Extra Deck: Flame Swordsman/Fusion, Gaia Knight/Synchro.")
                    .font(.footnote)
                Text("Chỉ dùng các lá đã triển khai trong bộ luyện tập. Chưa hỗ trợ mọi effect, trigger Flip, Xyz, Pendulum hoặc Link.")
                    .font(.footnote)
                if let error = game.setupError {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
                if game.state == nil {
                    ForEach(game.deckNames, id: \.self) { Text($0).font(.caption) }
                    Button("Bắt đầu trận tập") { game.start(); clearPrivateState() }
                        .disabled(game.setupError != nil)
                } else {
                    Button("Trận mới") { confirmRestart = true }
                }
            }
            if let state = game.state {
                duelStatus(state)
                if state.winner == nil { controls(state) }
                ForEach(0..<2, id: \.self) { player in field(state, player: player) }
                if !state.chain.isEmpty {
                    Section("Chain • giải quyết từ liên kết cuối") {
                        ForEach(state.chain) { link in
                            Text("Người \(link.player + 1): \(game.name(link.card))")
                            if link.effect == .revive, let targetID = link.targetCardID, let owner = link.targetOwner,
                               let target = state.players[owner].graveyard.first(where: { $0.id == targetID }) {
                                Text("Mục tiêu: \(game.name(target)) • Mộ Người \(owner + 1)").font(.caption)
                            }
                            if let targetID = link.targetCardID, let owner = link.targetOwner,
                               link.effect == .destroySpellTrap {
                                Text("Mục tiêu: \(spellTrapName(state, owner: owner, id: targetID))").font(.caption)
                            }
                            if !link.sourceOnField {
                                Text(link.sourceIsSpellTrap ? "Lá nguồn đã rời sân" : "Hiệu ứng quái • đã trả chi phí")
                                    .font(.caption)
                            }
                        }
                    }
                }
                Section("Nhật ký") {
                    ForEach(Array(state.log.enumerated().reversed()), id: \.offset) { entry in
                        Text(entry.element).font(.caption)
                    }
                }
            }
            if let error = game.actionError {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Đấu tập offline")
        .onAppear { if game.opponent == .computer { visiblePlayer = 0 }; game.resumeAI() }
        .onDisappear { game.stopAI() }
        .confirmationDialog("Bắt đầu lại và xóa tiến trình trận này?", isPresented: $confirmRestart) {
            Button("Bắt đầu trận mới", role: .destructive) { game.start(); clearPrivateState() }
            Button("Hủy", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func duelStatus(_ state: DuelState) -> some View {
        Section("Lượt \(state.turn) • Người \(state.activePlayer + 1) • \(state.phase.rawValue)") {
            ForEach(0..<2, id: \.self) { player in
                let zone = state.players[player]
                Text("Người \(player + 1): \(zone.lp) LP · Bộ bài \(zone.deck.count) · Tay \(zone.hand.count) · Extra \(zone.extraDeck.count) · Mộ \(zone.graveyard.count)")
            }
            if let damage = state.damageStep { Text("Damage Step: \(damage.stage.rawValue)").font(.headline) }
            if let winner = state.winner {
                Text("Người \(winner + 1) thắng").font(.headline)
                Text(state.finishReason ?? "Trận kết thúc.")
            }
        }
    }

    @ViewBuilder
    private func controls(_ state: DuelState) -> some View {
        let controller = game.controller(state)
        if game.opponent == .computer && controller == 1 {
            Section("AI đang xử lý") {
                if game.aiThinking { ProgressView("Đối thủ đang chọn hành động…") }
                if game.aiPaused { Button("Cho AI tiếp tục") { game.resumeAI() } }
                Text("AI sẽ dừng khi đến quyền phản hồi hoặc chọn bài của bạn.").font(.footnote)
            }
        } else if visiblePlayer != controller {
            Section {
                Text("Chuyển máy cho Người \(controller + 1) trước khi xem bài trên tay.")
                Button("Tôi là Người \(controller + 1) — hiện bài") { visiblePlayer = controller }
            }
        } else if let replay = state.pendingReplay {
            Section("Chọn lại mục tiêu tấn công") {
                Text("Đội hình đối phương đã đổi. Đây không phải một lần khai báo tấn công mới.").font(.footnote)
                if replay.canAttackDirectly {
                    Button("Đánh trực tiếp") { act { try $0.replayAttack(player: controller, targetID: nil) } }
                }
                ForEach(state.players[1 - controller].field.filter { replay.targetIDs.contains($0.id) }) { monster in
                    Button(monsterName(monster, owner: 1 - controller)) {
                        act { try $0.replayAttack(player: controller, targetID: monster.id) }
                    }
                }
                Button("Dừng lần tấn công này") { act { try $0.cancelAttack(player: controller) } }
            }
        } else if let choice = state.pendingFusionChoice {
            Section("Polymerization • chọn nguyên liệu Fusion") {
                Text("Nguyên liệu được chọn khi hiệu ứng giải quyết, từ tay hoặc sân của bạn.").font(.footnote)
                ForEach(choice.candidates, id: \.extraCard.id) { option in
                    ForEach(Array(option.materialPairs.enumerated()), id: \.offset) { entry in
                        Menu("\(game.name(option.extraCard)) ← \(materialNames(entry.element, state: state, player: controller))") {
                            Button("Triệu hồi thế công") {
                                act { try $0.chooseFusion(player: controller, extraCardID: option.extraCard.id, materialIDs: entry.element, position: .attack) }
                            }
                            Button("Triệu hồi thế thủ") {
                                act { try $0.chooseFusion(player: controller, extraCardID: option.extraCard.id, materialIDs: entry.element, position: .defense) }
                            }
                        }
                    }
                }
            }
        } else if let choice = state.pendingSummonChoice {
            Section("Unexpected Dai • chọn quái để triệu hồi") {
                Text("Chọn khi hiệu ứng giải quyết; bộ bài sẽ được xáo lại sau đó.").font(.footnote)
                ForEach(choice.candidates) { card in
                    Menu(game.name(card)) {
                        Button("Thế tấn công") { act { try $0.chooseSpecialSummon(player: controller, cardID: card.id, position: .attack) } }
                        Button("Thế phòng thủ") { act { try $0.chooseSpecialSummon(player: controller, cardID: card.id, position: .defense) } }
                    }
                }
            }
        } else if state.hasResponseWindow {
            Section("Người \(controller + 1) phản hồi") {
                Text(state.responseLabel)
                Text("Hai người bỏ qua liên tiếp để tiếp tục. Mọi phản hồi vẫn phải đúng thời điểm và Spell Speed.")
                    .font(.footnote)
                if let summon = state.pendingSummon {
                    Text("Đang triệu hồi: \(game.name(summon.monster.card))").font(.headline)
                }
                if let attack = state.pendingAttack,
                   let monster = state.players[attack.player].field.first(where: { $0.id == attack.attackerID }) {
                    Text("Đang tấn công: \(game.name(monster.card))").font(.headline)
                }
                ForEach(state.players[controller].traps) { trap in
                    fastCardControls(trap.card, state: state, player: controller)
                }
                ForEach(state.players[controller].hand.filter { state.definition(of: $0).effect == .kuriboh }) { card in
                    fastCardControls(card, state: state, player: controller)
                }
                if controller == state.activePlayer {
                    ForEach(state.players[controller].hand.filter { state.definition(of: $0).effect == .destroySpellTrap }) { card in
                        fastCardControls(card, state: state, player: controller)
                    }
                }
                Button("Không phản hồi") { act { try $0.pass(player: controller) } }
            }
        } else {
            Section("Thao tác của Người \(controller + 1)") {
                Button("Sang phase tiếp theo") { act { try $0.nextPhase(player: controller) } }
                Text("Hiến tế: chọn quái trên sân trước khi triệu hồi quái cấp 5 trở lên.")
                    .font(.footnote)
                if state.phase == .end && state.players[controller].hand.count > 6 {
                    Text("Chọn \(state.players[controller].hand.count - 6) lá để bỏ; hiện chọn \(discards.count).")
                    Button("Bỏ các lá đã chọn") { act { try $0.discard(player: controller, cardIDs: Array(discards)) } }
                }
            }
            Section("Bài trên tay") {
                ForEach(state.players[controller].hand) { card in
                    handRow(card, state: state, player: controller)
                }
            }
            extraDeckControls(state, player: controller)
        }
    }

    @ViewBuilder
    private func handRow(_ card: DuelState.CardInstance, state: DuelState, player: Int) -> some View {
        let definition = state.definition(of: card)
        let isMain = state.phase == .main1 || state.phase == .main2
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.name).font(.headline)
            if definition.normalSummonable {
                Text("Cấp \(definition.level) • ATK \(definition.atk ?? 0) / DEF \(definition.def ?? 0)").font(.caption)
                HStack {
                    Button("Triệu hồi") { act { try $0.summon(player: player, cardID: card.id, tributes: Array(tributes)) } }
                    Button("Úp phòng thủ") { act { try $0.summon(player: player, cardID: card.id, tributes: Array(tributes), set: true) } }
                }.disabled(!isMain || state.normalSummonUsed)
                if definition.effect == .cyberDragon {
                    specialFromHand(card, state: state, player: player)
                }
            } else if definition.effect == .judgment || definition.effect == .mirrorForce || definition.effect == .destroySpellTrap || definition.effect == .returnMonster {
                Button("Úp Phép/Bẫy") { act { try $0.setTrap(player: player, cardID: card.id) } }.disabled(!isMain)
                if definition.effect == .destroySpellTrap { fastCardControls(card, state: state, player: player) }
            } else if definition.effect == .revive {
                Menu("Monster Reborn • chọn mục tiêu") {
                    ForEach(0..<2, id: \.self) { owner in
                        ForEach(state.players[owner].graveyard.filter { state.definition(of: $0).isMonster }) { target in
                            Menu("\(game.name(target)) • Mộ Người \(owner + 1)") {
                                Button("Triệu hồi thế công") {
                                    act { try $0.activateSpell(player: player, cardID: card.id, targetID: target.id, targetPlayer: owner, position: .attack) }
                                }.disabled(!legal(.activateSpell(cardID: card.id, targetID: target.id, targetPlayer: owner, position: .attack), state: state, player: player))
                                Button("Triệu hồi thế thủ") {
                                    act { try $0.activateSpell(player: player, cardID: card.id, targetID: target.id, targetPlayer: owner, position: .defense) }
                                }.disabled(!legal(.activateSpell(cardID: card.id, targetID: target.id, targetPlayer: owner, position: .defense), state: state, player: player))
                            }
                        }
                    }
                }.disabled(!isMain || state.players[player].field.count >= 5)
            } else {
                Button("Kích hoạt Phép") { act { try $0.activateSpell(player: player, cardID: card.id) } }.disabled(!isMain)
            }
            if state.phase == .end && state.players[player].hand.count > 6 {
                Button(discards.contains(card.id) ? "Bỏ chọn" : "Chọn bỏ lá này") {
                    if !discards.insert(card.id).inserted { discards.remove(card.id) }
                }
            }
        }.buttonStyle(.bordered).padding(.vertical, 4)
    }

    @ViewBuilder
    private func field(_ state: DuelState, player: Int) -> some View {
        let canControl = visiblePlayer == player && state.activePlayer == player && !state.hasResponseWindow && !state.isResolving && state.winner == nil
        Section("Sân Người \(player + 1)") {
            if state.players[player].field.isEmpty { Text("Không có quái") }
            ForEach(state.players[player].field) { monster in
                VStack(alignment: .leading, spacing: 8) {
                    Text(monsterName(monster, owner: player)).font(.headline)
                    Text(monster.position == .attack ? "Tấn công" : "Phòng thủ").font(.caption)
                    if canControl {
                        if state.phase == .main1 || state.phase == .main2 {
                            HStack {
                                Button(tributes.contains(monster.id) ? "Bỏ chọn hiến tế" : "Chọn hiến tế") {
                                    if !tributes.insert(monster.id).inserted { tributes.remove(monster.id) }
                                }
                                Button("Đổi tư thế") { act { try $0.changePosition(player: player, monsterID: monster.id) } }
                                    .disabled(monster.summonedTurn == state.turn || monster.positionChangedTurn == state.turn || monster.attacked)
                            }
                        }
                        if state.phase == .battle {
                            attackMenu(state, player: player, monster: monster)
                        }
                    }
                }.buttonStyle(.bordered).padding(.vertical, 4)
            }
            ForEach(Array(state.players[player].traps.enumerated()), id: \.element.id) { index, trap in
                Text(visiblePlayer == player ? "Phép/Bẫy: \(game.name(trap.card))" : "Phép/Bẫy úp \(index + 1)")
                if canControl, let effect = state.definition(of: trap.card).effect,
                   effect == .destroySpellTrap || effect == .returnMonster {
                    fastCardControls(trap.card, state: state, player: player)
                }
            }
            DisclosureGroup("Mộ (\(state.players[player].graveyard.count))") {
                ForEach(state.players[player].graveyard) { card in Text(game.name(card)) }
            }
        }
    }

    @ViewBuilder
    private func attackMenu(_ state: DuelState, player: Int, monster: DuelState.Monster) -> some View {
        let targets = state.players[1 - player].field
        Menu("Tấn công") {
            if targets.isEmpty {
                Button("Đánh trực tiếp") { act { try $0.attack(player: player, attackerID: monster.id) } }
            } else {
                ForEach(targets) { target in
                    Button(monsterName(target, owner: 1 - player)) {
                        act { try $0.attack(player: player, attackerID: monster.id, targetID: target.id) }
                    }
                }
            }
        }.disabled(monster.attacked || monster.faceDown || monster.position != .attack)
    }

    private func monsterName(_ monster: DuelState.Monster, owner: Int) -> String {
        monster.faceDown && visiblePlayer != owner ? "Quái úp #\(monster.id)" : game.name(monster.card)
    }

    private func materialNames(_ ids: [Int], state: DuelState, player: Int) -> String {
        let cards = state.players[player].hand + state.players[player].field.map(\.card)
        return ids.map { id in
            cards.first(where: { $0.id == id }).map(game.name) ?? "Thẻ #\(id)"
        }.joined(separator: " + ")
    }

    @ViewBuilder
    private func specialFromHand(_ card: DuelState.CardInstance, state: DuelState, player: Int) -> some View {
        let attack = DuelAction.specialSummonFromHand(cardID: card.id, position: .attack)
        let defense = DuelAction.specialSummonFromHand(cardID: card.id, position: .defense)
        HStack {
            Button("Đặc biệt • thế công") { act { try $0.apply(action: attack, player: player) } }
                .disabled(!legal(attack, state: state, player: player))
            Button("Đặc biệt • thế thủ") { act { try $0.apply(action: defense, player: player) } }
                .disabled(!legal(defense, state: state, player: player))
        }
    }

    @ViewBuilder
    private func extraDeckControls(_ state: DuelState, player: Int) -> some View {
        Section("Extra Deck của bạn") {
            ForEach(state.players[player].extraDeck) { card in
                if state.definition(of: card).kindCode == 17 {
                    let sets = state.synchroMaterialSets(player: player, extraCardID: card.id)
                    Text(game.name(card)).font(.headline)
                    if sets.isEmpty { Text("Cần 1 Tuner và ít nhất 1 quái không phải Tuner, tổng cấp độ 6.").font(.caption) }
                    ForEach(Array(sets.enumerated()), id: \.offset) { entry in
                        Menu(materialNames(entry.element, state: state, player: player)) {
                            synchroButton(card, materials: entry.element, position: .attack, state: state, player: player)
                            synchroButton(card, materials: entry.element, position: .defense, state: state, player: player)
                        }
                    }
                } else {
                    Text("\(game.name(card)) • dùng Polymerization và đúng nguyên liệu").font(.subheadline)
                }
            }
        }
    }

    private func synchroButton(_ card: DuelState.CardInstance, materials: [Int], position: DuelState.Position,
                               state: DuelState, player: Int) -> some View {
        let action = DuelAction.synchroSummon(extraCardID: card.id, materialIDs: materials, position: position)
        return Button(position == .attack ? "Synchro thế công" : "Synchro thế thủ") {
            act { try $0.apply(action: action, player: player) }
        }.disabled(!legal(action, state: state, player: player))
    }

    @ViewBuilder
    private func fastCardControls(_ card: DuelState.CardInstance, state: DuelState, player: Int) -> some View {
        let effect = state.definition(of: card).effect
        if effect == .judgment {
            Button("Solemn Judgment") { act { try $0.activateCounter(player: player, trapID: card.id) } }
                .disabled(!legal(.counter(trapID: card.id), state: state, player: player))
        } else if effect == .mirrorForce {
            let action = DuelAction.activateSpell(cardID: card.id, targetID: nil, targetPlayer: nil, position: .attack)
            Button("Mirror Force") { act { try $0.apply(action: action, player: player) } }
                .disabled(!legal(action, state: state, player: player))
        } else if effect == .destroySpellTrap {
            Menu("MST • chọn Phép/Bẫy") {
                ForEach(0..<2, id: \.self) { owner in
                    ForEach(state.players[owner].traps.filter { $0.id != card.id }) { target in
                        mstTarget(card, targetID: target.id, owner: owner, state: state, player: player)
                    }
                    ForEach(state.chain.filter { $0.player == owner && $0.sourceOnField && $0.card.id != card.id }) { link in
                        mstTarget(card, targetID: link.card.id, owner: owner, state: state, player: player)
                    }
                }
            }
        } else if effect == .returnMonster {
            Menu("Compulsory Evacuation Device • chọn quái") {
                ForEach(0..<2, id: \.self) { owner in
                    ForEach(state.players[owner].field) { target in
                        let action = DuelAction.activateSpell(cardID: card.id, targetID: target.id, targetPlayer: owner, position: .attack)
                        Button(monsterName(target, owner: owner)) { act { try $0.apply(action: action, player: player) } }
                            .disabled(!legal(action, state: state, player: player))
                    }
                }
            }
        } else if effect == .kuriboh {
            let action = DuelAction.activateKuriboh(cardID: card.id)
            Button("Kuriboh • bỏ từ tay để chặn sát thương") { act { try $0.apply(action: action, player: player) } }
                .disabled(!legal(action, state: state, player: player))
        }
    }

    private func mstTarget(_ card: DuelState.CardInstance, targetID: Int, owner: Int,
                           state: DuelState, player: Int) -> some View {
        let action = DuelAction.activateSpell(cardID: card.id, targetID: targetID, targetPlayer: owner, position: .attack)
        return Button(spellTrapName(state, owner: owner, id: targetID)) {
            act { try $0.apply(action: action, player: player) }
        }.disabled(!legal(action, state: state, player: player))
    }

    private func spellTrapName(_ state: DuelState, owner: Int, id: Int) -> String {
        if let source = state.chain.first(where: { $0.card.id == id }) {
            let location = source.sourceOnField ? "Người \(owner + 1)" : "đã rời sân"
            return "\(game.name(source.card)) • \(location)"
        }
        if let card = state.players.flatMap({ $0.graveyard }).first(where: { $0.id == id }) {
            return "\(game.name(card)) • đã vào Mộ Người \(card.owner + 1)"
        }
        if visiblePlayer == owner, let trap = state.players[owner].traps.first(where: { $0.id == id }) {
            return "\(game.name(trap.card)) • Người \(owner + 1)"
        }
        return "Phép/Bẫy úp #\(id) • Người \(owner + 1)"
    }

    private func legal(_ action: DuelAction, state: DuelState, player: Int) -> Bool {
        var trial = state
        do { try trial.apply(action: action, player: player); return true }
        catch { return false }
    }

    private func act(_ action: (inout DuelState) throws -> Void) {
        game.perform(action)
        guard game.actionError == nil else { return }
        tributes = []; discards = []
        if let state = game.state {
            let controller = game.controller(state)
            if game.opponent == .computer { visiblePlayer = 0 }
            else if visiblePlayer != controller || state.winner != nil { visiblePlayer = nil }
        }
    }

    private func clearPrivateState() { visiblePlayer = game.opponent == .computer ? 0 : nil; tributes = []; discards = [] }
}
