# Open Island — Reimagine

**基于 [Open Island](https://github.com/Octane0411/open-vibe-island) 的 GPL-3.0 衍生版**，增加刘海用量芯片：**C**（Codex %）· **G**（Grok %）· **W**（WorkBuddy 剩余点数）· **O**（GitHub Copilot **已用 credits**）。

| | |
|--|--|
| **本仓库** | https://github.com/leeyf2018/Openisland-Reimagine |
| **上游** | https://github.com/Octane0411/open-vibe-island |
| **许可证** | [GPL-3.0](LICENSE)（与上游相同，再分发须提供源码） |
| **说明** | [NOTICE](NOTICE) · [改动说明](docs/REIMAGINE_CHANGES.md) · [构建](docs/BUILDING.md) |

## 下载

| 你想要什么 | 怎么做 |
|------------|--------|
| **预编译安装包（多数人直接用这个）** | 打开 [**Releases**](https://github.com/leeyf2018/Openisland-Reimagine/releases/latest) → 下载 `Open.Island.zip`（有 DMG 时也可使用）→ 解压 → 把 `Open Island.app` 拖到「应用程序」 |
| **只要源码 ZIP** | 仓库页 **Code → Download ZIP**，或 [main.zip](https://github.com/leeyf2018/Openisland-Reimagine/archive/refs/heads/main.zip)，再按文档自己编译 |

**首次打开预编译包：** 当前 Release 为 **本机 ad-hoc 签名**（不是 Apple 开发者公证）。若系统提示无法打开：

1. 右键 App → **打开** → 确认；或  
2. **系统设置 → 隐私与安全性** → 仍要打开  

只想用、不改代码：下预编译即可。GPL 源码仍完整提供，便于审查与二次开发。

## 从源码构建

```bash
git clone https://github.com/leeyf2018/Openisland-Reimagine.git
cd Openisland-Reimagine
swift build
swift run OpenIslandApp

# 打包
export OPEN_ISLAND_PACKAGE_ROOT="$PWD/output/package"
./scripts/package-app.sh
```

详见 [docs/BUILDING.md](docs/BUILDING.md)。

### O（Copilot credits）

需要本机安装并登录 [GitHub CLI](https://cli.github.com/)：`gh auth login`。

### W（WorkBuddy 剩余点数）

W 显示 WorkBuddy 当前账户页中的整数点数。首次使用需要给 `Open Island` 辅助功能权限；之后应用会周期刷新，也可点击 W 手动刷新。

## 声明

本仓库是 Open Island 的**衍生作品**，不是从零重写的独立产品。欢迎在 GPL-3.0 下使用与改进；若改动适合所有人，也欢迎回馈上游。
