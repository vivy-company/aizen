//
//  LicenseStateStore+Validation.swift
//  aizen
//

import AppKit
import Foundation
import os

extension LicenseStateStore {
    func start() {
        scheduleValidationTimer()
        Task {
            await validateIfNeeded()
        }
    }

    func validateIfNeeded() async {
        guard let cache = store.loadCache() else {
            return
        }

        let now = Date()
        if now.timeIntervalSince(cache.lastValidatedAt) < validationInterval {
            applyCache(cache)
            return
        }

        await validateNow()
    }

    func handleValidationFailure(_ error: Error) {
        logger.error("License validation failed: \(error.localizedDescription)")

        if deviceAuthService.isInvalidDeviceAuth(error),
           let token = currentToken {
            Task {
                _ = await deviceAuthService.refreshDeviceAuth(
                    token: token,
                    deviceName: Host.current().localizedName ?? "Mac"
                )
            }
        } else if let cache = store.loadCache(),
                  cache.isValid,
                  let daysLeft = offlineGraceDaysLeft(from: cache.lastValidatedAt) {
            applyCache(cache)
            status = .offlineGrace(daysLeft: daysLeft)
            lastMessage = "Offline grace period"
            return
        }

        status = .error(message: error.localizedDescription)
    }

    func scheduleValidationTimer() {
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.validationInterval ?? 86400))
                guard !Task.isCancelled else { break }
                await self?.validateNow()
            }
        }
    }
}
