# 物语SSH

iPhone 上的 SSH 终端。主要是为了在手机上用 Claude Code 这类命令行 agent。

## 功能

- **连接**：密码或私钥登录，支持跳板机和本地端口转发，可导入 `~/.ssh/config`
- **断线不丢活**：会话跑在 tmux 里，锁屏或切换网络后自动重连
- **agent 状态**：能看出它在工作、等确认还是空闲；等确认和跑完时发通知，可以直接回「允许 / 拒绝」
- **终端**：可自定义的按键栏、长输出滚动、搜索，另有一个写长提示词用的输入框
- **文件**：SFTP 浏览、上传下载、直接改远程的文本文件

## 安装

在 [Releases](../../releases) 下载 `nightly` 里的 IPA。它没有签名，要用 TrollStore、Sideloadly 或 AltStore 安装。需要 iOS 17 或以上。

## 编译

需要 macOS 和 Xcode 26。

```sh
brew install xcodegen
xcodegen generate
open MonogatariSSH.xcodeproj
```

推送到 `main` 后 GitHub Actions 也会自动编出 IPA。

## 还没做

Mosh、keyboard-interactive 认证、远程端口转发。
