//
//  Worktree+CheckoutType.swift
//  aizen
//

import Foundation

enum WorktreeCheckoutType: String, CaseIterable {
    case primary
    case linked
    case independent
}

extension Worktree {
    var checkoutTypeValue: WorktreeCheckoutType {
        get {
            if let raw = checkoutType,
               let parsed = WorktreeCheckoutType(rawValue: raw) {
                return parsed
            }
            if isPrimary {
                return .primary
            }
            return .linked
        }
        set {
            checkoutType = newValue.rawValue
        }
    }

    var isLinkedEnvironment: Bool {
        checkoutTypeValue == .linked
    }

    var isIndependentEnvironment: Bool {
        checkoutTypeValue == .independent
    }
}
