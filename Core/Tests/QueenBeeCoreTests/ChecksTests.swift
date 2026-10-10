import Foundation
import Testing
@testable import QueenBeeCore

@Suite struct ChecksTests {
    @Test func containsIgnoresCaseAndSurroundingSpace() {
        #expect(Checks.textCheck(.contains, value: " approved ", message: "Looks good. APPROVED.") == true)
        #expect(Checks.textCheck(.contains, value: "approved", message: "Needs work") == false)
        #expect(Checks.textCheck(.contains, value: "  ", message: "anything") == false)
    }

    @Test func notContainsIsTheOpposite() {
        #expect(Checks.textCheck(.notContains, value: "TODO", message: "all done") == true)
        #expect(Checks.textCheck(.notContains, value: "todo", message: "one TODO left") == false)
        #expect(Checks.textCheck(.notContains, value: "", message: "anything") == true)
    }

    @Test func regexIgnoresCaseAndABadPatternIsFalse() {
        #expect(Checks.textCheck(.regex, value: "^score: \\d+$", message: "Score: 42") == true)
        #expect(Checks.textCheck(.regex, value: "\\bfail(ed)?\\b", message: "2 tests FAILED") == true)
        #expect(Checks.textCheck(.regex, value: "^done$", message: "not done yet") == false)
        #expect(Checks.textCheck(.regex, value: "([unclosed", message: "([unclosed") == false)
        #expect(Checks.textCheck(.regex, value: "", message: "anything") == false)
    }

    @Test func judgeChecksAreNotTextChecks() {
        #expect(Checks.textCheck(.judge, value: "It is approved", message: "approved") == nil)
    }

    @Test func templatesFillInMessageAndFrom() {
        #expect(Checks.fillTemplate("{{from}} wrote:\n{{message}}\nReview it.", message: "A haiku", from: "Writer")
            == "Writer wrote:\nA haiku\nReview it.")
        #expect(Checks.fillTemplate("", message: "A haiku", from: "Writer") == "A haiku")
        #expect(Checks.fillTemplate("  \n", message: "A haiku", from: "Writer") == "A haiku")
        #expect(Checks.fillTemplate("Review this.", message: "A haiku", from: "Writer") == "Review this.\n\nA haiku")
        #expect(Checks.fillTemplate("{{ message }} / {{message}}", message: "x", from: "W") == "x / x")
    }

    @Test func aMessageThatLooksLikeATemplateIsNotFilledAgain() {
        #expect(Checks.fillTemplate("{{message}} by {{from}}", message: "{{from}}", from: "Writer") == "{{from}} by Writer")
        #expect(Checks.fillTemplate("Keep {{this}}: {{message}}", message: "x", from: "W") == "Keep {{this}}: x")
    }

    @Test func combineHeadsEachMessageWithItsSender() {
        let text = Checks.combine([(from: "Writer", text: "  Draft one\n"), (from: "Critic", text: "Too long")])
        #expect(text == "## From Writer\nDraft one\n\n## From Critic\nToo long")
    }

    @Test func theJudgePromptCarriesTheStatementAndTheEndOfTheMessage() {
        let message = String(repeating: "a", count: 5000) + String(repeating: "b", count: 12000)
        let prompt = Checks.judgePrompt(statement: "The tests pass", message: message)
        #expect(prompt.contains("The tests pass"))
        #expect(prompt.contains(String(repeating: "b", count: 12000)))
        #expect(!prompt.contains("aaaa"))
    }

    @Test func thePickPromptListsTheBranches() {
        let prompt = Checks.pickPrompt(branches: ["bug", "feature"], message: "It crashes on launch")
        #expect(prompt.contains("bug") && prompt.contains("feature") && prompt.contains("other"))
        #expect(prompt.contains("It crashes on launch"))
    }

    @Test func branchRepliesAreMatchedLoosely() {
        let branches = ["bug", "bug report", "Feature"]
        #expect(Checks.parseBranch("bug", branches: branches) == "bug")
        #expect(Checks.parseBranch(" \"FEATURE\". ", branches: branches) == "Feature")
        #expect(Checks.parseBranch("`bug report`", branches: branches) == "bug report")
        #expect(Checks.parseBranch("Feature, because it asks for something new", branches: branches) == "Feature")
        #expect(Checks.parseBranch("bug report: it crashes", branches: branches) == "bug report")
        #expect(Checks.parseBranch("other", branches: branches) == nil)
        #expect(Checks.parseBranch("", branches: branches) == nil)
        #expect(Checks.parseBranch("question", branches: branches) == nil)
    }

    @Test func savePathsIntoGitClaudeAndQueenBeeFoldersAreProtected() {
        for path in [".git/config", ".claude/settings.json", ".queenbee/flows/a.json", "sub/.git/hooks/pre-commit",
                     ".GIT/config", "output/../.git/config", "/.git/config", ".claude"] {
            #expect(Checks.isProtectedSavePath(path), "\(path)")
        }
        for path in ["output/answer.md", "answer.md", "", ".github/notes.md", "git/config", "docs/.gitignore", ".gitignore"] {
            #expect(!Checks.isProtectedSavePath(path), "\(path)")
        }
    }
}
