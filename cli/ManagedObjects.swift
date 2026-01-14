import Foundation
import CoreData

@objc(Workspace)
public class Workspace: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var order: Int16
    @NSManaged public var colorHex: String?
    @NSManaged public var lastSelectedRepositoryId: UUID?
    @NSManaged public var repositories: NSSet?
}

extension Workspace {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Workspace> {
        return NSFetchRequest<Workspace>(entityName: "Workspace")
    }
}

@objc(Repository)
public class Repository: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var path: String?
    @NSManaged public var lastUpdated: Date?
    @NSManaged public var status: String?
    @NSManaged public var note: String?
    @NSManaged public var postCreateActionsData: Data?
    @NSManaged public var workspace: Workspace?
    @NSManaged public var worktrees: NSSet?
}

extension Repository {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Repository> {
        return NSFetchRequest<Repository>(entityName: "Repository")
    }
}

@objc(Worktree)
public class Worktree: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var path: String?
    @NSManaged public var branch: String?
    @NSManaged public var isPrimary: Bool
    @NSManaged public var lastAccessed: Date?
    @NSManaged public var selectedTab: String?
    @NSManaged public var status: String?
    @NSManaged public var note: String?
    @NSManaged public var repository: Repository?
    @NSManaged public var terminalSessions: NSSet?
}

extension Worktree {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Worktree> {
        return NSFetchRequest<Worktree>(entityName: "Worktree")
    }
}

@objc(TerminalSession)
public class TerminalSession: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var splitLayout: String?
    @NSManaged public var focusedPaneId: String?
    @NSManaged public var initialCommand: String?
    @NSManaged public var worktree: Worktree?
}

extension TerminalSession {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TerminalSession> {
        return NSFetchRequest<TerminalSession>(entityName: "TerminalSession")
    }
}
