# BUG-10 — 浏览器错误视图对非 WebDavException 暴露原始异常文本（与 BUG-23-S5 全局裁决相悖）

## §0 头部元数据

```yaml
id: BUG-10
name: 错误视图对非 WebDavException 暴露原始异常文本（应与 BUG-23-S5 对齐：固定文案 + 日志）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/browser/browser_screen.dart
cross_module_impacts: [BRW]
parent_feature: Browser
manual_qa_required: false      # 纯 UI 文案 + debugPrint 日志，全部可在 flutter test 验证
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0803-browser-home.md` F1（cr 复核已确认仍存在）：

> #### F1. 浏览器错误视图对非 WebDavException 暴露原始异常文本
> - 类型 / 严重度 / 维度：FRAGILE / Minor / 正确性（错误卫生，与 BUG-23-S5 全局裁决不一致）
> - 证据：`lib/features/browser/browser_screen.dart:57-59`
>   ```dart
>   error: (error, _) => _ErrorView(
>     message:
>         error is WebDavException ? error.message : '加载失败：$error',
>   ),
>   ```
> - 复现路径（条件触发）：任意非 `WebDavException` 从 `directoryContentsProvider` 逃逸（如未来新增异常类型、排序/过滤中的 TypeError、`Uri.decodeFull` 之外的解析异常）→ 错误视图显示 `加载失败：<原始异常 toString>`。而 BUG-23-S5（`bug_bug23_repro_test.dart`）已确立裁决：用户可见文案固定、原始异常（errno/address 等）只经 debugPrint 进 LogBuffer——本分支与该裁决相悖；若异常文本含 URL userinfo 还会违反脱敏要求（SCHEMA §5）。
> - 自检答案：**该分支零覆盖**——brw_01 T44/T45 只注入 `WebDavException`；没有任何测试让非 WebDav 异常走 error view。
> - 修复建议（方向）：对齐 BUG-23-S5——固定兜底文案（如"加载失败，请稍后重试"），原始异常经 `debugPrint` 进 LogBuffer；补一条注入非 WebDav 异常的 widget 测试（断言固定文案 + 日志含原始文本）。

### 1.1 这一功能干什么（一句话）

浏览器目录加载出错时的错误提示做"错误卫生"处理：可识别的 WebDAV 错误显示具体原因，不可识别的异常一律显示固定兜底文案，原始异常文本只进日志不展示给用户。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 目录加载失败，且是"没有活跃的连接"这类可识别原因 | 看到具体原因提示（现有行为不变） |
| U2 | 目录加载失败，但原因不是可识别的类型（如程序内部错误、网络底层错误） | 看到固定的"加载失败，请稍后重试"提示，**不看到** errno、地址、异常类型名等原始技术细节（修复前：直接把原始错误文本摆到页面上） |
| U3 | 出错后想看细节排查问题 | 在日志页（调试模式）能找到原始异常文本（修复前：原始文本既不进日志也不在页面，无法排查） |
| U4 | 出错后点"重试" | 重新加载目录（现有行为不变） |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/browser/browser_screen.dart` | 393 | 目录内容 `contentsAsync.when` 的 error 分支（55-63）+ `_ErrorView`（276-317，含重试按钮） |
| Provider | `lib/features/browser/browser_provider.dart` | 258 | directoryContentsProvider（84-129）：加载失败以异常形式抛给 when(error:) |
| 网络 | `lib/core/network/webdav_client.dart` | — | WebDavException 定义 + `redactUrlForLog`（107，日志脱敏） |
| 测试 | `test/features/browser/bug_bug10_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| directoryContentsProvider | FutureProvider.family<List<NasFile>, String> | browser_provider.dart:84-129 | 目录加载；失败抛异常（WebDavException 或任意其它异常）→ error 分支 |

### 2.3 状态机图（错误显示分支）

```
directoryContentsProvider 结果
   ├─ AsyncData ──▶ 文件列表 / 空目录
   └─ AsyncError(error)
        ├─ error is WebDavException ──▶ _ErrorView(error.message)     （保留）
        └─ 其它 ──▶ _ErrorView('加载失败：$error')                    （缺陷，应改为固定文案）
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-10-S1]** WebDavException → 错误视图显示其 message（现有正确行为）
  ```
  Given directoryContentsProvider('/') 以 WebDavException('没有活跃的连接') 失败
  When BrowserScreen build 渲染 contentsAsync.when(error:)
  Then _ErrorView message = error.message = '没有活跃的连接'
  And 重试按钮存在（onRetry → invalidate directoryContentsProvider(currentPath)）
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:57-59`（`error is WebDavException ? error.message`）；锚定测试：`test/features/browser/bug_bug10_repro_test.dart` 用例 3（修复前 PASS）+ brw_01 T44/T45。

- **[BUG-10-S2]** 非 WebDavException → 错误视图暴露原始异常文本（缺陷根源）
  ```
  Given directoryContentsProvider('/') 以非 WebDavException（如 SocketException）失败
  When BrowserScreen build 渲染 error 分支
  Then _ErrorView message = '加载失败：$error' —— 原始异常 toString
        （errno/异常类型名/可能的 URL userinfo 直接进用户可见文案）
  And 原始异常不经过任何日志输出（该分支无 debugPrint）——无法排查
  ```
  Code evidence: `lib/features/browser/browser_screen.dart:59`（`'加载失败：$error'` 插值）；实证：`test/features/browser/bug_bug10_repro_test.dart` 用例 1/2 修复前 FAIL——固定文案 `加载失败，请稍后重试` 找不到（Actual: 0 widgets），日志无原始异常。

### 3.2 修复方案（status: new）

- **[BUG-10-S3]** 非 WebDavException → 固定兜底文案 + 原始异常仅进日志（修改点） （status: new）
  ```
  Given directoryContentsProvider('/') 以非 WebDavException（如 SocketException('OS Error: Connection refused, errno = 111')）失败
  When BrowserScreen build 渲染 error 分支
  Then _ErrorView message = 固定文案 '加载失败，请稍后重试'
  And 原始异常经 debugPrint（redactUrlForLog(error.toString())）进 LogBuffer
  否定断言:
    - 错误视图不得包含原始异常文本（errno / 'Connection refused' / 'SocketException' / '加载失败：' 前缀均不出现）
    - WebDavException 分支不受影响：仍显示 error.message（S1 语义不变）
    - 重试按钮与 onRetry 行为不变（仍 invalidate directoryContentsProvider(currentPath)）
  ```
  **修改点**：`lib/features/browser/browser_screen.dart:55-63` — error 分支从表达式改为带日志的块：
  ```dart
  error: (error, _) {
    if (error is! WebDavException) {
      debugPrint('[Browser] directory load error: '
          '${redactUrlForLog(error.toString())}');
    }
    return _ErrorView(
      message:
          error is WebDavException ? error.message : '加载失败，请稍后重试',
      onRetry: () {
        ref.invalidate(directoryContentsProvider(currentPath));
      },
    );
  },
  ```
  **无新增 import**：`debugPrint` 来自 flutter/foundation（本文件已用，`browser_screen.dart:96` `debugPrint('[Browser] onFileTap: ...')`）；`redactUrlForLog` 来自 `webdav_client.dart:107`（本文件已 import，`:19`）；`WebDavException` 同源已用（`:59`）。
  **脱敏说明**：`redactUrlForLog`（webdav_client.dart:107）剥离 URL userinfo，日志不得含密码明文（SCHEMA §5 错误处理纪律）；固定文案不含任何异常文本，无脱敏风险。
  **文案基准**：`'加载失败，请稍后重试'` 为 cr 报告建议文案逐字采用；对齐 BUG-23-S5 裁决（用户可见固定、原始进日志——`bug_bug23_repro_test.dart` S5 同型断言形态）。

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| error is WebDavException | 不新增日志（WebDAV 可识别错误已有明确 message；避免刷屏），message 显示 error.message |
| error 为其它异常 | debugPrint（脱敏后）原始文本 + 固定文案 |
| error.toString() 含 URL userinfo（如 `http://user:pass@host/`） | redactUrlForLog 剥离 userinfo 后再进日志（webdav_client.dart:107） |
| onRetry 行为 | 不变：`ref.invalidate(directoryContentsProvider(currentPath))`（browser_screen.dart:60-62 原样保留） |
| retry 后再次失败 | 每次 error 分支重建都会 debugPrint 一次（幂等，无状态累积） |

---

## §4 不变量

- **[BUG-10-INV1]** 错误视图用户可见文案永不包含原始异常类型名 / 消息 / 堆栈（错误卫生）
  证据：`lib/features/browser/browser_screen.dart:57-63`（修复后固定文案分支）+ BUG-23-S5 同款裁决（`test/features/browser/bug_bug23_repro_test.dart` S5：'无法连接到服务器，请检查地址和网络' 固定文案、无 errno/类型名泄漏）。

- **[BUG-10-INV2]** 非 WebDavException 的 error 分支必须留日志（catch-log 全局裁决：有日志才允许吞/掩盖）
  证据：`browser_screen.dart` 修复点 debugPrint；SCHEMA §5（静默吞错禁止 + 日志脱敏）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/browser/brw_01_test.dart T44/T45 | BUG-10-S1 的 WebDavException 面 | 只注入 WebDavException，非 WebDav 异常分支零覆盖（cr 自检答案） |
| test/features/browser/bug_bug10_repro_test.dart | BUG-10-S1/S2/S3 + INV1/INV2 | 本 Bug 门禁（修复前 FAIL，已用 repro-test.sh fail 确认） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-10-S1 … S3        # Scenario（S1 现有行为锚定，S2 缺陷锚定，S3 修复目标）
BUG-10-INV1 … INV2    # 不变量
```

dev-exe 要求：S3 + INV1/INV2 由 §5.4 门禁测试覆盖；S1 = 门禁用例 3（修复前 PASS 的锚定用例，修复后必须保持 PASS）；S2 = 门禁用例 1/2 的修复前 FAIL 证据（修复后转为 S3 断言）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无（文案/日志均可在 flutter test 验证；不涉真机） | — | — |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/browser/bug_bug10_repro_test.dart | BUG-10-S3、BUG-10-INV1、BUG-10-INV2 | 门禁：dev-exe 修复后必须 PASS（repro-test.sh pass） |

> 命名说明（SCHEMA §1.3 防撞名）：`test/features/progress/bug_10_repro_test.dart` 已存在（旧轮 BUG-10 = PRG1 double-pop），故本 Bug 门禁使用全称形态 `bug_bug10_repro_test.dart`，禁止覆盖或改名既有文件。

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/browser/browser_screen.dart`（2026-08-16）→ 无直接外部 import（仅 `shared/di/providers.dart:234` facade re-export BrowserScreen 供 router 装配）。

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW（browser_provider.dart:84-129） | 修改只在 error 渲染分支；加载/缓存/排序逻辑不动 | 无代码改动 | brw_01 T44/T45（WebDavException 错误面）+ brw_02/03 目录加载测试全绿 |
| BRW（连接切换/缓存失效路径，connection_provider 等） | 错误视图文案变化不影响数据流 | 无代码改动 | test_01_brw09/10/11 全绿 |
| 全局（SCHEMA §5 错误处理纪律） | 本修改是 catch-log 裁决在 UI 错误卫生面的落实 | 与 BUG-23-S5 同型 | bug_bug23_repro_test.dart 全绿（同款断言形态） |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：不触及任何平台特性条目——错误文案与日志均为纯 Dart/Flutter 行为，`redactUrlForLog` 与 `debugPrint` 均为现有使用中 API（webdav_client.dart:107/:378 同款用法）。

**真机风险列**：无——本修复全部可在 `flutter test` 中验证（固定文案断言 + captureDebugPrint 日志断言），不涉及平台原生特性。

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"BUG-10": {
  "spec_file": "docs/features/BUG-10.md",
  "spec_anchored_files": [
    "lib/features/browser/browser_screen.dart"
  ],
  "scenarios": ["BUG-10-S1", "BUG-10-S2", "BUG-10-S3"],
  "invariants": ["BUG-10-INV1", "BUG-10-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
