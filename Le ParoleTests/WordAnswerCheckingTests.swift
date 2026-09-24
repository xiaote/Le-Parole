import Foundation
import Testing
@testable import Le_Parole

@Suite("Word answer checking")
struct WordAnswerCheckingTests {
    // MARK: - English

    @Test("English answers accepted", arguments: [
        ("house", [], "house"),
        ("house", [], "  House "),
        ("house", ["home"], "home"),
        ("to have to", [], "have to"),
        ("to have to", [], "to have to"),
        ("do not", [], "don't"),
        ("I'm tired", [], "i am tired"),
        ("it’s late", [], "it is late"),
        ("apple (fruit)", [], "apple"),
        ("fifty years", [], "50 years"),
        ("24", [], "twenty-four"),
        ("twenty-four", [], "twenty four"),
        ("house", [], "hous"),            // 5 letters: one typo allowed
        ("elephant", [], "elephnt"),      // one typo
        ("beautiful", [], "butiful"),     // 9 letters: two typos allowed
    ] as [(String, [String], String)])
    func englishAccepted(english: String, alternatives: [String], input: String) {
        let word = Fixtures.word("x", english, alternatives: alternatives)
        #expect(word.isCorrectEnglish(input))
    }

    @Test("English answers rejected", arguments: [
        ("house", "dog"),
        ("cat", "car"),           // 3 letters: no typo tolerance
        ("book", "boo"),          // 4 letters: no typo tolerance
        ("house", "hosue"),       // 5 letters: two edits too many
        ("elephant", "elefant"),  // 8 letters: two edits too many
        ("fifty years", "15 years"),
    ])
    func englishRejected(english: String, input: String) {
        #expect(!Fixtures.word("x", english).isCorrectEnglish(input))
    }

    // MARK: - Italian

    @Test("Italian answers tolerate accents, case and apostrophe style", arguments: [
        ("perché", "perche"),
        ("perché", "perchè"),
        ("città", "Citta"),
        ("l'acqua", "l’acqua"),
        ("l’acqua", "l'acqua"),
        ("l'acqua", "l`acqua"),
        ("casa", " casa "),
    ])
    func italianAccepted(italian: String, input: String) {
        #expect(Fixtures.word(italian, "x").isCorrectItalian(input))
    }

    @Test func italianRejectsDifferentWord() {
        #expect(!Fixtures.word("casa", "house").isCorrectItalian("cosa"))
        #expect(!Fixtures.word("casa", "house").isCorrectItalian("case"))
    }

    // MARK: - Inflections

    @Test("Inflection variants", arguments: [
        ("Noun: il libro, i libri", "libri", true),
        ("Noun: il libro, i libri", "Libri", true),
        ("Noun: il libro, i libri", "libro", true),
        ("Noun: l'amico, gli amici", "amici", true),
        ("Noun: la città, le città", "citta", true),
        ("Adj: bello, bella, belli, belle", "belle", true),
        ("Noun: il libro, i libri", "il libri", false),
        ("Noun: il libro, i libri", "libraio", false),
        ("libro, libri", "libri", false),  // no "Type:" prefix
    ])
    func inflectionVariant(inflections: String, input: String, expected: Bool) {
        let word = Fixtures.word("libro", "book", inflections: inflections)
        #expect(word.isInflectionVariant(input) == expected)
    }

    @Test func noInflectionsMeansNoVariant() {
        #expect(!Fixtures.word("libro", "book").isInflectionVariant("libri"))
    }

    // MARK: - Lookup candidates

    @Test func lookupCandidatesCoverAccentsAndCase() {
        let candidates = Word.italianLookupCandidates("  Citta ")
        #expect(candidates == candidates.sorted())
        for expected in ["citta", "città", "Città", "CITTÀ", "cìtta"] {
            #expect(candidates.contains(expected), "missing \(expected)")
        }
    }

    @Test func lookupCandidatesStripAccents() {
        let candidates = Word.italianLookupCandidates("perché")
        #expect(candidates.contains("perché"))
        #expect(candidates.contains("perche"))
        #expect(candidates.contains("pèrché"))
    }

    @Test func lookupCandidatesCoverBothApostrophes() {
        let candidates = Word.italianLookupCandidates("l’acqua")
        #expect(candidates.contains("l'acqua"))
        #expect(candidates.contains("l’acqua"))
        #expect(candidates.contains("L'acqua"))
    }

    @Test func lookupCandidatesForBlankInputAreEmpty() {
        #expect(Word.italianLookupCandidates("").isEmpty)
        #expect(Word.italianLookupCandidates("   ").isEmpty)
    }
}
