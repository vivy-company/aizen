//
//  ToastStore.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 03.11.25.
//

import SwiftUI
import Combine

enum ToastType {
    case success
    case error
    case info
    case loading

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .loading: return "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .loading: return .gray
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    var isLoading: Bool = false

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

final class ToastStore: ObservableObject {
    static let shared = ToastStore()

    @Published var currentToast: ToastMessage?

    private init() {}

    @MainActor
    func show(_ message: String, type: ToastType, duration: TimeInterval = 3.0) {
        currentToast = ToastMessage(type: type, message: message, isLoading: type == .loading)
        let toastId = currentToast?.id

        if type != .loading {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                if self?.currentToast?.id == toastId {
                    self?.dismiss()
                }
            }
        }
    }

    @MainActor
    func showLoading(_ message: String, timeout: TimeInterval = 30.0) {
        show(message, type: .loading)
        let toastId = currentToast?.id

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            if self?.currentToast?.id == toastId {
                self?.dismiss()
            }
        }
    }

    @MainActor
    func dismiss() {
        currentToast = nil
    }
}
