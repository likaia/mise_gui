<p align="center">
  <img src="docs/brand-mark.png" alt="Mise GUI Logo" width="120" height="120">
</p>


<p align="center">
  简体中文 · <a href="README.en.md">English</a>
</p>

# Mise GUI

一个面向开发者的 mise 可视化管理软件，通过图形化界面快速管理本地工具链版本以及项目内所依赖工具版本。

![demo-img-1.png](docs/demo-img-1.png)

## 项目简介

Mise GUI 是一个基于 Flutter 的跨平台桌面应用，为 [mise](https://mise.jdx.dev/) 提供更直观的本地环境管理体验。它会读取真实的 mise CLI 状态，把系统信息、已安装工具、项目级版本覆盖、全局配置和最近操作集中到一起进行快速便捷的管理。

本项目适合经常在多语言、多项目之间切换的开发者：你不需要反复执行 `mise current`、`mise ls`、`mise outdated` 或打开多个 `mise.toml` 文件，就能快速判断当前有哪些项目覆盖了全局版本。



## 界面预览



### 工具版本

按工具查看当前版本和最新版本，进入详情后可以加载远端版本、切换版本、升级或卸载。

![demo-img-2.png](docs/demo-img-2.png)

### 安装新工具

安装流程会先读取远端可选版本，确认后进入命令预览，不会直接执行不可见操作。

![demo-img-3.png](docs/demo-img-3.png)

### 项目覆盖

你可以添加多个扫描目录，应用会递归检查项目配置，并把覆盖全局默认版本的项目单独展示出来。

![demo-img-4.png](docs/demo-img-4.png)

### 配置管理

配置页把全局配置和项目配置放在同一个上下文里，编辑 TOML 前后可以查看差异，减少误改风险。

![demo-img-5.png](docs/demo-img-5.png)

## 开始使用

前往[releases](https://github.com/likaia/mise_gui/releases)页下载符合你操作系统的最新版本，软件成功安装后，如果当前机器没有安装 mise，应用会进入引导页并给出推荐安装命令：

```bash
# macOS
brew install mise

# Windows
winget install jdx.mise

# Linux
curl https://mise.run | sh
```



## 本地开发

```bash
git clone https://github.com/likaia/mise_gui.git
cd mise_gui

flutter pub get
flutter run -d macos
```

其他桌面平台可以替换运行目标：

```bash
flutter run -d linux
flutter run -d windows
```



## 项目结构

```text
lib/
  app/                  # 应用启动、路由、主题和外壳
  features/
    dashboard/          # 环境总览
    tools/              # 工具版本、安装、升级、卸载
    projects/           # 扫描目录和项目覆盖
    config/             # 全局与项目配置管理
  repositories/         # 页面数据聚合
  services/             # mise CLI、配置、历史、更新等底层服务
  shared/ui/            # 通用面板、状态、对话框和预览组件
scripts/                # macOS 打包脚本
docs/                   # README 截图素材
```



## License

本项目使用MIT作为开源协议，详情请移步： [LICENSE.txt](LICENSE.txt)。
