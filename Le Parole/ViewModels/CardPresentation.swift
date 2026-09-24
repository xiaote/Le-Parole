import UIKit

/// Everything the quiz card shows that follows from its `StudyCard`, resolved
/// once when the card is presented. The card view re-evaluates its body many
/// times per card (entrance, flip, notices), so lookups, shuffles and string
/// processing must not run there.
struct CardPresentation {
    enum Language {
        case english, italian

        var label: String { self == .english ? "English" : "Italian" }
        var speechCode: String { self == .english ? "en-US" : "it-IT" }
    }

    let card: StudyCard
    let diagram: WordDiagram?
    /// Width / height of the diagram images, so the card can frame them exactly.
    let promptImageAspectRatio: CGFloat
    let answerImageAspectRatio: CGFloat
    let concept: WordConcept?
    /// Shuffled once per presentation so the options never reorder.
    let visualQuiz: VisualQuizData?
    /// Present only for a conjugation card; a conjugation card is never shown
    /// without a ready challenge (see `prepareCurrentCardForImmediateDisplay`).
    let conjugation: ConjugationDisplay?

    let promptText: String
    let promptLanguage: Language
    let answerText: String
    let answerLanguage: Language
    /// Other English meanings: listed under the English side of the card.
    let alternatives: [String]
    let inflections: String?
    /// Recorded with a mistake so the review screen can show what was asked.
    let mistakeContext: MistakeContext?
    /// How long a correct typed answer stays on screen before the session
    /// moves on by itself: longer when there is more to read.
    let autoAdvanceDelay: Duration

    init(card: StudyCard, challenge: ConjugationChallenge?) {
        let word = card.userWord.word
        self.card = card
        diagram = SailingDiagramService.diagram(for: word)
        promptImageAspectRatio = Self.aspectRatio(ofImageNamed: diagram?.promptImageName)
        answerImageAspectRatio = Self.aspectRatio(ofImageNamed: diagram?.revealedImageName)
        concept = ConceptService.shared.concept(for: word.italian)
        visualQuiz = card.cardType == .recognition
            ? SailingDiagramService.visualQuizOptions(for: word)
            : nil
        conjugation = card.cardType == .conjugation
            ? challenge.map { ConjugationDisplay($0) }
            : nil

        switch card.cardType {
        case .recognition:
            promptLanguage = .italian
            answerLanguage = .english
        case .production:
            promptLanguage = .english
            answerLanguage = .italian
        case .conjugation:
            promptLanguage = .italian
            answerLanguage = .italian
        }
        promptText = conjugation?.sentence ?? card.prompt
        answerText = conjugation?.completedSentence ?? card.correctAnswer
        alternatives = card.cardType == .conjugation ? [] : word.cleanAlternatives
        inflections = card.cardType == .production ? word.inflections : nil

        if let conjugation {
            mistakeContext = MistakeContext(
                question: conjugation.sentence,
                answer: conjugation.answer,
                explanation: conjugation.explanation
            )
        } else if let target = visualQuiz?.target {
            mistakeContext = MistakeContext(question: target.title, answer: target.title, explanation: target.caption)
        } else {
            mistakeContext = nil
        }

        autoAdvanceDelay = if conjugation != nil {
            .seconds(4.5)
        } else if concept != nil {
            .seconds(2.5)
        } else if inflections != nil {
            .seconds(2.0)
        } else if card.cardType == .recognition && !alternatives.isEmpty {
            .seconds(1.2)
        } else {
            .seconds(0.8)
        }
    }

    private static func aspectRatio(ofImageNamed name: String?) -> CGFloat {
        guard let name, let size = UIImage(named: name)?.size, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    func accepts(_ input: String) -> Bool {
        if let conjugation { return conjugation.accepts(input) }
        return card.isCorrect(input)
    }
}

/// A conjugation challenge with its display strings computed once.
struct ConjugationDisplay {
    let sentence: String
    let answer: String
    /// The sentence with the blank filled in.
    let completedSentence: String
    /// The explanation shortened for the card.
    let explanation: String
    let tense: String
    let pronoun: String
    let englishTranslation: String

    init(_ challenge: ConjugationChallenge) {
        sentence = challenge.sentence
        answer = challenge.answer
        completedSentence = Self.completing(challenge.sentence, with: challenge.answer)
        explanation = Self.concise(challenge.explanation)
        tense = challenge.tense
        pronoun = challenge.pronoun
        englishTranslation = challenge.englishTranslation
    }

    /// The answer may list alternatives separated by "/".
    func accepts(_ input: String) -> Bool {
        answer.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(input.lowercased())
    }

    private static func completing(_ sentence: String, with answer: String) -> String {
        if let regex = try? Regex("_{3,}\\s*\\([^)]+\\)", as: Substring.self), sentence.contains(regex) {
            return sentence.replacing(regex, with: answer)
        }
        if let regex = try? Regex("_{3,}", as: Substring.self) {
            return sentence.replacing(regex, with: answer)
        }
        return sentence
    }

    private static func concise(_ explanation: String) -> String {
        var concise = explanation
            .replacingOccurrences(of: "Formation:", with: "Rule:", options: .caseInsensitive)
            .replacingOccurrences(
                of: #"(?i)\s+Full\s+(?:presente|passato prossimo|imperfetto|futuro semplice|imperativo|condizionale presente|condizionale passato|congiuntivo presente|congiuntivo imperfetto|presente progressivo):\s*"#,
                with: "\nForms: ",
                options: .regularExpression
            )

        let tenseNames = [
            "presente", "passato prossimo", "imperfetto", "futuro semplice",
            "imperativo", "condizionale presente", "condizionale passato",
            "congiuntivo presente", "congiuntivo imperfetto", "presente progressivo",
        ]
        for tense in tenseNames {
            concise = concise.replacingOccurrences(of: " in \(tense)", with: "", options: .caseInsensitive)
        }
        return concise
    }
}
