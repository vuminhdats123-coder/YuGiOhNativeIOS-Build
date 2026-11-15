import Foundation

enum CardPropDecoder {
    static let kinds: [Int: String] = [0:"Normal",1:"Effect",2:"Fusion",3:"Fusion Effect",4:"Ritual",5:"Ritual Effect",6:"Toon",7:"Spirit",8:"Union",9:"Gemini",10:"Token",13:"Spell",14:"Trap",15:"Tuner Normal",16:"Tuner Effect",17:"Synchro",18:"Synchro Effect",19:"Synchro Tuner Effect",22:"Xyz",23:"Xyz Effect",24:"Flip Effect",25:"Pendulum",26:"Pendulum Effect",27:"Special Summoned Effect",28:"Toon Special Summon Only",29:"Spirit Special Summon Only",30:"Tuner Effect Special Summon Only",32:"Tuner Flip Effect",33:"Pendulum Tuner Effect",34:"Xyz Pendulum Effect",35:"Pendulum Flip Effect",36:"Synchro Pendulum Effect",37:"Union Tuner Effect",38:"Ritual Spirit Effect",39:"Fusion Tuner",40:"Pendulum Effect Special Summon Only",41:"Fusion Pendulum Effect",42:"Link",43:"Link Effect",44:"Pendulum Tuner Normal",45:"Pendulum Spirit Effect"]
    static let attributes = [0:"None",1:"LIGHT",2:"DARK",3:"WATER",4:"FIRE",5:"EARTH",6:"WIND",7:"DIVINE",8:"Spell",9:"Trap"]
    static let races = [0:"Normal",1:"Dragon",2:"Zombie",3:"Fiend",4:"Pyro",5:"Sea Serpent",6:"Rock",7:"Machine",8:"Fish",9:"Dinosaur",10:"Insect",11:"Beast",12:"Beast-Warrior",13:"Plant",14:"Aqua",15:"Warrior",16:"Winged Beast",17:"Fairy",18:"Spellcaster",19:"Thunder",20:"Reptile",21:"Psychic",22:"Wyrm",23:"Cyberse",24:"Divine-Beast",30:"Spell",31:"Trap"]
    static let genres = ["Recover LP","Damage LP","Help Draw","Special Summon","Negate Effect","Search Deck","Recover from Graveyard","Increase/Decrease ATK/DEF","Change Battle Position","Set Control","Destroy Monster","Destroy Spell Card","Destroy Hand","Destroy Deck","Remove Card","Return Card","Piercing","Direct Attack","Attack Multiple Times","Cannot Be Destroyed","Limit Attack","Cannot Normal Summon","Flip Effect Monster","Toon Monster","Spirit Monster","Union Monster","Gemini Monster","LV Monster","Original","Fusion Material Monster","Ritual","Token","Counter","Gamble","Attribute-related","Type-related","Tuner","Synchro Monster","Send to Graveyard","Normal Monster","LIGHT","DARK","EARTH","WATER","FIRE","WIND","Xyz Monster","Level Modifier","Pendulum","Link Monster","DIVINE","New Card","Game Original","Card Variation"]
    static func genres(_ mask: UInt64) -> [String] { genres.indices.compactMap { mask & (UInt64(1) << UInt64($0)) != 0 ? genres[$0] : nil } }
}


struct CardRelation: Decodable {
    let archetypes: [Int]
    let links: [Link]
    let same: Same?
    struct Link: Decodable { let target: Int; let kind: String }
    struct Same: Decodable { let target: Int; let mode: String }
}

enum CardRelationStore {
    static let index: [String: CardRelation] = {
        guard let url = Bundle.main.url(forResource: "card-relation-index", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([String: CardRelation].self, from: data) else { return [:] }
        return value
    }()
    static func relation(for konamiID: Int?) -> CardRelation? { konamiID.flatMap { index[String($0)] } }
}


struct CardPackSummary: Decodable { let status: String; let nonZeroRecords: Int; let records: Int; let note: String }
enum CardPackStore {
    static let summary: CardPackSummary? = {
        guard let url = Bundle.main.url(forResource: "card-pack-summary", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CardPackSummary.self, from: data)
    }()
}


struct CardKanaReading: Decodable { let sourceIndex: Int; let english: String; let japanese: String }
enum CardKanaStore {
    static let readings: [Int: CardKanaReading] = {
        guard let url = Bundle.main.url(forResource: "card-kana-index", withExtension: "json", subdirectory: "GeneratedData"), let data = try? Data(contentsOf: url), let rows = try? JSONDecoder().decode([CardKanaReading].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.sourceIndex, $0) })
    }()
    static func reading(for sourceIndex: Int) -> CardKanaReading? { readings[sourceIndex] }
}
