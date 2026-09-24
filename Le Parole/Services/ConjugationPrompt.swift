import Foundation

/// The single source of the conjugation-flashcard rules shared by the
/// on-device model and Gemini. Provider-specific output formats (XML for the
/// on-device model, a JSON array for Gemini) stay with each provider.
nonisolated enum ConjugationPrompt {
    static let rules = """
    - ANSWER: The answer MUST be the exact conjugated verb only (no SUBJECT pronoun like io/tu/lui/noi/voi/loro, no infinitive), except for the special PIACERE construction below. If the verb is reflexive (ends in -rsi), you MUST include the reflexive pronoun (mi, ti, si, ci, vi) in the answer.
    - PIACERE IS THE ONE EXCEPTION TO THE SUBJECT RULE: it normally means "to like", so the requested pronoun is the EXPERIENCER / indirect object. Include its clitic in the answer and use a singular thing liked: io→"mi", tu→"ti", lui/lei→"gli" or "le", noi→"ci", voi→"vi", loro→"gli". Examples: "Ti piacerà quel film", "Spero che vi piaccia il concerto", "Mi è piaciuto quel libro". For lui/lei, provide complete alternatives separated by a slash, for example "gli piacerà/le piacerà". Never use "piacere di".
    - MANCARE: The requested pronoun MUST be the grammatical subject. Use a natural sense such as "Tu mancherai all'appuntamento" or "Tu mi mancherai". Do not force the requested pronoun into an indirect-object role.
    - REFLEXIVE PRONOUNS: If the verb is reflexive (e.g. 'svegliarsi'), the reflexive pronoun (mi, ti, si, ci, vi) MUST be inside the answer. DO NOT write the reflexive pronoun outside the blank in the sentence. The blank replaces the ENTIRE conjugated reflexive verb. Incorrect: 'lui si _____ (svegliarsi)'. Correct: 'lui _____ (svegliarsi)'. If you use the verb reflexively (e.g. 'mi sveglio'), the infinitive in the parentheses MUST be the reflexive form (e.g. '_____ (svegliarsi)', NOT '_____ (svegliare)').
    - UNNECESSARY PRONOUNS: Do not add object pronouns unless the verb or the intended meaning requires them (for example, reflexives and "Tu mi mancherai"). The requested pronoun remains the SUBJECT of the sentence.
    - SUBJECT PRONOUNS: 'loro' means 'they'. NEVER write 'I loro'.
    - MULTI-WORD VERBS (e.g. 'alzarsi in piedi', 'andare d'accordo'): Put the extra words (e.g. 'in piedi') OUTSIDE the blank in the sentence. The blank and parentheses MUST only contain the root verb. Example sentence: "_____ (alzarsi) in piedi." The answer MUST be only the conjugated root verb (e.g., "ti alzi").
    - SIMPLE TENSES (presente, imperfetto, futuro semplice, condizionale presente, congiuntivo presente, congiuntivo imperfetto, imperativo): the answer MUST be exactly ONE word (plus the reflexive pronoun or PIACERE clitic if applicable). NEVER use auxiliary verbs (essere/avere + past participle) for these tenses; that creates a different compound tense.
    - CONGIUNTIVO TRIGGERS: NEVER use phrases like 'sperare che', 'pensare che', 'credere che', 'aspettarsi che', 'volere che' UNLESS the requested tense is explicitly 'congiuntivo'. If the requested tense is 'imperfetto', 'passato prossimo', or 'presente', you MUST NOT use verbs of opinion or expectation + 'che'.
    - AUXILIARY VERBS & PARTICIPLES: For compound tenses, use ESSERE for motion/state verbs (andare, venire, uscire, arrivare, partire, tornare, stare, rimanere, essere, diventare), intransitive verbs of happening (succedere, capitare), and all reflexive verbs. Use AVERE for all others. With ESSERE, the past participle MUST agree in gender and number with the subject. For 'succedere', the past participle is 'successo' (e.g. è successo).
    - GENDER AMBIGUITY: If the pronoun is 'io', 'tu', 'noi', or 'voi' AND the verb requires 'essere', the gender is ambiguous. You MUST provide BOTH the masculine and feminine forms in the answer, separated by a slash (e.g., "sono andato/sono andata", "ci siamo vestiti/ci siamo vestite"). DO NOT use abbreviations like 'andato/a'. Do NOT include gendered adjectives in the sentence that would force one specific gender.
    - GERUNDIO / STARE + GERUNDIO: NEVER combine stare with a simple present or infinitive. The gerundio ALWAYS ends in -ando or -endo (irregular: facendo, dicendo, bevendo).
    - SPELLING & ACCENTS: Pay strict attention to spelling! Verbs like 'bere', 'volere', 'venire', 'tenere', 'rimanere' have irregular future/conditional stems (e.g. berrò, vorrò, verrò, terrò, rimarrò).
    - NATURAL LANGUAGE: The sentence must sound like something a native Italian speaker would actually say in everyday conversation. Avoid overly formal, robotic, or unnatural phrasing.
    \(explanationRules)
    """

    static let explanationRules = """
    - EXPLANATION CONTENT: Teach how the answer is conjugated, not why the sentence calls for the requested tense. Do not justify the tense using time markers, sentence context, or phrases such as "refers to the present/past/future."
    - Make the explanation compact and scannable. Use the labels and line breaks below exactly. Do not write a paragraph, repeat the sentence, or repeat the tense name.
    - Always output exactly TWO lines. Line 1: "Rule: [stem/construction] + [ending/component] → [answer] ([brief rule, naming any irregular change])." Keep it to about 20 words. For -ciare and -giare verbs, avoid an ambiguous stem equation; instead use: "Rule: regular -are [pronoun] ending [ending] → [answer] ([spelling change if applicable])." Line 2: "Forms (io→loro): [six forms in standard io, tu, lui/lei, noi, voi, loro order, separated by ·]." Do not repeat the pronouns beside every form. For the imperative use "Forms (tu→loro):" and include only applicable persons. Examples: "Rule: vien- + -i → vieni (irregular tu stem).\nForms (io→loro): vengo · vieni · viene · veniamo · venite · vengono" and "Rule: regular -are noi ending -iamo → mangiamo (adjacent i written once).\nForms (io→loro): mangio · mangi · mangia · mangiamo · mangiate · mangiano"
    - For compound or progressive forms, the Rule line must show the auxiliary or stare, the participle or gerund, reflexive pronoun, and agreement when applicable. The Forms line must contain the complete conjugated construction. Examples: "Rule: ha + visto → ha visto (irregular participle of vedere).\nForms (io→loro): ho visto · hai visto · ha visto · abbiamo visto · avete visto · hanno visto" and "Rule: stanno + bevendo → stanno bevendo (irregular gerund of bere).\nForms (io→loro): sto bevendo · stai bevendo · sta bevendo · stiamo bevendo · state bevendo · stanno bevendo"
    - Never merely say that the requested pronoun "requires" the answer.
    """

    /// What the sentence must contain so the learner can tell which tense is wanted.
    static func tenseContext(for tense: String) -> String {
        switch tense.lowercased() {
        case "presente":
            "Express a current action, habit, or general truth (e.g. 'oggi', 'di solito', 'tutti i giorni'). NEVER use past time markers like 'ieri', 'scorso', or 'fa'."
        case "passato prossimo":
            "Include a specific past time marker: 'ieri', 'stamattina', 'la settimana scorsa', 'poco fa'. Answer = auxiliary + past participle (e.g. 'ho mangiato', 'sono andato'), following the AUXILIARY rule above."
        case "imperfetto":
            "Signal habitual/ongoing past: use 'da bambino/a', 'una volta', 'a quei tempi', 'mentre', 'allora', or describe a past state/feeling ('Mi sentivo stanco', 'Avevo fame', 'Era grande'). Use the simple imperfetto (e.g. 'tornavate', NEVER 'eravate tornati'). Do NOT use 'ieri' (that implies passato prossimo). Do NOT use 'ogni giorno', 'spesso', or 'di solito' by themselves, as they invite the present tense."
        case "futuro semplice":
            "Include a future time marker: 'domani', 'tra una settimana', 'l'anno prossimo', 'fra poco', 'presto'."
        case "imperativo":
            "Write the sentence as a direct command or suggestion to the requested pronoun. For formal 'lui/lei' and 'loro', the imperative takes the present subjunctive form (e.g. for -are verbs, use the -i ending like 'parli', 'basti', 'guardi'; for -ere/-ire verbs, use the -a ending like 'legga', 'senta'). Do NOT use time markers that imply the past or habitual action."
        case "condizionale presente":
            "Use a present hypothetical or polite context: 'vorrei', 'potrei', 'se potessi...', 'al posto tuo'."
        case "condizionale passato":
            "Use either a genuine past counterfactual ('Se avessi saputo, avrei chiamato') or a future-in-the-past context ('Il meteo aveva previsto che sarebbe piovuto'). Do NOT combine 'al posto tuo' with an unexplained past fact such as 'ieri sera'."
        case "congiuntivo presente":
            "Use a present or future trigger clause: 'penso che', 'spero che', 'è importante che', 'voglio che'. For target 'io', the main clause MUST name another person (for example, 'Mia madre spera che io...'). NEVER use an io or subjectless main clause such as 'Spero che io...' or 'Voglio che io...'."
        case "congiuntivo imperfetto":
            "Use a past or hypothetical trigger clause with an action simultaneous with or later than that trigger: 'Volevo che tu venissi', 'Mia madre sperava che io capissi', 'Se fossi ricco, non verrei...'. NEVER use completed-past markers such as 'ieri', 'la settimana scorsa', 'già', or an action completed before the trigger: those require congiuntivo trapassato instead. When using a se-clause, pair it with condizionale presente, NEVER condizionale passato. For target 'io', the main clause MUST name another person; NEVER use an io or subjectless main clause such as 'Volevo che io...'."
        case "presente progressivo":
            "Express an action happening RIGHT NOW: include 'in questo momento', 'adesso', or 'proprio ora'. Answer MUST be stare conjugated + gerundio. Stare: sto/stai/sta/stiamo/state/stanno. Gerundio: -are→-ando, -ere/-ire→-endo (irregular: fare→facendo, dire→dicendo, bere→bevendo). Example answer for 'io': 'sto mangiando'. The blank replaces both words."
        default:
            "Use a natural context that makes the tense clear."
        }
    }
}
