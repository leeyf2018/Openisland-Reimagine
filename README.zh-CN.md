# Open Island — Reimagine

**基于 [Open Island](https://github.com/Octane0411/open-vibe-island) 的 GPL-3.0 衍生版**，增加刘海用量芯片：**C**（Codex %）· **G**（Grok %）· **O**（GitHub Copilot **已用 credits**）。

| | |
|--|--|
| **本仓库** | https://github.com/leeyf2018/Openisland-Reimagine |
| **上游** | https://github.com/Octane0411/open-vibe-island |
| **许可证** | [GPL-3.0](LICENSE)（与上游相同，再分发须提供源码） |
| **说明** | [NOTICE](NOTICE) · [改动说明](docs/REIMAGINE_CHANGES.md) · [构建](docs/BUILDING.md) |

## 下载 ZIP

GitHub 页面 → **Code** → **Download ZIP**，或：

```text
https://github.com/leeyf2018/Openisland-Reimagine/archive/refs/heads/main.zip
```

ZIP 是**源码**，需在本机 macOS 上构建 `.app`（见下方）。

## 从源码构建

```bash
git clone https://github.com/leeyf2018/Openisland-Reimagine.git
cd Openisland-Reimagine
swift build
swift run OpenIslandApp

# 打包
export OPEN_ISLAND_VERSION="1.1.6-reimagine"
export OPEN_ISLAND_PACKAGE_ROOT="$PWD/output/package"
./scripts/package-app.sh
```

详见 [docs/BUILDING.md](docs/BUILDING.md)。

### O（Copilot credits）

需要本机安装并登录 [GitHub CLI](https://cli.github.com/)：`gh auth login`。

## 声明

本仓库是 Open Island 的**衍生作品**，不是从零重写的独立产品。欢迎在 GPL-3.0 下使用与改进；若改动适合所有人，也欢迎回馈上游。
