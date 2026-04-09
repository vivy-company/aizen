//
//  FileBrowserStore+DirectoryListing.swift
//  aizen
//
//  Directory listing and path helpers
//

import Foundation

extension FileBrowserStore {
    func listDirectory(path: String) throws -> [FileItem] {
        if directoryCacheShowHiddenFiles != showHiddenFiles {
            directoryItemsCache.removeAll()
            directoryCacheShowHiddenFiles = showHiddenFiles
        } else if directoryCacheShowHiddenFiles == nil {
            directoryCacheShowHiddenFiles = showHiddenFiles
        }

        if let cachedItems = directoryItemsCache[path] {
            return cachedItems
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: path)

        let items = contents.compactMap { name -> FileItem? in
            let isHidden = name.hasPrefix(".")

            if isHidden && !showHiddenFiles {
                return nil
            }

            let filePath = (path as NSString).appendingPathComponent(name)
            let fileURL = URL(fileURLWithPath: filePath)
            let isDir = isBrowsableDirectory(fileURL)
            let relativePath = getRelativePath(for: filePath)
            let isIgnored = gitIgnoredPaths.contains(filePath) || gitIgnoredPaths.contains(relativePath)
            let status = gitFileStatus[relativePath]

            return FileItem(
                name: name,
                path: filePath,
                isDirectory: isDir,
                isHidden: isHidden,
                isGitIgnored: isIgnored,
                gitStatus: status
            )
        }.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }

        directoryItemsCache[path] = items
        return items
    }

    func isBrowsableDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }

        if values.isDirectory == true {
            return true
        }

        if values.isSymbolicLink == true {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue
            }
        }

        return false
    }

    func getRelativePath(for absolutePath: String) -> String {
        guard let basePath = worktree.path else { return absolutePath }
        if absolutePath.hasPrefix(basePath) {
            var relative = String(absolutePath.dropFirst(basePath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return absolutePath
    }
}
