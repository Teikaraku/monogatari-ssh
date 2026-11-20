# 物语SSH（MonogatariSSH）

为在 iPhone 上驾驭 AI agent（Claude Code / Codex / Gemini CLI）而做的原生 SSH 终端。SwiftUI + iOS 原生组件，iOS 26 自动使用液态玻璃。

## 功能
- 连接：SSH（密码 / ED25519 / RSA / ECDSA 私钥，带口令）、跳板机链、本地端口转发、Telnet
- 会话恢复：tmux / screen，断线、锁屏后 agent 继续跑，回来自动接回；断线自动重连
- Agent 预设：连接后自动启动 Claude Code / Codex / Gemini / 自定义命令；Agent 快捷键栏（中断、⇧Tab 切模式、换行、1/2/3/y/n、/指令、@文件、#记忆）
- 写作框：用原生输入法写长提示词，bracketed paste 一次发送；常用提示语与历史
- 滑动优化：后台线程解析输出 + Metal 渲染；普通屏原生惯性滚动；tmux/vim/less 里单指滑动转为带惯性的滚轮；tmux 手机优化（鼠标、5 万行历史、单行滚轮）；回到底部按钮；双指捏合调字号
- 主机：密码默认隐藏，点眼睛显示，一键复制 IP / 用户名 / 密码 / SSH 命令；长按菜单、左右滑动操作
- 密钥生成与导入、主机指纹（TOFU）、命令片段（含 agent 预置）、SFTP 文件管理与传输记录、10 套配色

## 构建
推送到 `main` 后 GitHub Actions 自动编译：
- `MonogatariSSH-ipa` 构建产物 + `nightly` Release：未签名 IPA，用 TrollStore / Sideloadly / AltStore 自签安装
- `screenshots` 构建产物：模拟器各页面截图

本地（macOS + Xcode 26）：`brew install xcodegen && xcodegen generate && open MonogatariSSH.xcodeproj`
