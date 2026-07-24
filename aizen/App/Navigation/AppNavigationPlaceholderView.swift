//
//  AppNavigationPlaceholderView.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import SwiftUI

func placeholderView(
    titleKey: LocalizedStringKey,
    systemImage: String,
    descriptionKey: LocalizedStringKey
) -> AnyView {
    if #available(macOS 14.0, *) {
        AnyView(ContentUnavailableView(
            titleKey,
            systemImage: systemImage,
            description: Text(descriptionKey)
        ))
    } else {
        AnyView(VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(descriptionKey)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding())
    }
}
