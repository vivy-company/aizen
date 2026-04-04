//
//  LicenseStateStore+Cache.swift
//  aizen
//

import Foundation

extension LicenseStateStore {
    func loadFromStore() {
        licenseToken = store.loadToken() ?? ""
        if let cache = store.loadCache() {
            applyCache(cache)
        } else if licenseToken.isEmpty {
            status = .unlicensed
        }
    }

    func updateCache(type: String?, status: String?, expiresAt: Date?, isValid: Bool) {
        let cache = LicenseCache(
            type: type,
            status: status,
            expiresAt: expiresAt,
            isValid: isValid,
            lastValidatedAt: Date()
        )
        store.saveCache(cache)
        applyCache(cache)
    }

    func applyCache(_ cache: LicenseCache) {
        licenseType = cache.type
        licenseStatus = cache.status
        expiresAt = cache.expiresAt
        lastValidatedAt = cache.lastValidatedAt

        if cache.isValid {
            if let expiresAt, expiresAt < Date() {
                status = .expired
            } else {
                status = .active
            }
        } else if licenseToken.isEmpty {
            status = .unlicensed
        } else {
            status = .expired
        }
    }

    func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateParser.shared.parse(string)
    }
}
