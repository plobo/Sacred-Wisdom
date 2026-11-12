import Foundation
import Testing
@testable import SacredWisdom

@Suite struct SearchTextNormalizerTests {
    @Test func foldsArabicMarksAndAlefVariants() {
        #expect(SearchTextNormalizer.normalize("ٱلرَّحْمَٰنِ ٱلرَّحِيمِ") == "الرحمن الرحيم")
        #expect(SearchTextNormalizer.normalize("أإآ") == "ااا")
    }

    @Test func foldsHebrewPointsAndSplitsOnMaqaf() {
        #expect(SearchTextNormalizer.normalize("עַל־מֵי") == "על מי")
        #expect(SearchTextNormalizer.normalize("אֶחְסָר׃") == "אחסר ")
    }

    @Test func lowercasesAndLeavesOtherScriptsIntact() {
        #expect(SearchTextNormalizer.normalize("The LORD") == "the lord")
        #expect(SearchTextNormalizer.normalize("ਸਤਿ ਨਾਮੁ") == "ਸਤਿ ਨਾਮੁ")
        #expect(SearchTextNormalizer.normalize("कर्मण्येवाधिकारस्ते") == "कर्मण्येवाधिकारस्ते")
    }

    @Test func wordsSplitOnPunctuation() {
        #expect(SearchTextNormalizer.words(in: "name's sake: 5:9 — ॥੧॥") == ["name", "s", "sake", "5", "9", "੧"])
    }
}

@Suite struct SearchQueryParserTests {
    @Test func keywordsArePrefixMatchedWhenLongEnough() {
        let query = SearchQueryParser.parse("  Forgiveness   in ")
        #expect(query.clauses == [.term("forgiveness", prefix: true)])
        #expect(query.droppedStopWords == ["in"])
        #expect(query.mode == .keyword)
    }

    @Test func questionsKeepOnlyMeaningfulWords() {
        #expect(SearchQueryParser.parse("What is said about mercy?").clauses == [.term("mercy", prefix: true)])
        #expect(SearchQueryParser.parse("How can hatred cease?").keywordTerms == ["hatred", "cease"])
    }

    @Test func onlyStopWordsAreKept() {
        #expect(SearchQueryParser.parse("the").clauses == [.term("the", prefix: true)])
    }

    @Test func quotedTextIsAnExactPhrase() {
        let query = SearchQueryParser.parse(#"yoga "skill in action""#)
        #expect(query.clauses == [.term("yoga", prefix: true), .phrase(["skill", "in", "action"])])
        #expect(query.mode == .mixed)
        #expect(SearchQueryParser.parse("“still waters”").mode == .phrase)
        #expect(SearchQueryParser.parse(#""peacemakers""#).clauses == [.term("peacemakers", prefix: false)])
    }

    @Test func unbalancedQuoteTreatsRestAsPhrase() {
        #expect(SearchQueryParser.parse(#"love "green pastures"#).clauses ==
                [.term("love", prefix: true), .phrase(["green", "pastures"])])
    }

    @Test func duplicatesAndEmptyInput() {
        #expect(SearchQueryParser.parse("peace Peace PEACE").clauses == [.term("peace", prefix: true)])
        #expect(SearchQueryParser.parse("   ").isEmpty)
        #expect(SearchQueryParser.parse(#""""#).isEmpty)
        #expect(SearchQueryParser.parse("?!…").isEmpty)
    }

    @Test func referencesAndOtherScripts() {
        #expect(SearchQueryParser.parse("Matthew 5:9").keywordTerms == ["matthew", "5", "9"])
        #expect(SearchQueryParser.parse("ٱلرَّحِيمِ").keywordTerms == ["الرحيم"])
    }
}

@Suite struct SearchHighlighterTests {
    private func highlighted(_ text: String, _ terms: [String]) -> [String] {
        SearchHighlighter.ranges(of: terms, in: text).map { String(text[$0]) }
    }

    @Test func highlightsWholeWordsFromPrefixes() {
        #expect(highlighted("Blessed are the peacemakers: for they", ["peace"]) == ["peacemakers"])
        #expect(highlighted("Peace, peace, PEACE", ["peace"]) == ["Peace", "peace", "PEACE"])
    }

    @Test func ignoresMatchesInsideWords() {
        #expect(highlighted("appeased", ["peace"]).isEmpty)
    }

    @Test func ignoresDiacriticsAndMergesOverlaps() {
        #expect(highlighted("Manopubbaṅgamā dhammā", ["manopubbangama"]) == ["Manopubbaṅgamā"])
        #expect(highlighted("goodness and mercy", ["good", "goodness"]) == ["goodness"])
    }

    @Test func foldedMatchingFindsUnpointedTermsInPointedText() {
        #expect(SearchHighlighter.matchesFolded(["الرحيم"], in: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ"))
        #expect(SearchHighlighter.matchesFolded(["רעי"], in: "יְהוָה רֹעִי לֹא אֶחְסָר׃"))
        #expect(!SearchHighlighter.matchesFolded(["merciful"], in: "بِسْمِ ٱللَّهِ"))
    }

    @Test func summaryPluralizes() {
        #expect(SearchResultsSummary.text(passages: 1, traditions: 1) == "1 passage in 1 tradition")
        #expect(SearchResultsSummary.text(passages: 3, traditions: 2) == "3 passages in 2 traditions")
    }

    @Test func attributedTextIsUnchanged() {
        let text = "He restoreth my soul"
        #expect(String(SearchHighlighter.attributed(text, terms: ["soul"]).characters) == text)
    }
}

@Suite struct SearchSuggestionProviderTests {
    @Test func completesFromRecentThenSuggestions() {
        let recent = [SearchHistoryItem(id: UUID(), query: "Merciful Lord", searchedAt: Date())]
        let completions = SearchSuggestionProvider().completions(for: "merc", recent: recent)
        #expect(completions.first == "Merciful Lord")
        #expect(completions.contains("What is said about the merciful?"))
        #expect(SearchSuggestionProvider().completions(for: "  ", recent: recent).isEmpty)
    }
}
