import CoreData

extension SessionsListStore {
    func buildFetchRequest() -> NSFetchRequest<ChatSession> {
        Self.buildFetchRequest(
            filter: selectedFilter,
            searchText: searchText,
            worktreeId: selectedWorktreeId,
            fetchLimit: fetchLimit,
            agentName: selectedAgentName
        )
    }

    nonisolated static func buildFetchRequest(
        filter: SessionFilter,
        searchText: String,
        worktreeId: UUID?,
        fetchLimit: Int,
        agentName: String?
    ) -> NSFetchRequest<ChatSession> {
        let request = NSFetchRequest<ChatSession>(entityName: "ChatSession")

        var predicates: [NSPredicate] = []
        predicates.append(NSPredicate(format: "SUBQUERY(messages, $m, $m.role == 'user').@count > 0"))

        switch filter {
        case .all:
            break
        case .active:
            predicates.append(NSPredicate(format: "archived == NO"))
        case .archived:
            predicates.append(NSPredicate(format: "archived == YES"))
        }

        if let worktreeId {
            predicates.append(NSPredicate(format: "worktree.id == %@", worktreeId as CVarArg))
        }

        if !searchText.isEmpty {
            predicates.append(
                NSPredicate(
                    format: "title CONTAINS[cd] %@ OR agentName CONTAINS[cd] %@",
                    searchText,
                    searchText
                )
            )
        }

        if let agentName {
            if agentName == Self.unknownAgentLabel {
                predicates.append(NSPredicate(format: "agentName == nil OR agentName == ''"))
            } else {
                predicates.append(NSPredicate(format: "agentName == %@", agentName))
            }
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "lastMessageAt", ascending: false)
        ]
        request.relationshipKeyPathsForPrefetching = ["worktree"]
        request.fetchBatchSize = 10
        request.fetchLimit = fetchLimit

        return request
    }

    nonisolated static func buildAgentNamesRequest(
        filter: SessionFilter,
        worktreeId: UUID?
    ) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ChatSession")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["agentName"]
        request.returnsDistinctResults = true

        var predicates: [NSPredicate] = []
        predicates.append(NSPredicate(format: "SUBQUERY(messages, $m, $m.role == 'user').@count > 0"))

        switch filter {
        case .all:
            break
        case .active:
            predicates.append(NSPredicate(format: "archived == NO"))
        case .archived:
            predicates.append(NSPredicate(format: "archived == YES"))
        }

        if let worktreeId {
            predicates.append(NSPredicate(format: "worktree.id == %@", worktreeId as CVarArg))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "agentName", ascending: true)
        ]

        return request
    }
}
