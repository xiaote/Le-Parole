import Foundation
import Testing
@testable import Le_Parole

@Suite("ConjugationValidator")
struct ConjugationValidatorTests {
    private func output(_ sentence: String, answer: String, explanation: String = "Spiegazione.") -> String {
        "<sentence>\(sentence)</sentence><answer>\(answer)</answer><explanation>\(explanation)</explanation>"
    }

    private func validate(
        verb: String, tense: String, pronoun: String,
        sentence: String, answer: String
    ) -> ConjugationChallenge? {
        ConjugationValidator(verb: verb, tense: tense, pronoun: pronoun)
            .challenge(from: output(sentence, answer: answer))
    }

    @Test func acceptsFormContainingTheInfinitiveAsSubstring() throws {
        // "faremo" contains "fare"; only a whole-token infinitive is rejected.
        let challenge = try #require(validate(
            verb: "fare", tense: "futuro semplice", pronoun: "noi",
            sentence: "Domani noi _____ (fare) una lunga passeggiata in montagna.", answer: "faremo"
        ))
        #expect(challenge.answer == "faremo")
        #expect(challenge.sentence == "Domani noi _____ (fare) una lunga passeggiata in montagna.")
        #expect(challenge.tense == "futuro semplice")
        #expect(challenge.pronoun == "noi")
    }

    @Test func rejectsInfinitiveAsAnswer() {
        #expect(validate(
            verb: "fare", tense: "futuro semplice", pronoun: "noi",
            sentence: "Domani noi _____ (fare) una lunga passeggiata in montagna.", answer: "fare"
        ) == nil)
    }

    @Test("Rejects endings for a different person", arguments: [
        ("futuro semplice", "noi", "farete"),
        ("imperfetto", "io", "facevamo"),
        ("condizionale presente", "tu", "farei"),
    ])
    func rejectsWrongPerson(tense: String, pronoun: String, answer: String) {
        #expect(validate(
            verb: "fare", tense: tense, pronoun: pronoun,
            sentence: "Secondo me _____ (fare) sempre la cosa giusta per tutti.", answer: answer
        ) == nil)
    }

    @Test func acceptsCompoundTenseWithMatchingAuxiliary() {
        #expect(validate(
            verb: "mangiare", tense: "passato prossimo", pronoun: "io",
            sentence: "Ieri sera _____ (mangiare) una pizza buonissima con gli amici.", answer: "ho mangiato"
        ) != nil)
    }

    @Test("Rejects compound tenses missing or using the wrong auxiliary", arguments: ["mangiato", "sono mangiato", "hai mangiato"])
    func rejectsBadCompound(answer: String) {
        #expect(validate(
            verb: "mangiare", tense: "passato prossimo", pronoun: "io",
            sentence: "Ieri sera _____ (mangiare) una pizza buonissima con gli amici.", answer: answer
        ) == nil)
    }

    @Test func essereVerbAcceptsEssereAuxiliary() {
        #expect(validate(
            verb: "andare", tense: "passato prossimo", pronoun: "io",
            sentence: "L'anno scorso _____ (andare) in vacanza in Sicilia con la mia famiglia.", answer: "sono andato"
        ) != nil)
    }

    @Test func reflexiveVerbRequiresPronoun() {
        let sentence = "Ogni mattina _____ (svegliarsi) presto per andare al lavoro."
        #expect(validate(verb: "svegliarsi", tense: "presente", pronoun: "io", sentence: sentence, answer: "mi sveglio") != nil)
        #expect(validate(verb: "svegliarsi", tense: "presente", pronoun: "io", sentence: sentence, answer: "sveglio") == nil)
    }

    @Test func reflexiveImperativeMayAttachPronoun() {
        #expect(validate(
            verb: "svegliarsi", tense: "imperativo", pronoun: "voi",
            sentence: "Ragazzi, _____ (svegliarsi) subito, il treno parte tra venti minuti!", answer: "svegliatevi"
        ) != nil)
    }

    @Test func blanksAnswerWhenModelForgotTheBlank() throws {
        let challenge = try #require(validate(
            verb: "fare", tense: "futuro semplice", pronoun: "noi",
            sentence: "Domani noi faremo una lunga passeggiata in montagna.", answer: "faremo"
        ))
        #expect(challenge.sentence == "Domani noi _____ (fare) una lunga passeggiata in montagna.")
    }

    @Test func normalizesWrongInfinitiveHint() throws {
        let challenge = try #require(validate(
            verb: "fare", tense: "futuro semplice", pronoun: "noi",
            sentence: "Domani noi _____ (vivere) una lunga passeggiata in montagna.", answer: "faremo"
        ))
        #expect(challenge.sentence == "Domani noi _____ (fare) una lunga passeggiata in montagna.")
    }

    @Test func removesAnswerLeftNextToBlank() throws {
        let challenge = try #require(validate(
            verb: "fare", tense: "futuro semplice", pronoun: "noi",
            sentence: "Domani noi faremo _____ (fare) una lunga passeggiata in montagna.", answer: "faremo"
        ))
        #expect(challenge.sentence == "Domani noi _____ (fare) una lunga passeggiata in montagna.")
    }

    @Test func rejectsMissingTagsAndPlaceholders() {
        let validator = ConjugationValidator(verb: "fare", tense: "futuro semplice", pronoun: "noi")
        #expect(validator.challenge(from: "<sentence>Domani _____ (fare).</sentence><answer>faremo</answer>") == nil)
        #expect(validator.challenge(from: output("SCRIVERE_QUI _____ (fare)", answer: "faremo")) == nil)
    }

    /// Relies on NLLanguageRecognizer, which is available in the simulator.
    @Test func rejectsEnglishSentence() {
        #expect(validate(
            verb: "fare", tense: "futuro semplice", pronoun: "noi",
            sentence: "Tomorrow we _____ (fare) a very long walk in the mountains with our friends.", answer: "faremo"
        ) == nil)
    }

    /// The stem check fails ("bev" vs "man"), so this falls through to the
    /// NLTagger lemma, which must not resolve "bevo" to "mangiare".
    @Test func rejectsFormOfADifferentVerb() {
        #expect(validate(
            verb: "mangiare", tense: "presente", pronoun: "io",
            sentence: "Ogni giorno a pranzo _____ (mangiare) un panino al prosciutto.", answer: "bevo"
        ) == nil)
    }
}
