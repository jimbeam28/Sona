# NAS 音乐/有声书播放器

基于 Flutter 的 Android 音频播放器，通过 WebDAV 协议连接飞牛OS NAS，支持音乐和有声书播放。

## 核心功能

- **NAS 文件浏览**：通过 WebDAV 访问 NAS 上的音乐和有声书文件
- **音频播放**：支持流式播放、后台播放、锁屏媒体控件
- **播放进度记忆**：自动保存每个文件的播放位置，下次续播
- **定时停止**：支持固定时长（5/10/15分钟）和播完当前音频两种模式
- **播放速度调节**：适配有声书等场景

## 技术栈

Flutter · Riverpod · just_audio · audio_service · WebDAV · SQLite · go_router

## 环境要求

- Flutter SDK >= 3.3.0
- Android SDK（用于构建 APK）
- 一台开启 WebDAV 服务的 NAS（飞牛OS / 群晖 / 威联通等）

## 项目结构

```
lib/
├── core/           # 网络、数据库、服务层
├── features/       # 功能模块（连接、浏览、播放、设置）
└── shared/         # 共享模型和组件
```

## 快速开始

```bash
# 安装依赖
flutter pub get

# 开发调试
flutter run
```

## 构建 APK（安装到手机）

```bash
# 一键构建
./build_apk.sh
```

构建完成后，APK 位于 `build/app/outputs/flutter-apk/app-release.apk`，传到手机安装即可。

> 安装前需在手机设置中允许「未知来源」应用安装。

## 连接 NAS

1. 打开 APP，进入**连接管理**
2. 点击添加，填写 NAS 的 WebDAV 信息：

| 字段 | 说明 | 示例 |
|------|------|------|
| 地址 | WebDAV 服务地址 | `http://192.168.1.100:5005` |
| 用户名 | NAS 登录账号 | `admin` |
| 密码 | NAS 登录密码 | - |
| 名称 | 可选，显示用 | `我的NAS` |
| 路径 | 可选，起始目录 | `/music` |

3. 保存后即可浏览和播放 NAS 上的音频文件

> 飞牛OS 在「文件管理 → 设置 → WebDAV」中开启服务。

## 架构概览

```
UI Layer → State Layer (Riverpod) → Service Layer → Data Layer (WebDAV / SQLite)
```

详细架构设计见 [docs/design/architecture.md](docs/design/architecture.md)。
