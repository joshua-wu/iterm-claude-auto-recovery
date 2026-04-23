# iTerm2 Claude Code 会话自动恢复

[English](README_EN.md)

在 iTerm2 中重新打开标签页时，自动恢复上一次的 Claude Code 会话。

## 解决的问题

每次关闭并重新打开 iTerm2 标签页后，运行 `claude` 都会启动一个全新的会话——之前的对话上下文全部丢失。你不得不手动执行 `claude --resume <session-id>` 才能回到之前的会话。

## 工作原理

本脚本通过 shell 函数包装 `claude` 命令：

1. **将每个 iTerm2 标签页映射到一个 Claude 会话** —— 使用 iTerm2 的唯一标签页 UUID（`ITERM_SESSION_ID`）作为 key
2. **自动恢复** —— 当你在之前有过会话的标签页中输入 `claude` 时（且在同一工作目录下），自动恢复该会话
3. **优雅降级** —— 在非 iTerm2 终端中，`claude` 命令的行为与原来完全一致

映射关系存储在 `~/.claude/tab-sessions.tsv` 中。

## 功能特性

- **零感知** —— 像平常一样输入 `claude`，会话自动恢复
- **目录感知** —— 只有在与原始会话相同的目录下才会恢复
- **会话验证** —— 恢复前会检查会话文件是否仍然存在
- **手动控制**：
  - `claude --new` —— 在当前标签页强制新建会话
  - `claude --resume <id>` / `claude -r` / `claude -c` —— 手动会话控制（直接透传）
- **调试工具** —— 运行 `claude-sessions` 查看当前标签页与会话的映射关系

## 前置依赖

- [iTerm2](https://iterm2.com/)（macOS 终端模拟器）
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI 已安装
- 无其他外部依赖（纯 shell 实现）

## 通过 Claude 安装 / 卸载

### 安装

将下面的 prompt 复制粘贴到 Claude Code 中即可：

> 将 https://github.com/joshua-wu/iterm-claude-auto-recovery 克隆到 `~/.local/share/iterm-claude-auto-recovery`。然后检测我当前使用的 shell（通过 `$SHELL` 判断），将 `source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh` 添加到对应的 shell 配置文件中（zsh 对应 `~/.zshrc`，bash 对应 `~/.bashrc`）。如果已存在则不要重复添加。完成后对配置文件做语法检查。

### 卸载

将下面的 prompt 复制粘贴到 Claude Code 中即可：

> 从我的 shell 配置文件中删除 source `iterm_claude_auto_recovery.sh` 的那一行（通过 `$SHELL` 判断对应 `~/.zshrc` 还是 `~/.bashrc`）。同时删除目录 `~/.local/share/iterm-claude-auto-recovery` 和映射文件 `~/.claude/tab-sessions.tsv`（如果存在的话）。完成后对配置文件做语法检查。

## 手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/joshua-wu/iterm-claude-auto-recovery ~/.local/share/iterm-claude-auto-recovery

# 2. 添加到 shell 配置文件

# zsh 用户（~/.zshrc）：
echo 'source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh' >> ~/.zshrc

# bash 用户（~/.bashrc）：
echo 'source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh' >> ~/.bashrc

# 3. 重新加载配置
source ~/.zshrc  # 或 source ~/.bashrc
```

## 手动卸载

```bash
# 1. 从配置文件中删除 source 行
#    打开 ~/.zshrc（或 ~/.bashrc），删除以下这行：
#    source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh

# 2. 清理文件
rm -rf ~/.local/share/iterm-claude-auto-recovery
rm -f ~/.claude/tab-sessions.tsv
```

## 使用方式

```bash
# 正常使用 claude —— 会话按标签页自动恢复
claude

# 在当前标签页强制新建会话
claude --new

# 查看标签页与会话的映射关系
claude-sessions
```

## 映射机制

```
iTerm2 标签页 (UUID)  ──→  Claude 会话 ID + 工作目录
       ↓                           ↓
  标签页重新打开      ──→  查询映射 → 验证会话文件
                                   ↓
                      同目录 + 文件存在 → claude --resume <id>
                      否则             → 新建会话
```

## License

MIT
