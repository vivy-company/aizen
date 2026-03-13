# Aizen

[English](README.md) | [简体中文](README.zh-CN.md)

[![macOS](https://img.shields.io/badge/macOS-13.5+-black?style=flat-square&logo=apple)](https://aizen.win)
[![Swift](https://img.shields.io/badge/Swift-5.0+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-GPL%203.0-blue?style=flat-square)](LICENSE)
[![Discord](https://img.shields.io/badge/-Discord-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/zemMZtrkSb)
[![Twitter](https://img.shields.io/badge/-Twitter-1DA1F2?style=flat-square&logo=x&logoColor=white)](https://x.com/aizenwin)
[![Sponsor](https://img.shields.io/badge/-Sponsor-ff69b4?style=flat-square&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/vivy-company)

> **早期体验** — Aizen 正在积极开发中，几乎每天都有更新。预计会有频繁的破坏性更改和新功能。

Aizen 是一个面向并行开发的 macOS 工作区。

让你的项目、环境和日常工作井然有序。

为每个项目或分支提供独立环境，拥有各自的终端、文件、浏览器、代理和状态。

![Aizen Demo](https://r2.aizen.win/demo.png)

## Aizen 是什么？

Aizen 是一个以代理协作为优先的 macOS 开发工作区。它让你并行处理多个项目和分支，而不用把 worktree、文件夹或副本管理变成手工流程。每个环境都保留自己的终端、文件、浏览器、代理会话、Git 上下文和评审状态。

## 当前亮点

### 并行环境
- **工作区** — 将活跃项目组织到带颜色标记的分组中
- **项目级环境** — 为每个项目或分支提供独立的终端、文件、浏览器和聊天
- **底层实现灵活** — Aizen 可在底层使用 Git worktree、文件夹或副本

### 终端与 CLI
- **GPU 加速** — 基于 [libghostty](https://github.com/ghostty-org/ghostty)
- **分屏与标签** — 支持水平/垂直分屏、预设和主题
- **会话持久化** — 可选 tmux 持久化，重启后恢复终端状态
- **CLI 配套** — 通过 `aizen` 命令打开项目、管理工作区、连接持久终端

### Agentic-First 工作流
- **ACP 注册表优先** — 可直接添加注册表代理，也可配置自定义命令或二进制
- **环境级代理会话** — 将聊天、工具调用和上下文绑定到当前项目环境
- **MCP 市场** — 在应用内浏览并添加 MCP 服务器
- **丰富输入** — 文件附件、工具调用，以及带波形可视化的本地语音输入

### Git、评审与交付
- **Git 操作** — 在界面中完成暂存、提交、推送、拉取、合并和分支管理
- **Diff 与评审** — 带语法高亮的差异查看、评审评论和 PR/MR 详情
- **工作流可见性** — 在 worktree 侧边栏查看 GitHub Actions 与 GitLab CI
- **Apple 项目支持** — 为 `.xcodeproj` 和 `.xcworkspace` 提供 Xcode 构建集成

### 文件与浏览器
- **文件浏览器** — 树形视图、搜索、语法高亮、内联 diff 和多标签
- **内置浏览器** — 每个 worktree 独立保存文档、预览、认证流程和本地应用标签页

## 系统要求

- macOS 13.5+
- 仅支持 Apple Silicon Mac
- 从 1.0.71 起，Intel Mac 已被有意停止支持，以获得更好的用户体验

## 安装

从 [aizen.win](https://aizen.win) 下载

已使用 Apple 开发者证书签名并完成公证。

## 从源码构建

- Xcode 16.0+
- Swift 5.0+
- Git LFS
- Zig（用于构建 libghostty）：`brew install zig`

```bash
git lfs install
git clone https://github.com/vivy-company/aizen.git
cd aizen

# 构建 libghostty（默认固定到 Vendor/libghostty/VERSION 中的版本，Apple Silicon / arm64）
./scripts/build-libghostty.sh

# 在 Xcode 中打开并构建
open aizen.xcodeproj
```

在指定 commit 重新构建 libghostty：
```bash
./scripts/build-libghostty.sh <commit-sha>
```

## 代理设置

Aizen 现在默认采用 ACP 注册表代理方案。

- 默认预置 Claude Code、Codex 和 OpenCode
- 在 **设置 > 代理** 中添加更多代理
- 也可以手动配置自定义命令或可执行文件
- 每个代理都可以通过内置市场添加 MCP 服务器

## CLI

在 **设置 > 通用** 中安装内置 CLI，然后可以使用：

```bash
aizen open .
aizen workspace list
aizen terminal . --attach
aizen attach
```

CLI 可以添加或打开项目、查看工作区、创建持久终端，并连接到应用中创建的 tmux 会话。

## 配置

### 终端

设置 > 终端：
- 字体和大小
- 配色主题和预设
- 语音输入按钮
- tmux 会话持久化

### 通用

设置 > 通用：
- 默认外部编辑器（VS Code、Cursor、Sublime Text）
- CLI 安装与状态
- Apple 项目的 Xcode 构建按钮开关

## 快捷键

| 快捷键 | 操作 |
|--------|------|
| `⌘ D` | 向右分屏终端 |
| `⌘ ⇧ D` | 向下分屏终端 |
| `⌘ W` | 关闭面板 |
| `⌘ T` | 新建标签 |
| `⇧ ⇥` | 切换聊天模式 |
| `ESC` | 中断代理 |

## 依赖项

- [libghostty](https://github.com/ghostty-org/ghostty) — 终端模拟器
- [libgit2](https://libgit2.org/) — 原生 Git 操作
- [VVDevKit](https://github.com/vivy-company/VVDevKit) — 编辑器/Markdown/时间线/Diff 与 Tree-sitter 高亮
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 自动更新

## 架构

```
aizen/
├── App/                    # 入口
├── Models/                 # 数据模型、ACP、Git、MCP、Tab、Terminal
├── Services/
│   ├── Agent/              # ACP 客户端、注册表、安装器、会话管理
│   ├── Git/                # Worktree、分支、暂存、差异、评审、托管服务
│   ├── Audio/              # 语音录制、转写
│   ├── MCP/                # MCP 服务器管理
│   ├── Workflow/           # GitHub Actions / GitLab CI 集成
│   └── Xcode/              # Xcode 构建与设备集成
├── Views/
│   ├── Chat/               # 会话、输入、Markdown、工具调用
│   ├── Worktree/           # 列表、详情、Git、工作流、评审
│   ├── Terminal/           # 标签、分屏布局、面板
│   ├── Files/              # 树形视图、内容标签
│   ├── Browser/            # 标签、控件
│   ├── Search/             # 搜索界面
│   ├── CommandPalette/     # 命令面板
│   └── Settings/           # 设置面板与安装器
├── GhosttyTerminal/        # libghostty 封装
├── Managers/               # 共享状态管理器
└── Utilities/              # 工具函数
```

**设计模式：**
- MVVM 配合可观察模型
- 使用 Actor 处理并发敏感逻辑
- Core Data 持久化
- SwiftUI + async/await + `AsyncStream`

## 许可证

GNU General Public License v3.0

版权所有 © 2026 Vivy Technologies Co., Limited
