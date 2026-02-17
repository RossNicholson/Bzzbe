@testable import BzzbeApp
import Foundation
import Testing

@Test("MemorySearchIndex returns scope-filtered results")
func memorySearchIndexReturnsScopeFilteredResults() {
    let now = Date(timeIntervalSince1970: 10_000)
    let notes = [
        MemoryNote(
            id: UUID(),
            createdAt: now,
            scope: .private,
            title: "Private release checklist",
            content: "Remember QA signoff and regression pass."
        ),
        MemoryNote(
            id: UUID(),
            createdAt: now.addingTimeInterval(-60),
            scope: .shared,
            title: "Shared support style",
            content: "Use concise bullet replies for customer updates."
        )
    ]

    let privateResults = MemorySearchIndex.search(
        query: "release qa checklist",
        notes: notes,
        scope: .private,
        limit: 5
    )
    let sharedResults = MemorySearchIndex.search(
        query: "support customer bullet",
        notes: notes,
        scope: .shared,
        limit: 5
    )

    #expect(privateResults.count == 1)
    #expect(privateResults.first?.scope == .private)
    #expect(sharedResults.count == 1)
    #expect(sharedResults.first?.scope == .shared)
}
