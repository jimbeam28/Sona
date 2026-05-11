# Settings 模块功能设计

## 1. 模块概述

Settings 模块管理应用级别的用户偏好配置，包括播放速度默认值、界面主题、以及 NAS 连接管理入口。设计为轻量级配置中心，方便后续扩展更多设置项。

---

## 2. 功能列表

| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| SET-01 | 默认播放速度设置 | P0 |
| SET-02 | NAS 连接管理入口 | P0 |
| SET-03 | 界面主题切换（亮色/暗色） | P1 |
| SET-04 | 快进/快退步长设置 | P1 |
| SET-05 | 关于页面 | P2 |

---

## 3. 功能详细设计

### SET-01 默认播放速度设置

**入口：** 设置页 → 播放设置 → 默认速度

**选项：** 0.5x / 0.75x / 1.0x（默认）/ 1.25x / 1.5x / 2.0x

**行为：** 新开始播放一个文件时，使用此速度；用户在播放器中调节速度后，该次播放使用调节后的速度，但不修改默认值

**持久化：** SharedPreferences，key: `default_playback_speed`

---

### SET-02 NAS 连接管理入口

**入口：** 设置页 → 连接管理

**跳转：** 进入 Connection 模块的连接列表页，支持添加、编辑、删除、切换连接

---

### SET-03 界面主题切换

**选项：** 跟随系统 / 亮色 / 暗色

**持久化：** SharedPreferences，key: `theme_mode`

**实现：** 在 `MaterialApp` 的 `themeMode` 参数中读取此设置

---

### SET-04 快进/快退步长设置

**入口：** 设置页 → 播放设置 → 快进/快退步长

**选项：** 10秒 / 15秒（默认）/ 30秒 / 60秒

**持久化：** SharedPreferences，key: `seek_step_seconds`

---

### SET-05 关于页面

**显示内容：**
- 应用名称和版本号
- 开源许可证列表（Flutter、just_audio 等）

---

## 4. 存储方案

所有设置项使用 `SharedPreferences` 存储（轻量键值对，无需 SQLite）：

```dart
class AppSettings {
  static const String keyDefaultSpeed = 'default_playback_speed';
  static const String keyThemeMode = 'theme_mode';
  static const String keySeekStep = 'seek_step_seconds';
}
```

---

## 5. Provider 设计

```dart
@riverpod
class AppSettingsNotifier extends _$AppSettingsNotifier {
  Future<double> getDefaultSpeed();
  Future<void> setDefaultSpeed(double speed);

  Future<ThemeMode> getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);

  Future<int> getSeekStep();
  Future<void> setSeekStep(int seconds);
}
```

---

## 6. UI 结构

```
SettingsScreen
├── Section: 播放设置
│   ├── 默认播放速度（ListTile + 选择对话框）
│   └── 快进/快退步长（ListTile + 选择对话框）
├── Section: 外观
│   └── 主题（ListTile + 三选一对话框）
├── Section: 连接
│   └── 管理 NAS 连接（ListTile → 跳转 Connection 页面）
└── Section: 关于
    └── 关于本应用（ListTile → 关于页面）
```

---

## 7. 关键文件

| 文件 | 职责 |
|------|------|
| `lib/features/settings/settings_screen.dart` | 设置页面 UI |
| `lib/features/settings/settings_provider.dart` | 设置状态管理 |
