//
//  WorktreeSceneRegistry.swift
//  aizen
//
//  Bounded LRU cache for warm worktree scenes.
//

import Combine
import CoreData
import Foundation

@MainActor
final class WorktreeSceneRegistry: ObservableObject {
    @Published private(set) var activeSceneId: NSManagedObjectID?
    @Published private(set) var sceneOrder: [NSManagedObjectID] = []

    private let cacheLimit: Int
    private let viewContext: NSManagedObjectContext
    private var scenesById: [NSManagedObjectID: WorktreeSceneStore] = [:]

    init(viewContext: NSManagedObjectContext, cacheLimit: Int = 4) {
        self.viewContext = viewContext
        self.cacheLimit = max(cacheLimit, 1)
    }

    var mountedScenes: [WorktreeSceneStore] {
        sceneOrder.compactMap { scenesById[$0] }
    }

    var activeScene: WorktreeSceneStore? {
        guard let activeSceneId else { return nil }
        return scenesById[activeSceneId]
    }

    @discardableResult
    func activate(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        tabStateManager: WorktreeTabStateStore
    ) -> WorktreeSceneStore {
        let scene = scene(
            for: worktree,
            repositoryManager: repositoryManager,
            tabStateManager: tabStateManager
        )
        activeSceneId = scene.id
        touchScene(scene.id)
        evictIfNeeded()
        return scene
    }

    func clearActiveScene() {
        activeSceneId = nil
    }

    func isActive(_ scene: WorktreeSceneStore) -> Bool {
        activeSceneId == scene.id
    }

    func scene(for worktree: Worktree) -> WorktreeSceneStore? {
        scenesById[worktree.objectID]
    }

    private func scene(
        for worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        tabStateManager: WorktreeTabStateStore
    ) -> WorktreeSceneStore {
        if let existingScene = scenesById[worktree.objectID] {
            return existingScene
        }

        let newScene = WorktreeSceneStore(
            worktree: worktree,
            repositoryManager: repositoryManager,
            tabStateManager: tabStateManager,
            viewContext: viewContext
        )
        scenesById[worktree.objectID] = newScene
        sceneOrder.append(worktree.objectID)
        return newScene
    }

    private func touchScene(_ sceneId: NSManagedObjectID) {
        sceneOrder.removeAll { $0 == sceneId }
        sceneOrder.append(sceneId)
    }

    private func evictIfNeeded() {
        while sceneOrder.count > cacheLimit {
            let evictedId = sceneOrder.removeFirst()
            guard evictedId != activeSceneId else {
                sceneOrder.append(evictedId)
                break
            }
            scenesById[evictedId]?.prepareForEviction()
            scenesById.removeValue(forKey: evictedId)
        }
    }
}
