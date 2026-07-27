# BUG-15 — 音频识别基于 displayname 而非 href

> 来源：`docs/cr/cr-20260724-0110.md` MDL2
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-15
name: 音频识别基于 displayname 而非 href
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/shared/models/nas_file.dart
  - lib/features/browser/domain/directory_service.dart
cross_module_impacts: [BRW]
parent_feature: null  # 跨模块：锚点为共享模型 NasFile，影响 Browser 文件列表
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md MDL2：NasFile.audioType 用 isAudioFile(name) 判定，name 取 displayname。部分 NAS 对 href `/music/song.mp3` 返回 displayname `song`（去扩展名）→ isAudioFile('song')=false → 文件在浏览器中整条消失。

### 1.1 这一功能干什么（一句话）

修复无扩展名 displayname 导致音频文件从浏览列表消失的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | NAS 返回 displayname `song`（href 为 `/music/song.mp3`） | 浏览器显示该文件（按 href 末段 `song.mp3` 判定为音频） |
| U2 | NAS 返回 displayname `My Book`（href 为 `/books/book.m4b`） | 分类为 audiobook（按 href 末段 `book.m4b` 判定） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Shared Model | `lib/shared/models/nas_file.dart` | ~220 | NasFile.fromProps + audioType 判定 |
| Domain | `lib/features/browser/domain/directory_service.dart` | ~210 | 过滤 audioType != null |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-15-S1]** isAudioFile/classifyType 改用 href 末段判定 (`status: new`)
  ```
  Given href="/music/Simon & Garfunkel.mp3", displayname="Simon &amp; Garfunkel"
  When  NasFile.fromProps 构造
  Then  audioType 用 href 末段 "Simon & Garfunkel.mp3" 判定 → isAudioFile=true
        name 仍取 displayname（显示标签）
  否定断言:
    - 不用 displayname 做 isAudioFile 判定（当前 BUG 行为）
    - 不改变 name 字段的 displayname 来源（displayname 仅作显示标签）
    - 不改变 isDirectory 的判定逻辑
  ```
  Code evidence: `lib/shared/models/nas_file.dart:117-118`（audioType 用 name 判定）, `:93-96`（name 取 displayname）
   对照：`lib/features/browser/domain/directory_service.dart:140`（过滤 audioType != null → 文件消失）

   **修改指令 — `lib/shared/models/nas_file.dart`**

   位置：`:116-118`（audioType 判定使用 `name` 即 displayname）

   当前代码（:116-118）：
   ```dart
       // Classify audio type
       final audioType =
           (!isDirectory && isAudioFile(name)) ? classifyType(name) : null;
   ```

   改为：
   ```dart
       // Classify audio type — use href-derived filename (BUG-15)
       final hrefFilename = cleanHref.split('/').last;
       final audioType =
           (!isDirectory && isAudioFile(hrefFilename)) ? classifyType(hrefFilename) : null;
   ```

   边界裁决：
   - `cleanHref` 无路径段（如空字符串或 `/`）→ `cleanHref.split('/').last` 返回空字符串 → `isAudioFile('')` 返回 false → audioType = null（安全降级，不误判）
   - `cleanHref` 为相对路径（如 `music/song.mp3`）vs 绝对路径（如 `/music/song.mp3`）→ `split('/').last` 两种情况都返回 `song.mp3`（行为一致）
   - `cleanHref` 已去除尾部斜杠（`:88-90`）→ 目录 `/music/` 变为 `/music`，`split('/').last` 返回 `music`，但 `!isDirectory` guard 已阻止目录被分类 → 不影响
   - `name` 字段仍取 displayname（`:93-96` 不变）→ 显示标签不受影响，仅音频判定改用 href
   - `classifyType` 也改用 `hrefFilename` → `.m4b` 判定和 "有声书"/"audiobook" 关键词匹配基于 href 末段（文件名含扩展名），比 displayname 更可靠
   - `cleanHref` 已在 `:88-90` 定义，在作用域内 → 无需新增变量或 import
   - URL 编码的 href（如 `%20`）已在 `:80-85` 被 `Uri.decodeFull` 解码 → `cleanHref` 是解码后的路径，`split('/').last` 得到解码后的文件名

   **测试文件位置：`test/features/browser/bug_15_repro_test.dart`**

---

## §4 不变量

- **[BUG-15-INV1]** 音频识别基于文件系统真实名（href 末段），不基于显示标签
  证据：`nas_file.dart:117-118`（修复目标）

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-15-S1           # href 判定音频
BUG-15-INV1         # 真实名判定
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-15-S1 | 夹具 displayname 全部带扩展名 | 补 displayname 无扩展名但 href 有扩展名的用例 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---------|----------|
| BUG-15-S1 | `test/features/browser/bug_15_repro_test.dart` |
| BUG-15-INV1 | `test/features/browser/bug_15_repro_test.dart`（href 判定一致性用例） |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | 文件列表过滤 | displayname 无扩展名 | 文件不消失，分类正确 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-15 spec（基于 cr-20260724-0110.md MDL2）
