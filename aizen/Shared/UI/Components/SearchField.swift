//
//  SearchField.swift
//  aizen
//
//  Reusable search field with clear button and optional trailing content
//

import SwiftUI

struct SearchField<Trailing: View>: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var spacing: CGFloat = 8
    var iconSize: CGFloat = 14
    var iconWeight: Font.Weight? = nil
    var iconColor: Color = .secondary
    var textFont: Font = .system(size: 14)
    var clearButtonSize: CGFloat? = 12
    var clearButtonWeight: Font.Weight? = nil
    var clearButtonOpacity: Double = 1.0
    var showsClearButton: Bool = true
    var onSubmit: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var isFocused: FocusState<Bool>.Binding? = nil
    var disableAutocorrection: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: spacing) {
            icon
            textField

            if showsClearButton, !text.isEmpty {
                ClearTextButton(
                    text: $text,
                    size: clearButtonSize,
                    weight: clearButtonWeight,
                    opacity: clearButtonOpacity,
                    onClear: onClear
                )
            }

            trailing()
        }
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: "magnifyingglass")
        if let weight = iconWeight {
            image
                .font(.system(size: iconSize, weight: weight))
                .foregroundStyle(iconColor)
        } else {
            image
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
        }
    }

    @ViewBuilder
    private var textField: some View {
        if let isFocused = isFocused {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(textFont)
                .focused(isFocused)
                .disableAutocorrection(disableAutocorrection)
                .onSubmit { onSubmit?() }
                .onExitCommand { onEscape?() }
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(textFont)
                .disableAutocorrection(disableAutocorrection)
                .onSubmit { onSubmit?() }
                .onExitCommand { onEscape?() }
        }
    }
}
