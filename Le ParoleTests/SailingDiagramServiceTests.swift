import Foundation
import Testing
@testable import Le_Parole

@Suite("SailingDiagramService sense gating")
struct SailingDiagramServiceTests {
    @Test("Vocabulary lookup", arguments: [
        ("ancora", "still", [], nil),
        ("ancora", "anchor", [], "ancora"),
        ("ancora", "still", ["anchor"], "ancora"),     // nautical sense among alternatives
        ("l'ancora", "the anchor", [], "ancora"),      // article stripped
        ("ancora", "anchorage", [], nil),              // sense must be a whole word
        ("albero", "tree", [], nil),
        ("albero", "mast", [], "albero"),
        ("albero maestro", "mainmast", [], "albero"),  // exact key without senses
        ("albero di Natale", "Christmas tree", [], nil),
        ("albero di Natale", "mast", [], nil),         // "albero" never matches inside a phrase
    ] as [(String, String, [String], String?)])
    func vocabularyLookup(italian: String, english: String, alternatives: [String], expectedID: String?) {
        let word = Fixtures.word(italian, english, alternatives: alternatives)
        #expect(SailingDiagramService.diagram(for: word)?.id == expectedID)
    }

    @Test func termLookupIgnoresSenses() {
        #expect(SailingDiagramService.diagram(for: "ancora")?.id == "ancora")
        #expect(SailingDiagramService.diagram(for: "albero di Natale") == nil)
    }
}
