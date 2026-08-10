import Foundation
import Testing
@testable import Sundries

@Suite("SourceIssue")
struct SourceIssueTests {
    private struct AnonymousError: LocalizedError {
        var errorDescription: String? { "Something went wrong." }
    }

    /// The point of `SourceIssueRepresentable`: the store never inspects which
    /// adapter it is talking to, the error classifies itself.
    @Test("Takes the kind a source-classified error asks for")
    func takesKindFromSourceClassifiedError() {
        let issue = SourceIssue.from(
            MarkdownSourceError.folderUnavailable,
            sourceID: TaskSourceDescriptor.markdown.id
        )

        #expect(issue.kind == .needsSetup)
        #expect(issue.sourceID == TaskSourceDescriptor.markdown.id)
        #expect(issue.message == MarkdownSourceError.folderUnavailable.localizedDescription)
    }

    @Test("Leaves ordinary source errors as operation failures", arguments: [
        MarkdownSourceError.invalidDestination,
        MarkdownSourceError.missingLocation,
        MarkdownSourceError.taskMovedOrChanged
    ])
    func leavesOrdinaryErrorsAsOperationFailures(error: MarkdownSourceError) {
        #expect(SourceIssue.from(error, sourceID: "markdown").kind == .operationFailed)
    }

    @Test("Falls back to an operation failure for errors that do not classify themselves")
    func fallsBackForUnclassifiedErrors() {
        let issue = SourceIssue.from(AnonymousError(), sourceID: "markdown")

        #expect(issue.kind == .operationFailed)
        #expect(issue.message == "Something went wrong.")
    }

    /// Only `needsSetup` earns the warning triangle and, in the panel, a route
    /// into Settings.
    @Test("Signals setup problems differently from transient failures")
    func signalsSetupProblemsDifferently() {
        #expect(SourceIssue.markdownFolderUnresolvable.kind == .needsSetup)
        #expect(SourceIssue.markdownFolderUnresolvable.symbolName == "exclamationmark.triangle.fill")
        #expect(
            SourceIssue.from(AnonymousError(), sourceID: "markdown").symbolName
                == "exclamationmark.circle.fill"
        )
    }
}
