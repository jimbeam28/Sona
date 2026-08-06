# REF-02 — 契约层真启用（CTR2-CTR6 + SVC6 + PRG5）

> 来源：`docs/cr/cr-20260724-0110.md` CTR2-CTR6 + SVC6 + PRG5
> 用户裁决 2026-07-24："真启用"

---

## §0 头部元数据

```yaml
id: REF-02
name: 契约层真启用（CTR2-CTR6 + SVC6 + PRG5）
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/contracts/audio_handler_contract.dart
  - lib/core/contracts/audio_player_contract.dart
  - lib/core/contracts/database_contract.dart
  - lib/core/contracts/storage_contract.dart
  - lib/core/services/audio_handler.dart
  - lib/features/progress/domain/progress_service.dart
  - lib/features/connection/connection_provider.dart
  - lib/features/progress/progress_provider.dart
  - lib/features/player/player_provider.dart
  - lib/features/playlist/playlist_provider.dart
cross_module_impacts: [CON, PLY, BRW, PRG, SET, TMR]
parent_feature: null
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md CTR2-CTR6 + SVC6 + PRG5。6 个 contract 接口已定义但从未被真正使用——所有 provider 注入具体类，所有 fake/mock 绕过接口。IAudioHandler 无反向实现声明且 import 了 feature 文件（反向依赖）。IProgressDao 表面含测试钩子。ProgressService 直接依赖 ProgressDao 具体类。用户裁决："真启用"——让 contract 成为实际依赖边界。

### 1.1 这一功能干什么（一句话）

使 contract 接口成为 provider 注入、fake/mock 实现的唯一依赖边界，消除"接口存在但无人使用"的死代码状态。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | Provider 类型签名 | 所有 DAO/storage/player provider 类型为对应 `I*` 接口 |
| U2 | Fake/mock 实现 | 所有 test fake 实现对应 `I*` 接口 |
| U3 | NasAudioHandler | 声明 `implements IAudioHandler` |
| U4 | ProgressService 构造函数 | 接受 `IProgressDao` 而非 `ProgressDao` |
| U5 | IAudioHandler contract | 无 feature 层 import；类型定义自包含 |
| U6 | 全部现有测试 | 仍通过（接口等价变换） |

---

## §2 已实现的功能骨架

### 2.1 Contract 接口现状

| 接口 | 文件:行 | 实现类 | Provider 类型 | 问题 |
|---|---|---|---|---|
| `IConnectionDao` | `database_contract.dart:17` | `ConnectionDao implements IConnectionDao` (`:19`) | `Provider<ConnectionDao>` (`connection_provider.dart:23`) | CTR4: provider 用具体类 |
| `IProgressDao` | `database_contract.dart:54` | `ProgressDao implements IProgressDao` (`:16`) | `Provider<ProgressDao>` (`progress_provider.dart:25`) | CTR4+CTR5: provider 用具体类 + rawInsert 泄漏到接口 |
| `IPlaylistDao` | `database_contract.dart:97` | `PlaylistDao implements IPlaylistDao` (`:9`) | `Provider<PlaylistDao>` (`playlist_provider.dart:19`) | CTR4: provider 用具体类 |
| `ISecureStorage` | `storage_contract.dart:13` | 无（直接用 FlutterSecureStorage） | `Provider<FlutterSecureStorage>` (`connection_provider.dart:29`) | CTR4: provider 用具体类 |
| `IAudioPlayer` | `audio_player_contract.dart:17` | 无（直接用 AudioPlayer） | `Provider<AudioPlayer>` (`player_provider.dart:46`) | CTR4: provider 用具体类 |
| `IAudioHandler` | `audio_handler_contract.dart:18` | 无（NasAudioHandler 无 implements 声明） | `Provider<NasAudioHandler?>` (`player_provider.dart:51`) | CTR2+CTR3+SVC6: 漂移+反向依赖+死契约 |

### 2.2 问题详解

| 编号 | 问题 | 证据 |
|---|---|---|
| CTR2 | IAudioHandler 成员与 NasAudioHandler 漂移 | `audio_handler_contract.dart:18-83` vs `audio_handler.dart:42-265`；NasAudioHandler 无 `implements IAudioHandler`；contract 有 `playbackStateStream`/`mediaItemStream` getter 但 NasAudioHandler 用 `playbackState`/`mediaItem`（BehaviorSubject） |
| CTR3 | audio_handler_contract 反向依赖 feature 层 | `audio_handler_contract.dart:10-11` import `../../features/player/background_playback.dart` 和 `../services/audio_handler.dart` |
| CTR4 | 6 个接口零消费者 | provider 全部用具体类类型（见 §2.1 表） |
| CTR5 | IProgressDao 表面含 rawInsert 测试钩子 | `database_contract.dart:67` — `rawInsert` 注释 "Useful for testing" |
| CTR6 | IConnectionDao.delete 缺异常文档 | `database_contract.dart:43` — 无 `LastConnectionException` 文档 |
| SVC6 | IAudioHandler 死契约 | 无 implementer、无 consumer |
| PRG5 | ProgressService 绕过 IProgressDao | `progress_service.dart:14` import `progress_dao.dart`、`:41` `final ProgressDao _dao` |

---

## §3 行为规约

### 3.1 CTR4 — Provider 类型改为接口

- **[REF-02-S1]** connectionDaoProvider 类型为 IConnectionDao (`status: new`)
  ```
  Given connectionDaoProvider 在 Riverpod 容器中
  When  静态分析其类型签名
  Then  类型为 Provider<IConnectionDao>
  否定断言:
    - 不在 provider 类型签名中出现 ConnectionDao 具体类
    - 不改变 ConnectionDao 实例的创建方式（仍 `ConnectionDao()`）
    - 不改变任何消费 connectionDaoProvider 的代码行为
  ```
  Code evidence: `lib/features/connection/connection_provider.dart:23`

  **修改指令 — `lib/features/connection/connection_provider.dart`**

  位置：`:23`
  当前：`final connectionDaoProvider = Provider<ConnectionDao>((ref) => ConnectionDao());`
  改为：`final connectionDaoProvider = Provider<IConnectionDao>((ref) => ConnectionDao());`
  添加 import：`import '../../core/contracts/database_contract.dart';`

- **[REF-02-S2]** progressDaoProvider 类型为 IProgressDao (`status: new`)
  ```
  Given progressDaoProvider 在 Riverpod 容器中
  When  静态分析其类型签名
  Then  类型为 Provider<IProgressDao>
  否定断言:
    - 不在 provider 类型签名中出现 ProgressDao 具体类
    - 不改变 ProgressDao 实例的创建方式
    - 不改变任何消费 progressDaoProvider 的代码行为
  ```
  Code evidence: `lib/features/progress/progress_provider.dart:25`

  **修改指令 — `lib/features/progress/progress_provider.dart`**

  位置：`:25`
  当前：`final progressDaoProvider = Provider<ProgressDao>((ref) => ProgressDao());`
  改为：`final progressDaoProvider = Provider<IProgressDao>((ref) => ProgressDao());`
  添加 import：`import '../../core/contracts/database_contract.dart';`

- **[REF-02-S3]** playlistDaoProvider 类型为 IPlaylistDao (`status: new`)
  ```
  Given playlistDaoProvider 在 Riverpod 容器中
  When  静态分析其类型签名
  Then  类型为 Provider<IPlaylistDao>
  否定断言:
    - 不在 provider 类型签名中出现 PlaylistDao 具体类
    - 不改变 PlaylistDao 实例的创建方式
    - 不改变任何消费 playlistDaoProvider 的代码行为
  ```
  Code evidence: `lib/features/playlist/playlist_provider.dart:19`

  **修改指令 — `lib/features/playlist/playlist_provider.dart`**

  位置：`:19`
  当前：`final playlistDaoProvider = Provider<PlaylistDao>((ref) => PlaylistDao());`
  改为：`final playlistDaoProvider = Provider<IPlaylistDao>((ref) => PlaylistDao());`

- **[REF-02-S4]** secureStorageProvider 类型为 ISecureStorage (`status: new`)
  ```
  Given secureStorageProvider 在 Riverpod 容器中
  When  静态分析其类型签名
  Then  类型为 Provider<ISecureStorage>
  否定断言:
    - 不在 provider 类型签名中出现 FlutterSecureStorage 具体类
    - 不改变运行时实例的实际类型（仍为 FlutterSecureStorage 或其适配器）
    - 不改变 safeStorageRead/safeStorageWrite 的行为
  ```
  Code evidence: `lib/features/connection/connection_provider.dart:28-29`

  **修改指令 — `lib/features/connection/connection_provider.dart`**

  位置：`:28-29`
  当前：
  ```dart
  final secureStorageProvider =
      Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());
  ```
  改为：
  ```dart
  final secureStorageProvider =
      Provider<ISecureStorage>((ref) => FlutterSecureStorageAdapter());
  ```
  需新增 `FlutterSecureStorageAdapter implements ISecureStorage` 适配器。

- **[REF-02-S5]** FakeSecureStorage 实现 ISecureStorage (`status: new`)
  ```
  Given FakeSecureStorage 在 test/helpers/
  When  静态分析
  Then  声明 implements ISecureStorage
  否定断言:
    - 不继承 FlutterSecureStorage（当前 `extends FlutterSecureStorage`，fake_secure_storage.dart:9）
    - 不改变 read/write/delete 的 in-memory 行为
  ```
  Code evidence: `test/helpers/fake_secure_storage.dart:9`（`class FakeSecureStorage extends FlutterSecureStorage`）

  **修改指令 — `test/helpers/fake_secure_storage.dart`**

  位置：`:9`
  当前：`class FakeSecureStorage extends FlutterSecureStorage {`
  改为：`class FakeSecureStorage implements ISecureStorage {`
  移除 FlutterSecureStorage 平台方法签名（IOSOptions 等），改为 ISecureStorage 签名。

### 3.2 CTR2+CTR3+SVC6 — IAudioHandler 真启用

- **[REF-02-S6]** audio_handler_contract 无 feature 层反向 import (`status: new`)
  ```
  Given audio_handler_contract.dart 的 import 列表
  When  静态分析
  Then  不包含 ../../features/ 路径的 import
  And   不包含 ../services/audio_handler.dart 的 import
  否定断言:
    - 不在 contract 层出现 feature 层 import（当前 :10 `../../features/player/background_playback.dart`、`:11` `../services/audio_handler.dart`）
    - 不改变 IAudioHandler 接口的方法签名语义
  ```
  Code evidence: `lib/core/contracts/audio_handler_contract.dart:10-11`

  **修改指令 — `lib/core/contracts/audio_handler_contract.dart`**

  策略：
  1. 把 `BackgroundPlaybackConfig`、`AudioFocusState`、`NextTrackCallback`、`PreviousTrackCallback`、`ConfigChangeCallback` 等共享类型移到 `core/contracts/` 或 `shared/` 下，消除反向 import。
  2. `BackgroundPlaybackConfig` 和相关枚举来自 `features/player/background_playback.dart`——需在 `core/contracts/` 下创建 `background_playback_contract.dart` 或把这些类型移到 `shared/models/`。
  3. Callback typedefs（`NextTrackCallback` 等）来自 `core/services/audio_handler.dart`——需移到 contract 文件内。

- **[REF-02-S7]** NasAudioHandler implements IAudioHandler (`status: new`)
  ```
  Given NasAudioHandler 类声明
  When  静态分析
  Then  声明 implements IAudioHandler
  否定断言:
    - 不在 IAudioHandler 接口中保留 NasAudioHandler 没有的成员
    - 不改变 NasAudioHandler 的运行时行为
    - 不删除 IAudioHandler 中 NasAudioHandler 已实现的成员
  ```
  Code evidence: `lib/core/services/audio_handler.dart:42`（`class NasAudioHandler extends BaseAudioHandler`，无 `implements IAudioHandler`）

  **修改指令 — `lib/core/services/audio_handler.dart`**

  位置：`:42`
  当前：`class NasAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {`
  改为：`class NasAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler implements IAudioHandler {`

  需确保 NasAudioHandler 的公开方法与 IAudioHandler 声明一致：
  - `playbackStateStream` → IAudioHandler 声明了此 getter（`:26`），NasAudioHandler 通过 `BaseAudioHandler.playbackState`（BehaviorSubject）暴露。需添加 `Stream<PlaybackState> get playbackStateStream => playbackState;`
  - `mediaItemStream` → 同理，需添加 `Stream<MediaItem?> get mediaItemStream => mediaItem;`

- **[REF-02-S8]** audioHandlerProvider 类型为 IAudioHandler (`status: new`)
  ```
  Given audioHandlerProvider 在 Riverpod 容器中
  When  静态分析其类型签名
  Then  类型为 Provider<IAudioHandler?>
  否定断言:
    - 不在 provider 类型签名中出现 NasAudioHandler 具体类
    - 不改变 NasAudioHandler 实例的创建方式
    - 不改变任何消费 audioHandlerProvider 的代码行为
  ```
  Code evidence: `lib/features/player/player_provider.dart:51`

  **修改指令 — `lib/features/player/player_provider.dart`**

  位置：`:51`
  当前：`final audioHandlerProvider = Provider<NasAudioHandler?>((ref) => null);`
  改为：`final audioHandlerProvider = Provider<IAudioHandler?>((ref) => null);`

### 3.3 CTR5 — IProgressDao 表面最小化

- **[REF-02-S9]** IProgressDao 不含 rawInsert (`status: new`)
  ```
  Given IProgressDao 接口定义
  When  静态分析
  Then  不包含 rawInsert 方法
  否定断言:
    - 不在 contract 层出现测试专用方法（当前 database_contract.dart:67 `Future<void> rawInsert(PlayProgress progress)`）
    - 不在生产 DAO 中保留仅测试使用的方法（progress_dao.dart:78-83）
    - 不改变 upsert/find/delete 等生产方法的行为
  ```
  Code evidence: `lib/core/contracts/database_contract.dart:67`（rawInsert）、`lib/core/database/dao/progress_dao.dart:78-83`（rawInsert 实现）

  **修改指令**

  1. 从 `database_contract.dart:67` 删除 `Future<void> rawInsert(PlayProgress progress);`
  2. 从 `progress_dao.dart:78-83` 删除 `rawInsert` 方法
  3. 在 `test/helpers/test_database.dart`（或新文件 `test/helpers/progress_dao_test_helper.dart`）添加测试用 extension：
  ```dart
  extension ProgressDaoTestHelper on ProgressDao {
    Future<void> rawInsertForTest(PlayProgress progress) async { ... }
  }
  ```

### 3.4 CTR6 — IConnectionDao.delete 异常文档

- **[REF-02-S10]** IConnectionDao.delete 文档化 LastConnectionException (`status: new`)
  ```
  Given IConnectionDao.delete 方法的 dartdoc
  When  阅读文档
  Then  明确说明抛出 LastConnectionException 的条件
  否定断言:
    - 不在 delete 方法签名变更后遗漏文档更新
    - 不改变 ConnectionDao.delete 的运行时行为
  ```
  Code evidence: `lib/core/contracts/database_contract.dart:40-43`（delete 方法无异常文档）

  **修改指令 — `lib/core/contracts/database_contract.dart`**

  位置：`:40-43`
  当前：
  ```dart
  /// Deletes the connection with [id] and cascades to related records.
  ///
  /// Returns `true` if the deleted connection was the active one.
  Future<bool> delete(int id);
  ```
  改为：
  ```dart
  /// Deletes the connection with [id] and cascades to related records.
  ///
  /// Returns `true` if the deleted connection was the active one.
  ///
  /// Throws [LastConnectionException] when only one connection remains.
  Future<bool> delete(int id);
  ```

### 3.5 PRG5 — ProgressService 注入 IProgressDao

- **[REF-02-S11]** ProgressService 接受 IProgressDao (`status: new`)
  ```
  Given ProgressService 构造函数
  When  静态分析
  Then  参数类型为 IProgressDao（而非 ProgressDao）
  否定断言:
    - 不在 progress_service.dart import 中出现 progress_dao.dart（当前 :14）
    - 不在 ProgressService 中出现 ProgressDao 具体类型引用（当前 :41 `final ProgressDao _dao`）
    - 不改变 saveProgress/getProgress/clearProgress 的外部行为
  ```
  Code evidence: `lib/features/progress/domain/progress_service.dart:14`（import）、`:41`（`final ProgressDao _dao`）、`:43`（构造函数）

  **修改指令 — `lib/features/progress/domain/progress_service.dart`**

  位置：`:14`
  当前：`import '../../../core/database/dao/progress_dao.dart';`
  改为：`import '../../../core/contracts/database_contract.dart';`

  位置：`:41`
  当前：`final ProgressDao _dao;`
  改为：`final IProgressDao _dao;`

  位置：`:43`
  当前：`ProgressService({ProgressDao? dao}) : _dao = dao ?? ProgressDao();`
  改为：`ProgressService({required IProgressDao dao}) : _dao = dao;`

  注意：移除默认值 `ProgressDao()` 是因为 domain 层不应知道具体 DAO 实例化。Provider 层负责注入。

  **调用方适配：**

  `progress_provider.dart:33-34`
  当前：
  ```dart
  final progressServiceProvider = Provider<ProgressService>((ref) {
    return ProgressService(dao: ref.read(progressDaoProvider));
  });
  ```
  无需修改（`progressDaoProvider` 改为返回 `IProgressDao` 后自动适配）。

---

## §4 不变量

- **[REF-02-INV1]** 所有 DAO provider 类型为对应 `I*` 接口
  证据：`connectionDaoProvider: Provider<IConnectionDao>`、`progressDaoProvider: Provider<IProgressDao>`、`playlistDaoProvider: Provider<IPlaylistDao>`

- **[REF-02-INV2]** 所有 test fake 实现对应 `I*` 接口
  证据：`FakeSecureStorage implements ISecureStorage`、`MockAudioPlayer implements IAudioPlayer`（或同时 implements AudioPlayer 和 IAudioPlayer）

- **[REF-02-INV3]** IAudioHandler contract 无 feature 层 import
  证据：`audio_handler_contract.dart` import 列表无 `../../features/` 路径

- **[REF-02-INV4]** NasAudioHandler 声明 implements IAudioHandler
  证据：`audio_handler.dart:42` 类声明含 `implements IAudioHandler`

- **[REF-02-INV5]** ProgressService 依赖 IProgressDao 接口
  证据：`progress_service.dart:14` import `database_contract.dart`、`:41` `final IProgressDao _dao`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/helpers/fake_secure_storage.dart` | FakeSecureStorage | 需改为 implements ISecureStorage |
| `test/helpers/mock_audio_player.dart` | MockAudioPlayer | 需同时 implements IAudioPlayer |
| `test/helpers/test_database.dart` | DB helpers | rawInsert 迁移到此 |
| `test/features/connection/` | CON 测试 | 适配 provider 类型变更 |
| `test/features/progress/` | PRG 测试 | 适配 ProgressService 构造变更 |
| `test/features/playlist/` | Playlist 测试 | 适配 provider 类型变更 |
| `test/features/player/` | PLY 测试 | 适配 audioHandlerProvider 类型变更 |

### 5.2 测试 ID 派生清单

```
REF-02-S1 … S11       # Scenario
REF-02-INV1 … INV5    # 不变量
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-02-S5 | FakeSecureStorage 改为 implements ISecureStorage | 验证所有使用 FakeSecureStorage 的测试仍通过 |
| REF-02-S7 | NasAudioHandler implements IAudioHandler | 编译时验证（implements 声明确保方法签名匹配） |
| REF-02-S9 | rawInsert 移出 contract | 验证引用 rawInsert 的测试改用 test helper extension |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| REF-02-S1 | `test/features/connection/con_01_test.dart`（connectionDaoProvider 类型适配） |
| REF-02-S2/S9 | `test/features/progress/prg_test.dart`（progressDaoProvider 类型适配 + rawInsert 迁移） |
| REF-02-S3 | `test/features/playlist/ply_09_test.dart`（playlistDaoProvider 类型适配） |
| REF-02-S4/S5 | `test/helpers/fake_secure_storage.dart`（implements ISecureStorage） |
| REF-02-S6/S7/S8 | `test/features/player/bug_05_handler_play_test.dart`（audioHandlerProvider 类型适配） |
| REF-02-S10 | `test/features/connection/ref_22_test.dart`（delete LastConnectionException 文档化锚定） |
| REF-02-S11 | `test/features/progress/ref_25_test.dart`（ProgressService 构造变更适配） |
| helpers | `test/helpers/test_database.dart`（rawInsertForTest extension 迁移至此） |
| helpers | `test/helpers/mock_audio_player.dart`（implements IAudioHandler 适配） |

---

## §6 算法样例

不适用——本重构为接口启用，无新算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| CON | connectionDaoProvider 类型变更 | 所有 connection 测试编译通过 |
| PLY | audioHandlerProvider 类型变更 | 所有 player 测试编译通过 |
| PRG | progressDaoProvider 类型 + ProgressService 构造变更 | 所有 progress 测试编译通过 |
| Playlist | playlistDaoProvider 类型变更 | 所有 playlist 测试编译通过 |
| SET | secureStorageProvider 类型变更 | settings 测试编译通过 |
| BRW | secureStorageProvider 消费 | browser 测试编译通过 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-02 spec（基于 cr-20260724-0110.md CTR2-CTR6 + SVC6 + PRG5）
- 2026-08-06: dev-plan 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；门禁文件按现有引用面锚定：con_01/prg_test/ply_09/bug_05_handler_play/ref_22/ref_25 + helpers 三件套
