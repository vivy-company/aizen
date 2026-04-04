//
//  GitIndexWatcher+DispatchSources.swift
//  aizen
//
//  Dispatch source setup for git index watcher events
//

import Darwin
import Foundation

extension GitIndexWatcher {
    nonisolated func setupDispatchSources() -> Bool {
        let headPath = (gitIndexPath as NSString).deletingLastPathComponent
        let headFilePath = (headPath as NSString).appendingPathComponent("HEAD")

        indexFD = open(gitIndexPath, O_EVTONLY)
        headFD = open(headFilePath, O_EVTONLY)

        var createdSource = false

        if indexFD != -1 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: indexFD,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebounceCallback()
            }
            source.setCancelHandler { [weak self] in
                if let fd = self?.indexFD, fd != -1 {
                    close(fd)
                    self?.indexFD = -1
                }
            }
            source.resume()
            indexSource = source
            createdSource = true
        }

        if headFD != -1 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: headFD,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebounceCallback()
            }
            source.setCancelHandler { [weak self] in
                if let fd = self?.headFD, fd != -1 {
                    close(fd)
                    self?.headFD = -1
                }
            }
            source.resume()
            headSource = source
            createdSource = true
        }

        if !createdSource {
            if indexFD != -1 {
                close(indexFD)
                indexFD = -1
            }
            if headFD != -1 {
                close(headFD)
                headFD = -1
            }
        }

        return createdSource
    }
}
