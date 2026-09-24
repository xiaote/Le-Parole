import Testing
@testable import Le_Parole

struct ConjugationDisplayTests {
    @Test func pairsFormsWithPronounsAndMarksTheAnswer() {
        let (rule, forms) = ConjugationDisplay.parse(
            "Rule: vien- + -i → vieni (irregular tu stem).\nForms (io→loro): vengo · vieni · viene · veniamo · venite · vengono",
            answer: "vieni"
        )
        #expect(rule == "vien- + -i → vieni (irregular tu stem).")
        #expect(forms.map(\.pronoun) == ["io", "tu", "lui/lei", "noi", "voi", "loro"])
        #expect(forms.map(\.form) == ["vengo", "vieni", "viene", "veniamo", "venite", "vengono"])
        #expect(forms.filter(\.isAnswer).map(\.form) == ["vieni"])
    }

    @Test func imperativeFormsStartAtTu() {
        let (_, forms) = ConjugationDisplay.parse(
            "Rule: va' → va' (irregular).\nForms (tu→loro): va' · vada · andiamo · andate · vadano",
            answer: "andiamo"
        )
        #expect(forms.map(\.pronoun) == ["tu", "lui/lei", "noi", "voi", "loro"])
        #expect(forms.first(where: \.isAnswer)?.form == "andiamo")
    }

    @Test func matchesAnAnswerWithAlternatives() {
        let (_, forms) = ConjugationDisplay.parse(
            "Rule: sareste + cascati.\nForms (io→loro): sarei cascato/a · saresti cascato/a · sarebbe cascato/a · saremmo cascati/e · sareste cascati/e · sarebbero cascati/e",
            answer: "sareste cascati/sareste cascate"
        )
        #expect(forms.filter(\.isAnswer).map(\.form) == ["sareste cascati/e"])
    }

    @Test func unmatchedCountLeavesPronounsOut() {
        let (_, forms) = ConjugationDisplay.parse("Rule: x.\nForms (io→loro): a · b · c", answer: "b")
        #expect(forms.map(\.pronoun) == [nil, nil, nil])
        #expect(forms.first(where: \.isAnswer)?.form == "b")
    }

    @Test func ruleWithoutFormsHasNoTable() {
        let (rule, forms) = ConjugationDisplay.parse("Rule: mangi- + -o → mangio (regular -are, io).", answer: "mangio")
        #expect(rule == "mangi- + -o → mangio (regular -are, io).")
        #expect(forms.isEmpty)
    }

    @Test func summaryDropsTheClosingNote() {
        #expect(ConjugationDisplay.summary(of: "mangi- + -o → mangio (regular -are, io).") == "mangi- + -o → mangio")
        #expect(ConjugationDisplay.summary(of: "ha + visto → ha visto") == "ha + visto → ha visto")
    }
}
