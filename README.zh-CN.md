# MatTerm

> 使用 Swift 构建的原生 macOS 终端与 SSH 工作区。

[English](README.md)

MatTerm 面向需要频繁使用本地终端和 SSH 的 macOS 用户。它使用原生 SwiftUI 和 AppKit 界面、系统 PTY 以及系统 OpenSSH 客户端，保持响应流畅、资源占用较低，并与 macOS 的窗口和输入体系保持一致。

当前版本：**v0.2.0**

## 功能

- 基于真实 PTY 的本地终端会话。
- 从 `~/.ssh/config` 导入并同步 SSH 配置。
- 在 App 中新增或编辑的配置会写回本机 OpenSSH 配置文件。
- 支持 ANSI 颜色、256 色和 24 位真彩色渲染。
- 基于 Ghostty VT 核心实现终端解析、渲染、滚动和鼠标跟踪。
- 普通终端模式支持原生回滚滚动和可见滚动条。
- 内置 Tabby 社区配色方案。
- 支持设置字体、字号、额外行间距、光标闪烁、背景透明度和模糊程度。
- 使用自适应标签宽度的紧凑标签栏，并将新建标签按钮独立放置。
- 支持在设置中修改 SSH 配置选择器和分屏快捷键。
- 支持向左、向右、向上、向下分屏，每个子终端独立聚焦并独立显示光标。
- 记忆窗口大小和位置，支持窗口置顶以及全局显示/隐藏快捷键。
- 支持英文和简体中文界面。

v0.2.0 暂不包含端口转发；分屏目前采用方向性子窗口工作流。

## 系统要求

- macOS 26.0 或更高版本。
- 从源码构建需要 Swift 6.1 或更高版本，以及 macOS 26 SDK。
- 发布 App 同时包含 `arm64` 和 `x86_64` 两种架构。

## 构建和运行

```sh
git clone <repository-url>
cd MatTerm
./Scripts/build-app.sh
./Scripts/validate-app.sh
./Scripts/package-app.sh
open Build/MatTerm.app
```

构建脚本会先执行 Ghostty VT 核心、PTY、多路复用、外观和 App 级检查，分别编译两种 CPU 架构，生成标准 macOS 图标，并对 `Build/MatTerm.app` 进行临时签名。`Scripts/package-app.sh` 会在 `Artifacts/` 中生成 universal ZIP。

GitHub Actions 会在 `macos-26` runner 上执行相同的构建流程，上传 ZIP 工件；推送类似 `v0.2.0` 的 tag 时还会自动创建 GitHub Release。若要生成 Gatekeeper 可以直接接受的发布版本，请在仓库 Secrets 中配置：`APPLE_CERTIFICATE_P12_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_SIGNING_IDENTITY`、`APPLE_ID`、`APPLE_TEAM_ID` 和 `APPLE_APP_PASSWORD`。全部配置后，workflow 会执行 Developer ID 签名、公证、票据装订并上传经过公证的 ZIP。没有这些 Secrets 时，workflow 会明确生成临时签名 ZIP。

### v0.2.0

- 修复 ANSI 色块、终端文本对比度和行距对齐问题。
- 为普通终端加入回滚缓冲，使长输出场景下的滚动更流畅、稳定。
- 新增有效的回滚行数设置、文本选择与复制支持，以及 Cmd+Ctrl+F 全屏快捷键响应。
- 让 tmux 触控板滚动速度与普通终端一致，并在普通本地或 SSH shell 开始输入时自动回到实时提示符。

### v0.1.1

- 在保持现有 MatTerm 界面的同时，使用 Ghostty VT 核心重写终端视口逻辑。
- 修复普通终端滚轮回滚，并增加原生可见滚动条。
- 保持 tmux、Vim 和 screen 的鼠标事件由终端程序接收。
- 优化 ANSI、256 色和真彩色渲染，消除背景透出造成的竖线伪影。
- 减少滚动和分屏交互时的重复重绘。

如果只需要编译：

```sh
swift build -c release
```

MatTerm 当前面向个人使用和源码分发，不包含 Mac App Store 上架配置。

### 安装 GitHub 构建版本

对于 GitHub Actions 工件或 Release ZIP：

1. 下载并解压 ZIP。
2. 将 `MatTerm.app` 移动到 `/Applications`。
3. 第一次启动时按住 Control 点击 App，选择 **打开**，然后确认 **打开**。

默认 workflow 使用临时签名，因为仓库中不保存 Apple Developer 凭据。如果配置文档中列出的 GitHub Actions Secrets，生产 workflow 可以执行 Developer ID 签名和公证。没有公证时，Gatekeeper 可能要求第一次启动进行上述确认。App 本身是 universal，在 Apple Silicon Mac 上不需要 Rosetta。

## SSH 配置

MatTerm 使用系统 OpenSSH 客户端 `/usr/bin/ssh`。

- App 启动时会读取最新的 `~/.ssh/config`。
- 打开 SSH 配置选择器时，会在显示选择器前重新读取该文件。
- 保存配置时会更新匹配的 `Host` 块；找不到时会追加新的配置块。
- 更新配置时会保留无法由配置编辑器表示的选项以及其他无关的 `Host` 块。
- 身份验证仍由 OpenSSH、SSH Agent 和用户选择的身份文件负责，MatTerm 不保存密码。

如果已有 `Host` 块包含配置编辑器没有覆盖的高级选项，建议在使用其他 SSH 工具之前检查写回后的 `~/.ssh/config`。

## 项目结构

```text
Sources/MatTerm/      应用和终端实现
Resources/             Info.plist 和图标源文件
Scripts/               构建和运行检查脚本
Build/                 本机构建输出，已加入 Git 忽略
Artifacts/             本地发布压缩包，已加入 Git 忽略
```

## 许可证

MatTerm 使用 [MIT 许可证](LICENSE) 发布。
