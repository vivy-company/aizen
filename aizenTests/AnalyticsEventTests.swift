import Testing
@testable import Aizen

struct AnalyticsEventTests {
    @Test func repositoryCloneProviderIsCoarseAndDoesNotStoreURL() {
        let cloneURL = "git@github.com:private-org/private-repo.git"
        let event = AnalyticsEvent.repositoryAdded(
            source: .clone,
            provider: .provider(forCloneURL: cloneURL),
            repositoryCount: 12
        )

        #expect(event.name == "repository_added")
        #expect(event.url == "/repository")
        #expect(event.properties["provider"] == .string("github"))
        #expect(event.properties["repository_count_bucket"] == .string("11_plus"))
        #expect(!event.properties.values.contains(.string(cloneURL)))
    }

    @Test func appEventsCarryNoEventSpecificProperties() {
        #expect(AnalyticsEvent.appOpened.properties.isEmpty)
        #expect(AnalyticsEvent.appActiveDaily.properties.isEmpty)
        #expect(AnalyticsEvent.settingsOpened.properties.isEmpty)
    }

    @Test func worktreeCreatedUsesBucketedCounts() {
        let event = AnalyticsEvent.worktreeCreated(source: .newBranch, worktreeCount: 4)

        #expect(event.name == "worktree_created")
        #expect(event.url == "/worktree")
        #expect(event.properties["source"] == .string("new_branch"))
        #expect(event.properties["worktree_count_bucket"] == .string("4_10"))
    }
}
