# Progress 模块功能设计

## 1. 模块概述

Progress 模块负责记录和恢复每个音频文件的播放进度，确保用户下次打开同一文件时可以从上次停止的位置继续播放。对有声书场景尤为重要。

---

## 2. 功能列表

| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| PRG-01 | 自动保存播放进度 | P0 |
| PRG-02 | 启动时恢复播放进度 | P0 |
| PRG-03 | 进度恢复确认提示 | P0 |
| PRG-04 | 清除单个文件进度 | P1 |

---

## 3. 功能详细设计

### PRG-01 自动保存播放进度

**触发时机（多点保存，确保不丢失）：**
1. 每 10 秒定时保存一次当前位置
2. 用户手动暂停时立即保存
3. 切换曲目时保存上一首的进度
4. 应用进入后台时保存
5. 应用被关闭时保存（`AppLifecycleState.detached`）

**保存内容：**
- 文件路径（唯一标识）
- 连接 ID（区分不同 NAS）
- 播放位置（毫秒）
- 总时长（毫秒，用于显示进度百分比）
- 最后播放时间（用于排序「最近播放」）

**不保存的情况：**
- 播放位置在文件开头（< 5 秒）：视为未开始，不保存
- 播放位置在文件结尾（> 总时长 - 10 秒）：视为播完，清除进度记录

---

### PRG-02 启动时恢复播放进度

**触发时机：** 用户在 Browser 页面点击一个音频文件时

**查询逻辑：**
```dart
final progress = await progressDao.getProgress(
  connectionId: activeConnection.id,
  filePath: file.path,
);
```

**有进度记录时：** 触发 PRG-03 确认提示

**无进度记录时：** 直接从头播放

---

### PRG-03 进度恢复确认提示

**UI：** 点击文件后，若有进度记录，弹出对话框：

```
上次播放到 1:23:45
是否从此处继续？

[从头播放]    [继续播放]
```

**「继续播放」：** 加载文件，seek 到保存的位置，开始播放

**「从头播放」：** 加载文件，从 0:00 开始播放，清除该文件的进度记录

**超时自动选择：** 5 秒无操作，自动选择「继续播放」（倒计时显示在按钮上）

---

### PRG-04 清除单个文件进度

**入口：** 文件列表长按 → 「清除播放进度」（仅有进度记录的文件显示此选项）

**行为：** 删除数据库中该文件的进度记录，文件列表中的进度指示器消失

---

## 4. 数据库设计

```sql
CREATE TABLE play_progress (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id   INTEGER NOT NULL,
    file_path       TEXT NOT NULL,
    position_ms     INTEGER NOT NULL,
    duration_ms     INTEGER,
    last_played_at  INTEGER NOT NULL,
    UNIQUE(connection_id, file_path),
    FOREIGN KEY(connection_id) REFERENCES connections(id) ON DELETE CASCADE
);

CREATE INDEX idx_progress_lookup ON play_progress(connection_id, file_path);
```

---

## 5. 数据模型

```dart
class PlayProgress {
  final int? id;
  final int connectionId;
  final String filePath;
  final Duration position;
  final Duration? duration;
  final DateTime lastPlayedAt;

  double get percentage =>
      duration != null ? position.inMilliseconds / duration!.inMilliseconds : 0;
}
```

---

## 6. DAO 设计

```dart
class ProgressDao {
  Future<PlayProgress?> getProgress(int connectionId, String filePath);
  Future<void> saveProgress(PlayProgress progress);
  Future<void> deleteProgress(int connectionId, String filePath);
  Future<List<PlayProgress>> getRecentlyPlayed(int connectionId, {int limit = 20});
}
```

---

## 7. 进度指示器（Browser 页面集成）

**显示位置：** 文件列表中，有进度记录的音频文件行底部显示细进度条

**显示内容：** 进度百分比（颜色条），鼠标悬停/长按显示具体时间

---

## 8. 关键文件

| 文件 | 职责 |
|------|------|
| `lib/core/database/dao/progress_dao.dart` | 进度数据库操作 |
| `lib/core/services/audio_handler.dart` | 进度自动保存触发点 |
| `lib/features/browser/widgets/file_list_item.dart` | 进度指示器显示 |
| `lib/features/player/player_provider.dart` | 进度恢复逻辑 |
| `lib/shared/models/play_progress.dart` | 数据模型 |
