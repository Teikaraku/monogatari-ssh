# 物语SSH（MonogatariSSH）

为在 iPhone 上驾驭 AI agent（Claude Code / Codex / Gemini CLI）而做的原生 SSH 终端。SwiftUI + iOS 原生组件，iOS 26 自动使用液态玻璃。

## 连接
- SSH：密码 / ED25519 / RSA / ECDSA 私钥（含口令）、跳板机链、本地端口转发（应用内浏览器预览）、Telnet
- 测试连接、快速连接（粘贴 `ssh -p 端口 user@host`）、导入 `~/.ssh/config`
- 主机指纹 TOFU；指纹变化时醒目提示并可确认更新
- 回到前台探活并自动重连；app 被系统杀掉后「继续上次的会话」一键恢复；长按 app 图标直连最近主机；点通知直达会话

## AI agent
- 会话恢复：tmux / screen，锁屏断线 agent 继续跑；连接后自动启动 Claude Code / Codex / Gemini / 自定义命令（启动命令可自定义）
- Agent 状态识别：工作中 / 等待确认 / 空闲，显示在顶栏与会话列表；当前模式（计划 / 自动接受 / 跳过权限）
- 后台通知：等待确认、任务完成、响铃、OSC 9/777
- 快速回复（1 允许 / 2 始终 / 拒绝）：会话列表里、终端收起键盘时浮动显示，不用进终端或弹键盘
- 工作计时、会话重命名、复制 agent 最后一条回复、前台看别的会话时顶部提醒
- tmux 会话管理：列出、接入、结束；新建并行 agent 会话
- 斜杠指令面板（/compact /clear /model /resume /context …，最近使用置顶）
- 写作框：原生输入法写长提示词，bracketed paste 一次发送；常用短语与历史；从相册选图上传到服务器并插入路径
- 命令片段：agent 预置 + `{{变量}}` 填写

## 终端
- 键盘辅助栏：第一行 esc / tab / ctrl / alt / 方向键（按住连发）/ 收起键盘；第二行可横滑、可在设置里自定义增删排序（模式、换行、1/2/3、/指令、@文件、粘贴、写作、片段、^C ^R ^L、F1–F12、符号…）；ctrl / alt 对辅助栏按键同样生效
- 滑动优化：网络线程解析输出 + Metal 渲染；普通屏原生惯性滚动；tmux / vim / less 中单指滑动转为带惯性的滚轮；tmux 手机优化（鼠标、5 万行历史、单行滚轮），未开启鼠标时一键开启；回到底部按钮
- 终端内搜索（高亮、上一个/下一个、计数）、输出浏览（原生选择 / 查找 / 分享）
- 点按移动光标（编辑 agent 提示词 / 长命令，中文按字符计）；服务器命令历史；链接在应用内浏览器打开
- 辅助栏预设方案（Agent / Shell / Vim）、长按按键看说明
- 顶栏点主机名切换会话或新开会话；硬件键盘快捷键（⌘F ⌘K ⌘± ⌘[ ⌘] …）
- 双指捏合字号、10 套配色、光标样式

## 文件与数据
- SFTP：浏览、筛选、排序、上传下载（含相册）、新建文件、重命名删除、远程文本编辑（改 CLAUDE.md / .env）、作为 @文件 发给 agent、cd 到此处
- 服务器状态：CPU / 内存 / 磁盘 / 负载 / 高占用进程 / 运行中的 agent 进程
- tmux 会话重命名；tmux 复制内容同步到 iPhone 剪贴板（OSC 52）
- 密码默认隐藏，眼睛切换，一键复制 IP / 用户名 / 密码 / SSH 命令
- 备份与迁移（JSON，可选含密码与私钥）

## 构建
推送到 `main` 后 GitHub Actions 自动编译：
- `nightly` Release：未签名 IPA，用 TrollStore / Sideloadly / AltStore 自签安装
- `screenshots` 构建产物：模拟器各页面截图

本地（macOS + Xcode 26）：`brew install xcodegen && xcodegen generate && open MonogatariSSH.xcodeproj`
