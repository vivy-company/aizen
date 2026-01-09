# Aizen

[English](README.md) | [简体中文](README.zh-CN.md)

[![macOS](https://img.shields.io/badge/macOS-13.5+-black?style=flat-square&logo=apple)](https://aizen.win)
[![Swift](https://img.shields.io/badge/Swift-5.0+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-GPL%203.0-blue?style=flat-square)](LICENSE)
[![Discord](https://img.shields.io/badge/-Discord-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/zemMZtrkSb)
[![Twitter](https://img.shields.io/badge/-Twitter-1DA1F2?style=flat-square&logo=x&logoColor=white)](https://x.com/aizenwin)
[![Sponsor](https://img.shields.io/badge/-Sponsor-ff69b4?style=flat-square&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/vivy-company)

> **早期体验** — Aizen 正在积极开发中，几乎每天都有更新。预计会有频繁的破坏性更改和新功能。

让你的仓库井然有序。切换 worktree，而非窗口。

![Aizen Demo](https://r2.aizen.win/demo.png)

## Aizen 是什么？

Aizen 是一个面向需要并行处理多个分支的开发者的 macOS 工作区。每个 worktree 都有独立的终端、文件浏览器、网页浏览器和代理会话 — 让你切换 worktree，而非窗口。

## 功能特性

### 核心
- **工作区** — 将仓库组织到带颜色标记的分组中
- **Worktree** — 通过可视化界面创建和管理 Git worktree
- **独立会话** — 每个 worktree 拥有独立的终端、文件、浏览器和聊天

### 终端
- **GPU 加速** — 基于 [libghostty](https://github.com/ghostty-org/ghostty)
- **分屏** — 水平和垂直分屏
- **主题** — Catppuccin、Dracula、Nord、Gruvbox、TokyoNight 等

### 代理
- **支持** — Claude、Codex、Gemini、Kimi 及自定义代理
- **协议** — Agent Client Protocol (ACP)
- **自动安装** — 从 NPM 或 GitHub releases 安装
- **语音输入** — 本地语音转文字，带波形可视化

### Git
- **操作** — 暂存、提交、推送、拉取、合并、分支
- **差异查看器** — 全窗口差异对比，带语法高亮
- **状态** — 实时文件状态指示

### 文件浏览器
- **树形视图** — 层级目录导航
- **语法高亮** — Tree-sitter 支持 50+ 种语言
- **多标签** — 打开多个文件

### 网页浏览器
- **独立浏览器** — 每个 worktree 内嵌浏览器，用于文档和预览
- **多标签** — 会话持久化

## 系统要求

- macOS 13.5+
- Apple Silicon 或 Intel Mac

### 从源码构建

- Xcode 16.0+
- Swift 5.0+
- Git LFS
- Zig（用于构建 libghostty）：`brew install zig`

```bash
git lfs install
git clone https://github.com/vivy-company/aizen.git
cd aizen

# 构建 libghostty（通用 arm64 + x86_64）
./scripts/build-libghostty.sh

# 在 Xcode 中打开并构建
open aizen.xcodeproj
```

在指定 commit 重新构建 libghostty：
```bash
./scripts/build-libghostty.sh <commit-sha>
```

## 安装

从 [aizen.win](https://aizen.win) 下载

已使用 Apple 开发者证书签名和公证。

## 配置

### 代理

设置 > 代理：

| 代理 | 安装方式 | 包名 |
|------|---------|------|
| Claude | NPM | `@anthropic-ai/claude-code` |
| Codex | GitHub | `openai/codex` |
| Gemini | NPM | `@anthropic-ai/claude-code` |
| Kimi | GitHub | `MoonshotAI/kimi-cli` |

代理可自动发现和安装，也可手动配置。

### 终端

设置 > 终端：
- 字体和大小
- 配色主题

### 编辑器

设置 > 通用：
- 默认外部编辑器（VS Code、Cursor、Sublime Text）

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
- [CodeEdit](https://github.com/CodeEditApp/CodeEdit) 包 — 语法高亮（Tree-sitter）
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 自动更新

## 架构

```
aizen/
├── App/                    # 入口
├── Models/                 # 数据模型、ACP 类型
├── Services/
│   ├── Agent/              # ACP 客户端、安装器、会话管理
│   ├── Git/                # Worktree、分支、暂存、差异服务
│   ├── Audio/              # 语音录制、转写
│   └── Highlighting/       # Tree-sitter 集成
├── Views/
│   ├── Workspace/          # 侧边栏、创建/编辑弹窗
│   ├── Worktree/           # 列表、详情、Git 侧边栏
│   ├── Terminal/           # 标签、分屏布局、面板
│   ├── Chat/               # 会话、输入、Markdown、工具调用
│   ├── Files/              # 树形视图、内容标签
│   ├── Browser/            # 标签、控件
│   └── Settings/           # 所有设置面板
├── GhosttyTerminal/        # libghostty 封装
└── Utilities/              # 工具函数
```

**设计模式：**
- MVVM 配合 `@ObservableObject`
- Actor 模型处理并发
- Core Data 持久化
- SwiftUI + async/await

## 许可证

GNU General Public License v3.0

版权所有 © 2025 Vivy Technologies Co., Limited
