import Foundation

enum CardPropDecoder {
    static func labels(_ value: UInt32) -> [String] {
        let flags: [(UInt32, String)] = [(1,"Monster"),(2,"Spell"),(4,"Trap"),(0x10,"Normal"),(0x20,"Effect"),(0x40,"Fusion"),(0x80,"Ritual"),(0x200,"Spirit"),(0x400,"Union"),(0x800,"Gemini"),(0x1000,"Tuner"),(0x2000,"Synchro"),(0x4000,"Token"),(0x8000,"Flip"),(0x10000,"Toon"),(0x20000,"Xyz"),(0x40000,"Pendulum"),(0x80000,"Link")]
        return flags.filter { value & $0.0 != 0 }.map(\.1)
    }
}
