//
//  AgentConfigMenu.swift
//  aizen
//
//  Created by Agent on 11.01.26.
//

import ACP
import SwiftUI

struct AgentConfigMenu: View {
    @ObservedObject var session: AgentSession
    var showsBackground: Bool = true
    
    var body: some View {
        if !session.availableConfigOptions.isEmpty {
            HStack(spacing: 8) {
                ForEach(session.availableConfigOptions, id: \.id.value) { option in
                    configMenu(for: option)
                }
            }
        }
    }
    
    private func configMenu(for option: SessionConfigOption) -> some View {
        Menu {
            switch option.kind {
            case .select(let select):
                switch select.options {
                case .ungrouped(let options):
                    ForEach(options, id: \.value.value) { item in
                        button(for: item, configId: option.id.value, currentId: select.currentValue.value)
                    }
                    
                case .grouped(let groups):
                    ForEach(groups, id: \.group.value) { group in
                        Section(header: Text(group.name)) {
                            ForEach(group.options, id: \.value.value) { item in
                                button(for: item, configId: option.id.value, currentId: select.currentValue.value)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: option))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(currentOptionName(for: option))
                    .font(.system(size: showsBackground ? 12 : 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: showsBackground ? 8 : 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, showsBackground ? 10 : 0)
            .padding(.vertical, showsBackground ? 5 : 0)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(session.isStreaming)
        .opacity(session.isStreaming ? 0.5 : 1.0)
    }
    
    private func button(for item: SessionConfigSelectOption, configId: String, currentId: String) -> some View {
        Button {
            Task {
                try? await session.setConfigOption(configId: configId, value: item.value.value)
            }
        } label: {
            HStack {
                Text(item.name)
                Spacer()
                if item.value.value == currentId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
    
    private func currentOptionName(for option: SessionConfigOption) -> String {
        guard case .select(let select) = option.kind else { return option.name }
        let currentId = select.currentValue.value
        
        switch select.options {
        case .ungrouped(let options):
            return options.first { $0.value.value == currentId }?.name ?? currentId
        case .grouped(let groups):
            for group in groups {
                if let opt = group.options.first(where: { $0.value.value == currentId }) {
                    return opt.name
                }
            }
        }
        return currentId
    }

    private func iconName(for option: SessionConfigOption) -> String {
        let name = option.name.lowercased()
        if name.contains("permission") || name.contains("access") || name.contains("sandbox") {
            return "lock.shield"
        }
        if name.contains("model") {
            return "cpu"
        }
        if name.contains("effort") || name.contains("reason") || name.contains("thinking") {
            return "gauge.with.dots.needle.33percent"
        }
        return "slider.horizontal.3"
    }
}
