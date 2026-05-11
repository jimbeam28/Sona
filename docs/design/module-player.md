# Player 模块功能设计

## 1. 模块概述

Player 模块是应用的核心，负责音频的流式播放、播放控制、后台播放、系统媒体控件集成。基于 `just_audio` + `audio_service` 构建，支持锁屏控件和通知栏媒体控件。

---

## 2. 功能列表

| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| PLY-01 | 音频流式播放 | P0 |
| PLY-02 | 基础播放控制 | P0 |
| PLY-03 | 后台播放 | P0 |
| PLY-04 | 锁屏/通知栏媒体控件 | P0 |
| PLY-05 | 播放队列管理 | P0 |
| PLY-06 | 播放模式切换 | P0 |
| PLY-07 | 播放速度调节 | P0 |
| PLY-08 | 迷你播放器 | P1 |

---

## 3. 功能详细设计

### PLY-01 音频流式播放

**播放方式：** 通过 WebDAV URL 直接流式播放，无需完整下载

**URL 构建：**
```dart
// WebDAV URL 即为 HTTP URL，just_audio 可直接播放
final audioUrl = '${connection.url}${file.path}';
// 需要在请求头中携带 Basic Auth
```

**认证处理：** `just_audio` 支持自定义 HTTP 请求头，通过 `AudioSource.uri` 的 `headers` 参数传入 `Authorization: Basic <base64>` 头。

**支持格式：** MP3、FLAC、AAC、M4A、M4B、OGG、Opus、WAV（Android 系统解码器支持）

**缓冲策略：** 使用 `just_audio` 默认缓冲策略，预缓冲 30 秒

---

### PLY-02 基础播放控制

**控制操作：**
- 播放 / 暂停
- 上一首 / 下一首
- 进度拖拽（Seek）
- 快进 / 快退 15 秒（有声书常用）

**进度显示：**
- 当前时间（`00:00:00` 格式）
- 总时长
- 进度条（Slider）

**自动进度保存：** 每 10 秒自动保存一次当前播放位置到数据库（见 Progress 模块）

---

### PLY-03 后台播放

**实现方案：** `audio_service` 包，将 `just_audio` 包装为 Android 前台服务

**Android 配置：**
```xml
<!-- AndroidManifest.xml -->
<service android:name="com.ryanheise.audioservice.AudioServiceIsolate"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>
```

**行为：** 切换到其他应用或锁屏后，音频继续播放，通知栏显示媒体控件

---

### PLY-04 锁屏/通知栏媒体控件

**通知栏显示内容：**
- 专辑封面（若有，从 ID3 标签读取；否则显示默认图标）
- 曲目名称（文件名，去掉扩展名）
- 上一首 / 播放暂停 / 下一首 按钮

**锁屏控件：** Android 系统自动从通知栏媒体控件生成

**耳机按键支持：**
- 单击：播放/暂停
- 双击：下一首
- 三击：上一首

---

### PLY-05 播放队列管理

**队列来源：** 由 Browser 模块在用户点击文件时构建（当前目录所有音频文件）

**队列操作：**
- 查看当前队列（底部弹出列表）
- 点击队列中的曲目直接跳转播放
- 队列内拖拽排序（P2，暂不实现）

**队列持久化：** 应用重启后恢复上次的播放队列和位置

---

### PLY-06 播放模式切换

**支持模式：**
- 顺序播放（默认）
- 单曲循环
- 列表循环
- 随机播放

**UI：** 播放器页面右下角循环/随机按钮，点击切换，图标反映当前模式

---

### PLY-07 播放速度调节

**速度选项：** 0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 2.0x

**UI：** 播放器页面速度按钮，点击弹出选择菜单

**持久化：** 速度设置保存到 SharedPreferences，下次启动保持

**实现：** `just_audio` 的 `setSpeed()` 方法，同时保持音调不变（`just_audio` 默认行为）

---

### PLY-08 迷你播放器

**显示时机：** 有音频在播放时，在 Browser 页面底部显示迷你播放器条

**显示内容：**
- 当前曲目名称
- 播放/暂停按钮
- 下一首按钮
- 进度条（细线，不可拖拽）

**交互：** 点击迷你播放器主体区域 → 展开完整播放器页面

---

## 4. 数据模型

```dart
class PlaybackState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;
  final PlayMode playMode;
  final MediaItem? currentItem;
}

class MediaItem {
  final String id;        // 文件路径
  final String title;     // 文件名（去扩展名）
  final String? album;    // 目录名
  final Uri artUri;       // 封面图 URI
  final Duration? duration;
}

enum PlayMode { sequential, repeatOne, repeatAll, shuffle }
```

---

## 5. AudioHandler 设计

```dart
class NasAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;

  // 实现 audio_service 要求的方法
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> skipToQueueItem(int index);
  Future<void> setSpeed(double speed);
  Future<void> updateQueue(List<MediaItem> queue);
}
```

---

## 6. UI 结构

```
PlayerScreen
├── AlbumArtwork           # 封面图（大图）
├── TrackInfo              # 曲目名称、所在目录
├── ProgressBar            # 进度条 + 时间显示
├── SpeedButton            # 速度调节按钮
├── PlayControls           # 上一首/播放暂停/下一首 + 快进快退
├── PlayModeButton         # 播放模式切换
└── QueueButton            # 查看播放队列

MiniPlayer (overlay)
├── TrackTitle
├── ProgressLine
├── PlayPauseButton
└── NextButton
```

---

## 7. 关键文件

| 文件 | 职责 |
|------|------|
| `lib/core/services/audio_handler.dart` | audio_service 处理器，核心播放逻辑 |
| `lib/features/player/player_screen.dart` | 播放器完整页面 |
| `lib/features/player/player_provider.dart` | 播放状态 Provider |
| `lib/features/player/widgets/mini_player.dart` | 迷你播放器组件 |
| `lib/features/player/widgets/play_controls.dart` | 播放控制按钮组 |
| `lib/features/player/widgets/progress_bar.dart` | 进度条组件 |
