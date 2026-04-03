//
//  PullRequestListPane+Header.swift
//  aizen
//
//  Header and filter controls for the pull request list pane.
//

import SwiftUI

extension PullRequestListPane {
    var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(viewModel.prTerminology + "s")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !viewModel.pullRequests.isEmpty {
                    TagBadge(
                        text: "\(viewModel.pullRequests.count)\(viewModel.hasMore ? "+" : "")",
                        color: .secondary,
                        cornerRadius: 6
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Menu {
                ForEach(PRFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.changeFilter(to: filter)
                    } label: {
                        if filter == viewModel.filter {
                            Label(filter.displayName, systemImage: "checkmark")
                        } else {
                            Text(filter.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(viewModel.filter.displayName)
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .frame(minWidth: 110)
                .background(chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: Layout.chipCornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Layout.chipCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(viewModel.isLoadingList)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(chipBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoadingList)
        }
        .padding(.horizontal, Layout.headerHorizontalPadding)
        .padding(.vertical, Layout.headerVerticalPadding)
    }

    var chipBackground: some ShapeStyle {
        Color.white.opacity(0.08)
    }
}
