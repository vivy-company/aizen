//
//  QuestionInputView.swift
//  aizen
//
//  Interactive question UI for agent clarifying questions
//

import SwiftUI

struct QuestionInputView: View {
    let questionContent: QuestionContent
    let onSubmit: ([String]) -> Void
    
    @State private var selectedOptions: Set<String> = []
    @State private var customAnswer: String = ""
    @State private var showCustomInput: Bool = false
    @State private var isSubmitted: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var currentQuestion: Question? {
        questionContent.questions.first
    }
    
    private var canSubmit: Bool {
        !selectedOptions.isEmpty || !customAnswer.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var accentColor: Color {
        ANSIColorProvider.shared.color(for: 4)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.16) : Color.white
    }
    
    var body: some View {
        if let question = currentQuestion {
            VStack(alignment: .leading, spacing: 12) {
                headerView(question: question)
                
                if !isSubmitted {
                    optionsView(question: question)
                    
                    if question.allowsCustom {
                        customInputSection(question: question)
                    }
                    
                    submitButton
                } else {
                    submittedView
                }
            }
            .padding(16)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                    .fill(accentColor)
                    .frame(width: 4)
            }
        }
    }
    
    @ViewBuilder
    private func headerView(question: Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                
                Text(question.header)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if question.allowsMultiple {
                    Text("Select multiple")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            Text(question.question)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    private func optionsView(question: Question) -> some View {
        VStack(spacing: 8) {
            ForEach(question.options) { option in
                QuestionOptionCard(
                    option: option,
                    isSelected: selectedOptions.contains(option.label),
                    accentColor: accentColor,
                    cardBackground: cardBackground
                ) {
                    handleOptionTap(option: option, allowsMultiple: question.allowsMultiple)
                }
            }
        }
    }
    
    @ViewBuilder
    private func customInputSection(question: Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCustomInput.toggle()
                    if showCustomInput {
                        selectedOptions.removeAll()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showCustomInput ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(showCustomInput ? accentColor : .secondary)
                    
                    Text("Type your own answer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showCustomInput ? .primary : .secondary)
                    
                    Spacer()
                    
                    Image(systemName: showCustomInput ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(showCustomInput ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            
            if showCustomInput {
                TextField("Enter your answer...", text: $customAnswer, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(12)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .lineLimit(1...5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var submitButton: some View {
        HStack {
            Spacer()
            
            Button {
                submitAnswer()
            } label: {
                HStack(spacing: 6) {
                    Text("Submit")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(canSubmit ? accentColor : Color.secondary.opacity(0.5))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }
    
    private var submittedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
            
            Text("Answer submitted")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if !selectedOptions.isEmpty {
                Text(selectedOptions.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if !customAnswer.isEmpty {
                Text(customAnswer)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func handleOptionTap(option: QuestionOption, allowsMultiple: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            showCustomInput = false
            customAnswer = ""
            
            if allowsMultiple {
                if selectedOptions.contains(option.label) {
                    selectedOptions.remove(option.label)
                } else {
                    selectedOptions.insert(option.label)
                }
            } else {
                selectedOptions = [option.label]
            }
        }
    }
    
    private func submitAnswer() {
        let answers: [String]
        if !customAnswer.trimmingCharacters(in: .whitespaces).isEmpty {
            answers = [customAnswer.trimmingCharacters(in: .whitespaces)]
        } else {
            answers = Array(selectedOptions)
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isSubmitted = true
        }
        
        onSubmit(answers)
    }
}

struct QuestionOptionCard: View {
    let option: QuestionOption
    let isSelected: Bool
    let accentColor: Color
    let cardBackground: Color
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accentColor : (isHovering ? accentColor.opacity(0.3) : Color.clear), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: .black.opacity(isSelected ? 0.1 : 0.03),
                radius: isSelected ? 4 : 2,
                x: 0,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

#Preview("Question Input") {
    VStack(spacing: 20) {
        QuestionInputView(
            questionContent: QuestionContent(questions: [
                Question(
                    question: "What kind of code snippets do you want to see?",
                    header: "Code Snippets Type",
                    options: [
                        QuestionOption(label: "Browse project files", description: "Open and view files from this Aizen project"),
                        QuestionOption(label: "Search codebase", description: "Search for specific patterns or functions"),
                        QuestionOption(label: "Show recent changes", description: "View git diff and recent modifications")
                    ],
                    multiple: false,
                    custom: true
                )
            ]),
            onSubmit: { answers in
                print("Selected: \(answers)")
            }
        )
        
        QuestionInputView(
            questionContent: QuestionContent(questions: [
                Question(
                    question: "Select all the features you want to implement:",
                    header: "Feature Selection",
                    options: [
                        QuestionOption(label: "Authentication", description: "User login and signup"),
                        QuestionOption(label: "Database", description: "Data persistence layer"),
                        QuestionOption(label: "API", description: "REST or GraphQL endpoints")
                    ],
                    multiple: true,
                    custom: false
                )
            ]),
            onSubmit: { answers in
                print("Selected: \(answers)")
            }
        )
    }
    .padding()
    .frame(width: 500)
    .background(Color(nsColor: .windowBackgroundColor))
}
