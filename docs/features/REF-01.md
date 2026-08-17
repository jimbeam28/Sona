# REF-01 — listDirectory 对服务器返回的绝对 URL href 正确相对化（含根挂载）

## §0 头部元数据

```yaml
id: REF-01
name: listDirectory 绝对 URL href 相对化（含根挂载）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/core/network/webdav_client.dart
  - lib/shared/webdav_paths.dart
  - lib/shared/models/nas_file.dart
cross_module_impacts: [BRW, PLY, PLT]   # browser / player / playlist(添加曲目浏览器)
manual_qa_required: false               # 纯 HTTP 层逻辑，MockClient 全可测，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0801-core-shared.md` D1（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D1. listDirectory 相对化不处理服务器返回的绝对 URL href（含 scheme://host），根挂载时完全不相对化
> - 类型 / 严重度 / 维度：DESIGN / Info / 正确性
> - 证据：`lib/core/network/webdav_client.dart:360-366`（`decodedBase = basePath.isEmpty ? '' : Uri.decodeFull(basePath)`——根挂载时跳过 relativise）与 `webdav_client.dart:436-454`（`_relativisePath` 仅剥离 `decodedBase` 路径前缀，`p.startsWith('$decodedBase/')` 对 `http://host:5005/dav/music/` 形态的 href 不匹配，整段 URL 会成为 NasFile.path）。
> - 取舍分析：现测试全部使用相对 href（webdav_client_test.dart、bug_13_repro_test.dart），对返回绝对 href 的服务器（如 Nextcloud/ownCloud 系）行为未定义——路径会带 `http://host:5005/` 前缀进入导航/播放拼 URL 链路。目标 NAS（自建 dav）可能不返回绝对 href，故不列 BUG；是否支持绝对 href 服务器请用户裁决，若支持则 relativise 需先剥 authority。
> - 修复建议：确定目标服务器形态后，要么在 `_relativisePath` 前先 `Uri.parse(href)` 剥掉 scheme+authority，要么在文档/需求层面明确不支持并给出校验提示。

用户裁决：**支持绝对 href 服务器**——设计新行为：绝对 URL href 也正确相对化。

### 1.1 这一功能干什么（一句话）

让 `listDirectory` 把服务器返回的"完整网址"（`http://主机:端口/路径/...`）形式的目录条目正确转成相对连接根的路径，与"相对路径"形式的条目行为一致——这样 Nextcloud/ownCloud 系服务器（习惯返回绝对 href）也能正常浏览与播放。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 连接一台返回"完整网址"地址的服务器（如 Nextcloud 系），打开文件夹 | 看到的是正常文件名，不是带着 `http://...` 前缀的乱路径；点进子文件夹、点播歌曲都正常 |
| U2 | 把服务器根目录作为挂载点（基础路径为 `/`），服务器返回完整网址形式的条目 | 子文件夹/文件路径不带服务器地址前缀，浏览与播放正常 |
| U3 | 目录条目里混有指向**其它服务器**的链接 | 这类条目不会被误当成自己 NAS 上的文件路径拼接出错误播放地址——保持原样、不影响其它条目 |
| U4 | 原来能正常用的服务器（返回相对路径形式） | 行为与修复前完全一致，不受影响 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core | `lib/core/network/webdav_client.dart` | 493 | WebDAV 网络层：listDirectory + `_relativisePath`（436-454）+ `_parsePropfindResponse`（395-428） |
| Shared | `lib/shared/webdav_paths.dart` | 143 | `webDavEffectiveBaseUrl`（66-70）/ `normalizeStoredPath`（133-142）——base 路径约定唯一源（NET1） |
| Shared | `lib/shared/models/nas_file.dart` | 229 | NasFile.fromProps（89-141）：href URL 解码 + 去尾斜杠 + 分类 |
| Provider | `lib/features/browser/browser_provider.dart` | 258 | directoryContentsProvider（84-129）：传 effective base URL + 过滤自引用 |
| Provider | `lib/features/playlist/widgets/add_tracks_browser.dart` | — | 播放单"添加曲目"浏览器：同 listDirectory 消费链 |
| 测试 | `test/core/bug_13_repro_test.dart` | 268 | NET1-2（188-208）：相对 href + 非根挂载的剥离锚定 |
| 测试 | `test/core/network/webdav_client_test.dart` | 135 | MockClient 网络层锚定（href 均为相对形态） |

### 2.2 关键 Provider 表

本功能不涉 Riverpod Provider（纯 core 网络层行为），跳过。

### 2.3 状态机图

本功能无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-01-S1]** 相对 href + 非根挂载：剥连接根前缀，自引用归一为 `/`
  ```
  Given url=http://nas.example.com:5005/dav（effective base，path 段=/dav），
      PROPFIND 返回 href `/dav/music/` 与 `/dav/`
  When listDirectory(path: '/')
  Then music 目录 path == '/music'（剥掉 /dav 前缀）
  And 自引用 /dav 归一为 '/'
  ```
  Code evidence:
  - `lib/core/network/webdav_client.dart:363-366`（`decodedBase = Uri.decodeFull(basePath)` 后 `parsed.map((f) => _relativisePath(f, decodedBase))`）
  - `lib/core/network/webdav_client.dart:439-445`（`p == decodedBase → '/'`；`p.startsWith('$decodedBase/') → substring`）
  - 锚定测试：`test/core/bug_13_repro_test.dart:188-208`（NET1-2）

- **[REF-01-S2]** 根挂载（连接根为 `/`）：整体跳过 relativise，条目原样返回
  ```
  Given effective base URL path 段为空（如 http://nas.example.com:5005/ 或
      http://nas.example.com:5005），basePath 变量 == ''
  When listDirectory 解析响应
  Then decodedBase == '' → result = parsed 原样（不 map、不剥任何前缀）
  ```
  Code evidence: `lib/core/network/webdav_client.dart:363-366`
  （`final decodedBase = basePath.isEmpty ? '' : Uri.decodeFull(basePath);` + `decodedBase.isEmpty ? parsed : parsed.map(...)`）
  测试锚定缺口：现有测试（bug_13_repro_test / webdav_client_test）只覆盖非根挂载（cr-0801 T3），本场景零锚定。

- **[REF-01-S3]** 绝对 URL href（含 scheme://host）不被相对化，整段 URL 成为 NasFile.path
  ```
  Given base 段=/dav，PROPFIND 返回 href `http://nas.example.com:5005/dav/music/`
  When listDirectory 解析响应并 relativise
  Then NasFile.fromProps 先解码去尾斜杠 → p == 'http://nas.example.com:5005/dav/music'
  And _relativisePath: p == decodedBase('/dav')? 否；p.startsWith('/dav/')? 否（以 http: 开头）
      → else 分支 rel = p 原样
  And 返回 path == 'http://nas.example.com:5005/dav/music'（整段 URL 泄漏进导航/播放链路）
  ```
  Code evidence:
  - `lib/core/network/webdav_client.dart:441-445`（`else { rel = p; }`——绝对 URL 不匹配任何前缀分支）
  - `lib/shared/models/nas_file.dart:96-104`（href 先 `Uri.decodeFull` + 去尾斜杠，绝对 URL 形态保留）
  - 下游后果链：`browser_provider.dart:118-123` 的自引用过滤（`e.path == path` 等比较）失效 + 导航/播放经 `audio_source_builder.dart:92-103`（buildUriWithBasePath 按 `/` 切段，`http:`、`host:5005` 会变成路径段）拼出错误 URL。

### 3.2 修改方案（status: new）

设计裁决（用户裁决"支持绝对 href 服务器"）：

**authority 判定规则**：`href` 为绝对 URL（`Uri.parse` 后 scheme 非空且 host 非空）时，比较其 host 与**请求目标 URL**（listDirectory 的 `targetUri`）的 host——**host 相同（大小写不敏感）即视为本服务器**；端口与 scheme 不参与判定（服务器可能经反代以不同端口/不同 scheme 自报，下游重拼 URL 始终用连接 URL 的端口与 scheme，剥掉 authority 后拼接仍然正确）。

| 边界情况 | 裁决 |
|---|---|
| href 为相对/根相对路径（无 scheme，如 `/music/x.mp3`） | 非绝对 URL → 不做 authority 处理，走现有 base 剥离逻辑（行为与修复前一致） |
| 绝对 URL 且 host 与本连接相同（如 `http://nas:5005/dav/music`，请求 `http://nas:5005/dav`） | 剥 scheme+authority → `/dav/music` → 继续走现有 base 剥离 → `/music` |
| 绝对 URL 且 host 与请求不同（如 `http://other:5005/dav/`） | **不剥、原样返回**（外部引用不吞掉，REF-01-S6） |
| 绝对 URL 剥掉 authority 后 path 为空（根自引用 `http://nas:5005`） | 归一为 `/`（REF-01-S7） |
| 绝对 URL 同 host 但路径不在 base 下（如 base=/dav，href `http://nas:5005/other/x.mp3`） | 剥 authority 后 `/other/x.mp3` 不匹配 base 前缀 → 防御分支原样返回（正确数据不被损坏） |
| scheme-relative `//host:5005/dav/`（无 scheme） | `Uri.parse` 后 scheme 空 → 不视为绝对 URL → 原样返回（WebDAV 响应无此形态，防御分支） |
| host 形态差异（IPv6 `[::1]`、尾点域名、大小写） | 不做特判，按 `Uri.parse` 规范化后的 host 字符串（小写化后）比较 |
| href 含 userinfo（`http://user:pass@nas/...`） | 剥 authority 包含 userinfo 一起剥掉（Uri.parse 的 path 不含 userinfo）；下游拼接不会带上凭证 |

- **[REF-01-S4]** 绝对 URL href（host 相同）→ 剥 scheme+authority 后走 base 剥离 （status: new）
  ```
  Given url=http://nas.example.com:5005/dav（targetUri host=nas.example.com），
      PROPFIND 返回 href `http://nas.example.com:5005/dav/music/`
  When listDirectory 解析响应并 relativise
  Then 识别为绝对 URL 且 host 相同 → 剥 authority → 路径形态 '/dav/music'
  And 走现有 base 剥离（'/dav/' 前缀）→ 返回 path == '/music'
  否定断言:
    - 返回 path 不得以 'http://' 或 'https://' 开头（scheme/authority 不得泄漏进 NasFile.path）
    - 相对 href（如 `/dav/a.mp3`）的处理结果不得改变（S1 行为保持）
    - 非本服务器 host 的绝对 URL 不得被剥掉 authority（保留原样）
  ```
  **修改点 1**：`lib/core/network/webdav_client.dart:363-366` —— 删除"根挂载跳过 relativise"与"仅非空 base 才 map"的双分支，改为无条件统一 map：
  ```dart
  // 修改前（363-366 行）:
  final decodedBase = basePath.isEmpty ? '' : Uri.decodeFull(basePath);
  final result = decodedBase.isEmpty
      ? parsed
      : parsed.map((f) => _relativisePath(f, decodedBase)).toList();
  // 修改后:
  final decodedBase = basePath.isEmpty ? '' : Uri.decodeFull(basePath);
  // REF-01: 无条件 relativise —— 根挂载时绝对 URL href 也要剥 authority
  // （cr-20260816-0801 D1）。targetUri 的 authority 是"本服务器"判定基准。
  final result =
      parsed.map((f) => _relativisePath(f, decodedBase, targetUri)).toList();
  ```
  **修改点 2**：`lib/core/network/webdav_client.dart:436-454` —— `_relativisePath` 增加第三参 `Uri requestUri`，前置 authority 剥离步骤：
  ```dart
  // 修改前（436 行签名）:
  static NasFile _relativisePath(NasFile file, String decodedBase) {
  // 修改后:
  static NasFile _relativisePath(
      NasFile file, String decodedBase, Uri requestUri) {
    final p = file.path;
    // REF-01: 绝对 URL href 先剥 authority（host 同本连接才剥），再走既有前缀剥离。
    final pathOnly = _stripHrefAuthority(p, requestUri);
    final base = pathOnly ?? p; // null → 非绝对 URL 或外部 host，保持原样
    String rel;
    if (base == decodedBase) {
      rel = '/';
    } else if (base.startsWith('$decodedBase/')) {
      rel = base.substring(decodedBase.length);
    } else {
      rel = base;
    }
    return NasFile(
      name: file.name,
      path: rel,
      isDirectory: file.isDirectory,
      size: file.size,
      modifiedAt: file.modifiedAt,
      audioType: file.audioType,
    );
  }
  ```
  **修改点 3**：`lib/core/network/webdav_client.dart` 新增私有静态纯函数（放在 `_relativisePath` 之后、`_extractXmlContent` 之前）：
  ```dart
  /// REF-01: 返回 [hrefPath] 的路径形态（剥掉 scheme+authority），当且仅当
  /// [hrefPath] 是绝对 URL（scheme 非空且 host 非空）且其 host 与 [requestUri]
  /// 的 host 相同（大小写不敏感）。端口与 scheme 不参与判定（反代/端口改写
  /// 场景下服务器可能以不同端口/scheme 自报，下游重拼 URL 用连接 URL 的
  /// 端口与 scheme，剥掉 authority 后拼接仍正确）。非绝对 URL 或 host 不同
  /// 返回 null —— 调用方保持原样（外部引用不被相对化吞掉）。
  /// 剥后 path 为空（根自引用 `http://host:5005`）→ 归一为 '/'。
  static String? _stripHrefAuthority(String hrefPath, Uri requestUri) {
    final uri = Uri.tryParse(hrefPath);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    if (uri.host.toLowerCase() != requestUri.host.toLowerCase()) return null;
    final path = uri.path;
    return path.isEmpty ? '/' : path;
  }
  ```

- **[REF-01-S5]** 根挂载（base 段空）+ 绝对 URL href（host 相同）→ 剥 authority，路径保留；根相对 href 不被改动 （status: new）
  ```
  Given effective base URL 为 http://nas.example.com:5005/（basePath 变量 == ''），
      PROPFIND 返回 href `http://nas.example.com:5005/music/` 与 `/song.mp3`
  When listDirectory 解析响应并 relativise
  Then `http://.../music` 剥 authority → '/music'（根挂载下根相对即连接根相对，保留）
  And 根相对 href '/song.mp3' 原样返回（非绝对 URL，不触碰）
  否定断言:
    - 根相对 href（'/song.mp3'、'/'）不得被改动（S2 的相对行为保持）
    - 根挂载下任何条目的 path 不得以 'http://' 或 'https://' 开头
  ```
  Code evidence（修改点）: `lib/core/network/webdav_client.dart:363-366`（修改后无条件 map）+ `_stripHrefAuthority`（修改点 3）。

- **[REF-01-S6]** 绝对 URL href（host 与请求不同）→ 原样返回，不剥 authority （status: new）
  ```
  Given 请求 targetUri host=nas.example.com，PROPFIND 返回 href `http://other-nas:5005/dav/music/`
  When listDirectory 解析响应并 relativise
  Then _stripHrefAuthority 判定 host 不同 → null → base = 原 p
  And 返回 path == 'http://other-nas:5005/dav/music'（整段保留，防御分支）
  否定断言:
    - 不得抛出任何异常（外部引用是合法输入，走防御分支）
    - 不得产生部分剥离（不得剥成 '/dav/music' 之类的中间形态）
    - 同目录下 host 匹配的条目仍正常相对化（互不影响）
  ```
  Code evidence（修改点）: `lib/core/network/webdav_client.dart:441-445`（修改后 `else { rel = base; }` 保留原样）+ `_stripHrefAuthority` 的 host 判定。

- **[REF-01-S7]** 绝对 URL 根自引用（剥后 path 空）→ 归一为 `/` （status: new）
  ```
  Given 根挂载（basePath == ''），PROPFIND 返回 href `http://nas.example.com:5005/`
  When listDirectory 解析响应并 relativise
  Then fromProps 去尾斜杠 → p == 'http://nas.example.com:5005'（path 段为空）
  And _stripHrefAuthority 剥 authority → path '' → 归一为 '/'
  And base '/' 剥离逻辑 → 返回 path == '/'
  否定断言:
    - 返回不得为空字符串 ''
    - 返回不得带 authority（'http://nas.example.com:5005' 不得泄漏）
  ```
  Code evidence（修改点）: `_stripHrefAuthority` 的 `path.isEmpty ? '/' : path` 分支。

---

## §4 不变量

- **[REF-01-INV1]** 对 host 匹配本连接的全部 href，listDirectory 返回的 NasFile.path 必为路径形态（不以 `scheme://` 开头）
  证据：`lib/core/network/webdav_client.dart:363-366`（修改后无条件 relativise）+ `_stripHrefAuthority`（剥 authority 后 path 必为 `/` 开头形态或 `/`）。

- **[REF-01-INV2]** 相对 href（无 scheme）的处理结果与修复前逐字节一致
  证据：`lib/core/network/webdav_client.dart:439-445`（`p == decodedBase` / `startsWith('$decodedBase/')` / else 三分支原样保留，仅新增前置 authority 步骤——非绝对 URL 输入时 `_stripHrefAuthority` 返回 null、走原逻辑）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/core/bug_13_repro_test.dart:188-208（NET1-2） | REF-01-S1 | 相对 href + 非根挂载；修复后必须保持绿（回归护栏） |
| test/core/network/webdav_client_test.dart | — | href 均为相对形态；不直接覆盖 REF-01 新行为 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-01-S1 … S7        # Scenario（S1~S3 现状锚定，S4~S7 修复目标）
REF-01-INV1 … INV2    # 不变量
REF-01-ALG1           # 算法样例（见 §6）
```

dev-exe 要求：S1 由既有 bug_13_repro_test.dart 覆盖；S2 现状、S3 缺陷态、S4~S7 与 INV1/2、ALG1 由 §5.4 门禁测试文件覆盖。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-01-S2（根挂载相对 href 原样） | 零锚定（cr-0801 T3） | §5.4 门禁文件补用例 |
| REF-01-S3（缺陷态） | 零锚定 | §5.4 门禁文件按现有行为锚定缺陷态（防回归漂移） |
| REF-01-S4~S7 / INV1/2 / ALG1 | 新行为 | §5.4 门禁文件 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/core/network/ref_01_relativise_test.dart`（使用 MockClient 注入真实 WebDavClient，与 bug_13_repro_test 同模式；命名已 grep 核实与既有文件无冲突）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/core/network/ref_01_relativise_test.dart | REF-01-S2、S3、S4、S5、S6、S7、REF-01-INV1、REF-01-INV2、REF-01-ALG1 | 门禁：dev-exe 修复后必须 PASS（cov-gate 内） |
| test/core/bug_13_repro_test.dart | REF-01-S1 | 既有文件，断言不变，修复后保持绿 |

---

## §6 算法样例

```
ALG [REF-01-ALG1-stripHrefAuthority]:
  输入: '/music/a.mp3', Uri.parse('http://nas:5005/dav')
      → 期望: null（非绝对 URL → 走原剥离逻辑）                    # 主流程
  输入: 'http://nas:5005/dav/music', Uri.parse('http://nas:5005/dav')
      → 期望: '/dav/music'（同 host 剥 authority，再走 base 剥离）  # 主流程
  输入: 'HTTP://NAS:5005/dav/music', Uri.parse('http://nas:5005/dav')
      → 期望: '/dav/music'（scheme/host 大小写不敏感，Uri.parse 已规范化）  # 边界
  输入: 'https://nas:5005/dav/music', Uri.parse('http://nas:5005/dav')
      → 期望: '/dav/music'（scheme 不同仍剥 —— 端口/scheme 不参与判定）  # 边界
  输入: 'http://other:5005/dav/music', Uri.parse('http://nas:5005/dav')
      → 期望: null（host 不同 → 原样返回，外部引用不被吞）           # 边界
  输入: 'http://nas:5005', Uri.parse('http://nas:5005/dav')
      → 期望: '/'（剥后 path 空 → 根自引用归一）                     # 边界
  输入: '//nas:5005/dav/music', Uri.parse('http://nas:5005/dav')
      → 期望: null（scheme-relative，scheme 空 → 非绝对 URL）        # 异常/防御
  输入: 'not a url at all', Uri.parse('http://nas:5005/dav')
      → 期望: null（Uri.tryParse 失败或 scheme/host 空）              # 异常/防御
```

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/core/network/webdav_client.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Browser（browser_provider.dart:84-129） | directoryContentsProvider 调 listDirectory + 自引用过滤（118-123） | 相对 href 行为不变；绝对 URL href 从此返回相对路径，过滤逻辑的字符串比较恢复正常 | 既有 brw_* / bug_13_repro_test 全绿；ref_01_relativise_test.dart PASS |
| Playlist 添加曲目（add_tracks_browser.dart） | 同 listDirectory 消费链 | 同上 | 既有 playlist 添加曲目测试全绿 |
| Player（player_provider / playback_orchestrator / audio_source_builder.dart:82-104） | buildUriWithBasePath 按 `/` 切段拼播放 URL | 修复后 NasFile.path 不再带 `http:/` 段 | 既有 player 测试全绿（filePath 相对形态假设不变） |
| Browser UI（browser_screen.dart） | 消费相对路径展示/导航 | 无直接改动 | 既有测试全绿 |
| Connection（connection_provider / connection_screen / connection_edit_screen / connection_validator） | 仅 validate 链路（webdav_client.dart:185-283），本修改不触碰 validate | 无 | 既有 connection 测试全绿 |
| normalizeStoredPath（webdav_paths.dart:115-116 注释声称"语义 identical to _relativisePath"） | 持久化路径归一化 | 存储数据无绝对 URL 形态生产者（pre-NET1 绝对 = 路径形态，webdav_paths.dart:101-106 注释）；修复后"绝对 URL 输入"上两者行为不再一致（normalizeStoredPath 不剥 authority）——**不改其语义** | 允许 dev-exe 仅更新 webdav_paths.dart:115-116 注释措辞（注明仅路径形态输入才与 `_relativisePath` 一致），严禁改函数体 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本需求为纯 HTTP 响应解析层行为，不触及 P1~P17 任何条目（不涉 audio_service / 监听器生命周期 / Provider 状态 / 平台通道 / 超时分层——listDirectory 的 5s 超时（P17 独立网络超时段）不在本次修改范围内）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 真实 Nextcloud/ownCloud 系服务器返回的绝对 href 形态（scheme/端口/host 自报方式）与 fixture 假设不符 | 单测 fixture 覆盖三种权威形态（同 host 绝对 URL / 根挂载绝对 URL / 异 host 绝对 URL），行为全在 MockClient 层可验 | 无（行为全部可在 `flutter test` 中验证，不涉平台原生） |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-01": {
  "spec_file": "docs/features/REF-01.md",
  "spec_anchored_files": [
    "lib/core/network/webdav_client.dart",
    "lib/shared/webdav_paths.dart",
    "lib/shared/models/nas_file.dart"
  ],
  "scenarios": ["REF-01-S1", "REF-01-S2", "REF-01-S3", "REF-01-S4", "REF-01-S5", "REF-01-S6", "REF-01-S7"],
  "invariants": ["REF-01-INV1", "REF-01-INV2"],
  "algorithms": ["REF-01-ALG1-stripHrefAuthority"],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
