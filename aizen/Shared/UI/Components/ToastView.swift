//
//  ToastView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 03.11.25.
//

import SwiftUI

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 12) {
            if toast.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Image(systemName: toast.type.icon)
                    .foregroundStyle(toast.type.color)
            }

            Text(toast.message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

struct ToastContainerView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ToastModifierView(content: content)
    }
}

private struct ToastModifierView<Content: View>: View {
    let content: Content
    @StateObject private var toastManager = ToastManager.shared

    var body: some View {
        ZStack {
            content

            if let toast = toastManager.currentToast {
                VStack {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 20)
                    Spacer()
                }
                .animation(.spring(), value: toastManager.currentToast)
            }
        }
    }
}

extension View {
    func toast() -> some View {
        ToastContainerView {
            self
        }
    }
}
