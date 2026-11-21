# 物语SSH

iPhone 上的 SSH 终端。主要是为了在手机上用 Claude Code 这类命令行 agent。

## 功能

### 连接

- 密码或私钥登录（ED25519 / RSA / ECDSA，可带口令）
- 跳板机、本地端口转发、Telnet
- 快速连接：粘贴一条 `ssh -p 端口 user@host` 就能连
- 导入 `~/.ssh/config`，保存前可以先测试连接
- 首次连接记住主机指纹，指纹变了会提示
- 回到前台或切换网络后自动重连；app 被系统关掉后可以一键恢复上次的会话
- 长按 app 图标直连最近用过的主机

### agent

- 会话跑在 tmux 或 screen 里，锁屏断线后 agent 继续运行
- 连上后自动启动 Claude Code / Codex / Gemini，或者自己填的命令
- 识别 agent 的状态（工作中 / 等确认 / 空闲）和当前模式，显示在顶栏和会话列表
- 等确认、任务完成时发通知，点通知直接进会话
- 快速回复「允许 / 始终允许 / 拒绝」，不用进终端也不用弹键盘
- tmux 会话管理：列出、接入、结束、重命名，新建并行的 agent 会话
- 斜杠指令面板（`/compact` `/clear` `/model` `/resume` 等），最近用过的排在前面
- 写作框：用系统输入法写长提示词，一次发送；保存常用短语和历史
- 从相册选图上传到服务器，并把路径插进提示词
- 命令片段，支持 `{{变量}}`
- 工作计时、复制 agent 的最后一条回复

### 终端

- 按键栏：第一行是 esc / tab / ctrl / alt / 方向键；第二行可以横滑，内容在设置里增删排序
- 按键栏预设：Agent / Shell / Vim
- 长输出滚动流畅；在 tmux、vim、less 里单指滑动等同滚轮
- 搜索终端内容，带高亮和上一个 / 下一个
- 点一下移动光标，方便改长命令和提示词
- 服务器命令历史
- 链接在 app 内的浏览器打开
- 顶栏点主机名切换或新开会话
- 外接键盘快捷键
- 双指缩放字号，10 套配色，可选光标样式

### 文件和数据

- SFTP：浏览、筛选、排序、上传下载、新建、重命名、删除
- 直接编辑远程文本文件
- 把文件作为 `@文件` 发给 agent，或者 cd 到所在目录
- 服务器状态：CPU、内存、磁盘、负载、占用高的进程、正在运行的 agent
- tmux 里复制的内容同步到 iPhone 剪贴板
- 一键复制 IP、用户名、密码、SSH 命令
- 备份和迁移（JSON，可以选择是否包含密码和私钥）

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
