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
            guard practice.count == 2, practice.allSatisfy({ $0.extra.isEmpty && $0.side.isEmpty }) else {
                throw DuelState.DuelError.invalid("Dữ liệu cần đúng hai bộ bài luyện tập không dùng Extra/Side Deck.")
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
            state = try DuelState(definitions: definitions, decks: decks, shuffle: true)
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
        state.pendingSummonChoice?.player ?? (state.chain.isEmpty ? state.activePlayer : state.priorityPlayer)
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
                Text("Quái Normal và 8 lá hiệu ứng. Có hồi sinh bằng Monster Reborn, gọi quái từ Deck bằng Unexpected Dai, Raigeki và Dark Hole. Chưa hỗ trợ effect quái, triệu hồi từ Extra Deck hay phản hồi khi tấn công.")
                    .font(.footnote)
                Text("Solemn Judgment hiện chỉ phủ nhận kích hoạt Phép/Bẫy, chưa phủ nhận triệu hồi.")
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
                            if let targetID = link.targetCardID, let owner = link.targetOwner,
                               let target = state.players[owner].graveyard.first(where: { $0.id == targetID }) {
                                Text("Mục tiêu: \(game.name(target)) • Mộ Người \(owner + 1)").font(.caption)
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
                Text("Người \(player + 1): \(zone.lp) LP · Bộ bài \(zone.deck.count) · Tay \(zone.hand.count) · Mộ \(zone.graveyard.count)")
            }
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
        } else if !state.chain.isEmpty {
            Section("Người \(controller + 1) phản hồi") {
                Text("Hiệu ứng chưa được áp dụng. Hai người cùng bỏ qua liên tiếp sẽ giải quyết chain.")
                    .font(.footnote)
                ForEach(state.players[controller].traps) { trap in
                    Button("Phản hồi: \(game.name(trap.card))") {
                        act { try $0.activateCounter(player: controller, trapID: trap.id) }
                    }.disabled(trap.setTurn == state.turn)
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
        }
    }

    @ViewBuilder
    private func handRow(_ card: DuelState.CardInstance, state: DuelState, player: Int) -> some View {
        let definition = state.definition(of: card)
        let isMain = state.phase == .main1 || state.phase == .main2
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.name).font(.headline)
            if definition.kindCode == 0 {
                Text("Cấp \(definition.level) • ATK \(definition.atk ?? 0) / DEF \(definition.def ?? 0)").font(.caption)
                HStack {
                    Button("Triệu hồi") { act { try $0.summon(player: player, cardID: card.id, tributes: Array(tributes)) } }
                    Button("Úp phòng thủ") { act { try $0.summon(player: player, cardID: card.id, tributes: Array(tributes), set: true) } }
                }.disabled(!isMain || state.normalSummonUsed)
            } else if definition.effect == .judgment {
                Button("Úp Bẫy") { act { try $0.setTrap(player: player, cardID: card.id) } }.disabled(!isMain)
            } else if definition.effect == .revive {
                Menu("Monster Reborn • chọn mục tiêu") {
                    ForEach(0..<2, id: \.self) { owner in
                        ForEach(state.players[owner].graveyard.filter { state.definition(of: $0).kindCode == 0 }) { target in
                            Menu("\(game.name(target)) • Mộ Người \(owner + 1)") {
                                Button("Triệu hồi thế công") {
                                    act { try $0.activateSpell(player: player, cardID: card.id, targetID: target.id, targetPlayer: owner, position: .attack) }
                                }
                                Button("Triệu hồi thế thủ") {
                                    act { try $0.activateSpell(player: player, cardID: card.id, targetID: target.id, targetPlayer: owner, position: .defense) }
                                }
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
        let canControl = visiblePlayer == player && state.activePlayer == player && state.chain.isEmpty && state.winner == nil
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
                Text(visiblePlayer == player ? "Bẫy: \(game.name(trap.card))" : "Bẫy úp \(index + 1)")
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
