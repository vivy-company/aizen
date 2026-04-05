import AppKit
import SwiftUI
import VVCode

extension GitPanelWindowContentWithToolbar {
    var body: some View {
        GitPanelWindowContent(
            context: context,
            repositoryManager: repositoryManager,
            selectedTab: $selectedTab,
            diffRenderStyle: diffRenderStyleBinding,
            onClose: onClose
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $selectedTab) {
                    Label(GitPanelTab.git.displayName, systemImage: GitPanelTab.git.icon).tag(GitPanelTab.git)
                    Label(GitPanelTab.comments.displayName, systemImage: GitPanelTab.comments.icon).tag(GitPanelTab.comments)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 24)
            }

            ToolbarItem(placement: .navigation) {
                Picker("", selection: $selectedTab) {
                    Label(GitPanelTab.history.displayName, systemImage: GitPanelTab.history.icon).tag(GitPanelTab.history)
                    Label(GitPanelTab.prs.displayName, systemImage: GitPanelTab.prs.icon).tag(GitPanelTab.prs)
                    Label(GitPanelTab.workflows.displayName, systemImage: GitPanelTab.workflows.icon).tag(GitPanelTab.workflows)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 12)
            }

            ToolbarItem(placement: .navigation) {
                if gitFeaturesAvailable {
                    branchSelector
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if gitFeaturesAvailable {
                    prActionButton
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Spacer().frame(width: 16)
            }

            ToolbarItem(placement: .primaryAction) {
                if gitFeaturesAvailable {
                    gitActionsToolbar
                }
            }
        }
        .task(id: selectedTab) {
            guard selectedTab == .prs else { return }
            loadHostingInfoIfNeeded()
        }
        .task(id: gitStatus.currentBranch) {
            await refreshPRStatus()
        }
        .alert("CLI Not Installed", isPresented: $showCLIInstallAlert) {
            if let info = hostingInfo {
                Button("Install Instructions") {
                    if let url = URL(string: "https://\(info.provider == .github ? "cli.github.com" : info.provider == .gitlab ? "gitlab.com/gitlab-org/cli" : "")") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Open in Browser") {
                    let branch = gitStatus.currentBranch
                    guard !branch.isEmpty else { return }
                    Task {
                        await gitHostingService.openInBrowser(
                            info: info,
                            action: .createPR(sourceBranch: branch, targetBranch: nil)
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let info = hostingInfo {
                Text("The \(info.provider.displayName) CLI (\(info.provider.cliName ?? "")) is not installed or not authenticated.\n\nInstall with: \(info.provider.installInstructions)")
            }
        }
        .sheet(isPresented: $showingBranchPicker) {
            BranchSelectorView(
                repository: worktree.repository!,
                repositoryManager: repositoryManager,
                selectedBranch: .constant(nil),
                onSelectBranch: { branch in
                    gitOperations.switchBranch(branch.name)
                },
                allowCreation: true,
                onCreateBranch: { branchName in
                    gitOperations.createBranch(branchName)
                }
            )
        }
    }
}
