# REF-14 — FakeSecureStorage 挂起变体提取到共享 helper（3 处重复实现收敛）

## §0 头部元数据

```yaml
id: REF-14
name: FakeSecureStorage 挂起变体提取（HangingFakeSecureStorage 共享化）
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - test/helpers/fake_secure_storage.dart
  - test/features/bug_10_test.dart
  - test/features/coverage/bug_bug32_repro_test.dart
  - test/features/coverage/svc_storage_utils_test.dart
cross_module_impacts: []                 # 纯测试基础设施，零 lib/ 影响
manual_qa_required: false                # 测试辅助代码，不涉平台原生
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0806-test-helpers.md` D1（cr 复核分流，用户裁决"修"→ 转 REF 需求流程）：

> #### D1. FakeSecureStorage 家族仍缺"挂起"变体，挂起 fake 在 3 个文件重复实现
> - 类型 / 严重度 / 维度：DESIGN / Major / 可测性
> - 证据：
>   - 共享 helper `test/helpers/fake_secure_storage.dart:54-78` 提供 Throwing / DeleteThrowing / ReadThrowing 三种抛错变体，**无 hanging（永不完成）变体**；
>   - 重复实现：`test/features/bug_10_test.dart:157-192`（`_HangingSecureStorage` / `_HangingWriteSecureStorage`）、`test/features/coverage/bug_bug32_repro_test.dart:44-140`（`_HangingReadStorage` / `_HangingWriteStorage` / `_HangingDeleteStorage` + `_MapStorage` + `_ThrowingReadStorage` 共 5 个本地类）、`test/features/coverage/svc_storage_utils_test.dart:15-24`（`_HangingReadStorage`）。
>   - 历史先例：cr-dimensions.md §3 锚定 3 明记"cr-2026-06-28 先例：fake_secure_storage 不能模拟超时"——至今未闭环。
> - 现象与取舍：挂起 fake 是"超时类"测试的必需品（BUG-10 / BUG-32 / SVC10 均需），但三处各自手写 `Completer<T>().future` 实现，后续若安全存储超时语义再变（如 P4 超时分层调整），三处副本可能改漏；取舍点：是否在共享 helper 增加 `HangingSecureStorage` 变体（可配 per-method 挂起），换取三处收敛。
> - 修复建议：向 fake_secure_storage.dart 增加 hanging 变体（read/write/delete 可分别配置挂起），迁移三处本地实现；或登记 coverage-debt 留待后续。

用户裁决：**修**——抽取公共挂起变体到 `test/helpers/`，迁移三处本地实现。

### 1.1 这一功能干什么（一句话）

把"安全存储的读/写/删操作永远不返回"的测试用假实现从 3 个测试文件里抽取到共享测试辅助库，按方法分别开关，消除三份重复代码。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 写"安全存储没反应"类测试（如超时行为） | 直接用测试辅助库里的公共挂起假存储，按需开启"读/写/删 不响应"，不用再在每个测试文件里手写一份 |
| U2 | 想同时让"读"挂起、但"写"正常完成 | 公共变体支持分别配置读/写/删哪个挂起，其余照常工作 |
| U3 | 现在三个已有超时测试文件 | 改用公共变体后，测试测的东西和结果完全不变，只是内部不再有重复的本地实现 |
| U4 | 以后安全存储超时语义调整 | 只需要改共享 helper 一处，三个测试文件不会因为各自副本而改漏 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| 测试 helper | `test/helpers/fake_secure_storage.dart` | 78 | 共享 FakeSecureStorage（内存 map）+ Throwing / DeleteThrowing / ReadThrowing 三抛错变体（54-78） |
| 测试 helper 自测 | `test/helpers/fake_helpers_test.dart` | 65 | helper 行为确认（TEST-07） |
| 测试 | `test/features/bug_10_test.dart` | 192 | BUG-10：safeStorage 超时保护；本地 `_HangingSecureStorage`（157-173）/ `_HangingWriteSecureStorage`（176-192） |
| 测试 | `test/features/coverage/bug_bug32_repro_test.dart` | 643 | BUG-32 门禁：safeStorage 超时抛 SecureStorageTimeoutException；本地 5 类（44-140） |
| 测试 | `test/features/coverage/svc_storage_utils_test.dart` | 54 | SVC10：safeStorageRead 超时降级；本地 `_HangingReadStorage`（14-24） |

### 2.2 关键 Provider 表

本功能不涉 Riverpod Provider，跳过。

### 2.3 状态机图

无状态机，跳过。

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽）

- **[REF-14-S1]** 共享 helper 现状：仅抛错变体（Throwing / DeleteThrowing / ReadThrowing），无挂起变体
  ```
  Given test/helpers/fake_secure_storage.dart
  When 扫描 helper 提供的变体
  Then 仅三种抛错变体（write/delete/read 各自无条件 throw），无任何"永不完成"变体
  And 挂起实现只能在各测试文件本地手写 Completer<T>().future
  ```
  Code evidence:
  - `test/helpers/fake_secure_storage.dart:54-59`（ThrowingFakeSecureStorage）/ :63-68（DeleteThrowing）/ :73-77（ReadThrowing）
  - `test/features/bug_10_test.dart:171`（`return Completer<String?>().future;`）/ :190（`Completer<void>().future`）
  - `test/features/coverage/bug_bug32_repro_test.dart:56/74/91`（三处同形态）
  - `test/features/coverage/svc_storage_utils_test.dart:16-22`（`gate` Completer + `return gate.future;`）

- **[REF-14-S2]** 三个文件挂起变体的本地重复实现（删除目标）
  ```
  Given bug_10_test.dart:158-173 / bug_bug32_repro_test.dart:44-58 / svc_storage_utils_test.dart:15-24
  When 对比三处 _HangingReadStorage（读挂起）
  Then 语义一致：read 永不完成，其余方法（write/delete/containsKey）立即正常完成
  And bug_bug32/svc_storage_utils 形态直接 implements ISecureStorage（非 extends FakeSecureStorage），
      与 fake_secure_storage.dart 的继承式变体风格不同
  ```
  Code evidence:
  - `test/features/bug_10_test.dart:158-173`
  - `test/features/coverage/bug_bug32_repro_test.dart:44-58`（_HangingReadStorage）/ :61-76（_HangingWriteStorage）/ :79-93（_HangingDeleteStorage）
  - `test/features/coverage/svc_storage_utils_test.dart:15-24`（带 `readCalls` 计数器，:17/:46 断言使用）

- **[REF-14-S3]** 挂起 fake 的调用点（迁移时逐一替换）
  ```
  Given 三文件挂起变体的全部构造点
  When 枚举
  Then bug_10_test.dart:29（read 挂起）、:59（write 挂起）
  And bug_bug32_repro_test.dart:230/325/364/427/546（read 挂起）、:290（write 挂起）、:294（delete 挂起）
  And svc_storage_utils_test.dart:36（read 挂起，:46 断言 readCalls == 1）
  ```
  Code evidence:
  - `test/features/bug_10_test.dart:29/59`
  - `test/features/coverage/bug_bug32_repro_test.dart:230/290/294/325/364/427/546`
  - `test/features/coverage/svc_storage_utils_test.dart:36/46`

### 3.2 修改方案（status: new）

设计裁决（用户裁决"修"，cr D1 修复建议："向 fake_secure_storage.dart 增加 hanging 变体（read/write/delete 可分别配置挂起），迁移三处本地实现"）：

| 设计点 | 裁决 |
|---|---|
| 变体形态 | **单一类 `HangingFakeSecureStorage extends FakeSecureStorage`**，构造参数 `hangRead` / `hangWrite` / `hangDelete` 三布尔开关（默认 false），按 cr 修复建议"可配 per-method 挂起"实现；不采用三个独立类（Throwing 家族虽为三独立类，但挂起变体需支持"多方法同时挂起"与计数器，单类更紧凑，且 cr 建议原文即 per-method 可配） |
| 命名 | `HangingFakeSecureStorage`（与 `ThrowingFakeSecureStorage` 家族同缀） |
| 挂起实现 | 覆写方法返回 `Completer<T>().future`（永不 complete）——与三处本地实现同一机制（S2 逆抽证据），**覆写方法不得声明 async**（async 会包一层，语义仍挂起但计数器/短路逻辑易出错；非 async 直返 Completer().future 与现有本地实现逐字节同构） |
| 计数器 | `readCalls` / `writeCalls` / `deleteCalls` 每次调用 +1（含非挂起调用），满足 svc_storage_utils_test.dart:46 的 `readCalls == 1` 断言；计数在挂起短路**之前**递增 |
| 非挂起方法 | 委托 `super`（FakeSecureStorage 内存 map 实现），行为与本地实现"立即完成"一致 |
| bug_bug32 的 `_MapStorage` / `_ThrowingReadStorage` | **不迁移、保留本地**——非"挂起"家族（cr D1 修复建议仅提 hanging 变体）；`_ThrowingReadStorage` 虽与 `ReadThrowingFakeSecureStorage` 语义等价但异常文本不同，迁移会改变断言路径，保留防语义漂移 |
| `import 'dart:async'` | 三文件在删完本地类后移除（Completer 仅存在于被删类中，S3 证据；`Future`/`Stream` 由 dart:core 再导出，见可行性依据） |

**可行性依据（铁律 6）**：
- 挂起机制 `Completer<T>().future`：三处本地实现已在生产使用中（bug_10_test.dart:171、bug_bug32:56/74/91、svc_storage_utils:22），同款模式实证有效，非新模式。
- 继承式变体 `extends FakeSecureStorage + override`：fake_secure_storage.dart:54-77 三个抛错变体同款模式实证（在仓库编译使用中），非新模式。
- `import 'dart:async'` 移除安全：本机 Flutter SDK `bin/cache/dart-sdk/lib/core/core.dart:167` `export "dart:async" show Future, FutureExtensions, Stream;` —— `Future`/`Stream` 由 dart:core 再导出，无需显式 import；三文件内其余 dart:async 类型（Completer/Timer/StreamSubscription/unawaited/scheduleMicrotask）经 grep 实证仅存在于被删类中（bug_bug32:11 的 `unawaited` 出现在注释里，:509 的 `Stream<ProcessingState>` 走 dart:core 导出）。

**修改点 1（新增共享变体）**：`test/helpers/fake_secure_storage.dart` 文件末尾（第 78 行 ReadThrowingFakeSecureStorage 之后）追加：

```dart
/// A [FakeSecureStorage] whose selected methods never complete
/// (simulates a hung Keystore / flutter_secure_storage).
///
/// Configure per-method hanging via [hangRead] / [hangWrite] / [hangDelete]
/// (default false = delegate to the normal in-memory implementation).
/// Call counters increment on every invocation (hanging or not) — asserted
/// by callers such as svc_storage_utils_test.
class HangingFakeSecureStorage extends FakeSecureStorage {
  HangingFakeSecureStorage({
    this.hangRead = false,
    this.hangWrite = false,
    this.hangDelete = false,
  });

  final bool hangRead;
  final bool hangWrite;
  final bool hangDelete;

  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<String?> read({required String key}) {
    readCalls++;
    if (hangRead) {
      return Completer<String?>().future;
    }
    return super.read(key: key);
  }

  @override
  Future<void> write({required String key, required String? value}) {
    writeCalls++;
    if (hangWrite) {
      return Completer<void>().future;
    }
    return super.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    deleteCalls++;
    if (hangDelete) {
      return Completer<void>().future;
    }
    return super.delete(key: key);
  }
}
```

文件头部需补 `import 'dart:async';`（当前文件无此 import，Completer 需要）。

- **[REF-14-S4]** HangingFakeSecureStorage 存在且 per-method 可配（status: new）
  ```
  Given test/helpers/fake_secure_storage.dart 新增 HangingFakeSecureStorage
  When 构造 HangingFakeSecureStorage(hangRead: true, hangWrite: false, hangDelete: false)
  Then 类 extends FakeSecureStorage（isA<FakeSecureStorage> 且 isA<ISecureStorage>）
  And 默认参数形态：三参均可省略（默认全部 false）
  否定断言:
    - 不新增任何其它挂起类（保持单一变体，无重复源）
    - 不修改既有 Throwing / DeleteThrowing / ReadThrowing 三变体任何行为
  ```
  Code evidence（修改点）: `test/helpers/fake_secure_storage.dart` 文件末尾追加块。

- **[REF-14-S5]** hangRead=true：read 永不完成，其余方法正常（status: new）
  ```
  Given storage = HangingFakeSecureStorage(hangRead: true)
  When 调 read(key: 'k') 并 .timeout(Duration(milliseconds: 1))
  Then 抛 TimeoutException（证明永不完成）
  And write/delete/containsKey 立即正常完成（透传 FakeSecureStorage 内存实现）
  And 非挂起 read（hangRead: false 实例）返回 null（map 无值）且正常完成
  否定断言:
    - hangRead=true 时 read 的 Future 不得完成（不得返回 null/值/异常）
    - 挂起 read 不得影响 write/delete 完成（互不干扰）
    - hangRead=false 时 read 不得挂起（透传 map 实现）
  ```
  Code evidence（修改点）: 新增类 `read` 覆写（`readCalls++; if (hangRead) return Completer<String?>().future; return super.read(key: key);`）。

- **[REF-14-S6]** hangWrite=true：write 永不完成；hangDelete=true：delete 永不完成（status: new）
  ```
  Given storage = HangingFakeSecureStorage(hangWrite: true)
  When 调 write(key: 'k', value: 'v') 并 .timeout(Duration(milliseconds: 1))
  Then 抛 TimeoutException
  And read 正常完成（返回 null）
  Given storage2 = HangingFakeSecureStorage(hangDelete: true)
  When 调 delete(key: 'k') 并 .timeout(Duration(milliseconds: 1))
  Then 抛 TimeoutException
  And read/write 正常完成
  否定断言:
    - 挂起 write 不得写进内存 map（peek 不得出现该 key）
    - 挂起 delete 不得触发 map 移除（stub 后 delete 挂起 → peek 仍返回原值）
    - 非挂起 write/delete 必须完成并生效（写入/移除 map）
  ```
  Code evidence（修改点）: 新增类 `write`/`delete` 覆写（短路 return Completer 在前，透传 super 在后）。

- **[REF-14-S7]** 计数器：每次调用 +1（含挂起与非挂起）（status: new）
  ```
  Given storage = HangingFakeSecureStorage(hangRead: true)
  When 调 read 2 次（第 1 次 .timeout 后算完成）、write 1 次、delete 1 次
  Then readCalls == 2 且 writeCalls == 1 且 deleteCalls == 1
  And hangRead: false 实例的 read 调用同样计数
  否定断言:
    - 挂起（永不完成的）调用不得漏计数（计数在短路 return 之前递增）
    - 未调用的方法计数器保持 0
  ```
  Code evidence（修改点）: 新增类中 `readCalls++;` 位于 `if (hangRead) return ...` 之前（write/delete 同理）。

- **[REF-14-S8]** bug_10_test.dart 迁移：两本地类删除，调用点换共享变体（status: new）
  ```
  Given test/features/bug_10_test.dart
  When 执行迁移
  Then 删除第 157-192 行（_HangingSecureStorage 157-173 + _HangingWriteSecureStorage 176-192 + 注释）
  And 第 29 行 `_HangingSecureStorage()` → `HangingFakeSecureStorage(hangRead: true)`
  And 第 59 行 `_HangingWriteSecureStorage()` → `HangingFakeSecureStorage(hangWrite: true)`
  And 移除第 10 行 `import 'dart:async';`（Completer 随类删除而消失，S3 证据）
  And import '../../helpers/fake_secure_storage.dart' 保持（已有）
  And 本文件全部用例（BUG-10-T01~T04）断言与期望零改动，测试保持全绿
  否定断言:
    - 不得改动任何测试断言、超时数值（4s/5s/2s elapse）、异常类型期望
    - 不得删除第 89/101 行的 _FakeSecureStorage / _FakeWriteSecureStorage（非挂起家族，保留）
    - 文件内不得残留 _HangingSecureStorage / _HangingWriteSecureStorage 标识符
  ```
  Code evidence（删除目标）: `test/features/bug_10_test.dart:157-192`；调用点 :29/:59。

- **[REF-14-S9]** bug_bug32_repro_test.dart 迁移：三挂起类删除，_MapStorage/_ThrowingReadStorage 保留（status: new）
  ```
  Given test/features/coverage/bug_bug32_repro_test.dart
  When 执行迁移
  Then 删除第 43-93 行区域（注释行 43 + _HangingReadStorage 44-58 + 注释行 59-60 +
      _HangingWriteStorage 61-76 + 注释行 77-78 + _HangingDeleteStorage 79-93）
  And **保留** _MapStorage（96-123）与 _ThrowingReadStorage（126-140）及其全部使用点（265/271/278/396/467）
  And 调用点替换：
      :230 `_HangingReadStorage()` → `HangingFakeSecureStorage(hangRead: true)`
      :290 `_HangingWriteStorage()` → `HangingFakeSecureStorage(hangWrite: true)`
      :294 `_HangingDeleteStorage()` → `HangingFakeSecureStorage(hangDelete: true)`
      :325/:364/:427/:546 `_HangingReadStorage()` → `HangingFakeSecureStorage(hangRead: true)`
  And 移除第 16 行 `import 'dart:async';`（Completer 仅存在于被删三类的 56/74/91 行，S3 证据）
  And import '../../helpers/fake_secure_storage.dart' 新增（当前文件未 import 该 helper）
  And 本文件全部用例断言与期望零改动，测试保持全绿
  否定断言:
    - 不得改动 _MapStorage / _ThrowingReadStorage 及其任何使用点（非挂起家族，防语义漂移）
    - 不得改动任何测试断言 / elapse 数值 / 异常类型期望（含 :239-258 的 4s/6s 超时窗与 SecureStorageTimeoutException 检查）
    - 文件内不得残留 _HangingReadStorage / _HangingWriteStorage / _HangingDeleteStorage 标识符
  ```
  Code evidence（删除目标）: `test/features/coverage/bug_bug32_repro_test.dart:44-93`；调用点 :230/:290/:294/:325/:364/:427/:546；保留类 :96-140。

- **[REF-14-S10]** svc_storage_utils_test.dart 迁移（status: new）
  ```
  Given test/features/coverage/svc_storage_utils_test.dart
  When 执行迁移
  Then 删除第 14-24 行（注释 14 + _HangingReadStorage 15-24）
  And 第 36 行 `_HangingReadStorage()` → `HangingFakeSecureStorage(hangRead: true)`
  And 第 46 行 `expect(storage.readCalls, equals(1))` 断言**保留不变**（共享变体的 readCalls 计数器支撑）
  And 移除第 6 行 `import 'dart:async';`（Completer/gate 仅存在于被删类，S3 证据）
  And import '../../helpers/fake_secure_storage.dart' 保持（已有，第 12 行）
  And 本文件全部用例断言与期望零改动，测试保持全绿
  否定断言:
    - 不得改动 :28-52 的任何断言（4s 未超时 / 6s 抛 SecureStorageTimeoutException / readCalls == 1）
    - 文件内不得残留 _HangingReadStorage 标识符
  ```
  Code evidence（删除目标）: `test/features/coverage/svc_storage_utils_test.dart:14-24`；调用点 :36；计数器断言 :46。

---

## §4 不变量

- **[REF-14-INV1]** 挂起方法返回的 Future 在任何时间点都不完成（无任何路径 complete，包括异步错误）
  证据：`Completer<T>().future` 无 complete 调用——`test/features/bug_10_test.dart:171`（生产使用实证）+ 新增类短路分支（修改点 1）；timeout 语义下调用方只能收到 TimeoutException（svc_storage_utils_test.dart:49 实证）。

- **[REF-14-INV2]** 计数器对挂起与非挂起调用都 +1
  证据：计数递增位于挂起短路 return 之前（修改点 1 代码顺序）+ 现有断言 `svc_storage_utils_test.dart:46`（`expect(storage.readCalls, equals(1))`）。

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/helpers/fake_helpers_test.dart | — | helper 行为确认（TEST-07），本次不新增用例；REF-14 新变体用例放 §5.4 新文件 |
| test/features/bug_10_test.dart | REF-14-S8 | 迁移回归锚：BUG-10-T01~T04 断言不变 |
| test/features/coverage/bug_bug32_repro_test.dart | REF-14-S9 | 迁移回归锚：全部用例断言不变 |
| test/features/coverage/svc_storage_utils_test.dart | REF-14-S10 | 迁移回归锚：SVC10 两用例断言不变 |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
REF-14-S1 … S3        # 现状逆抽（S1/S2/S3 为行为锚定，非待测目标）
REF-14-S4 … S10       # 修改目标（S4~S7 由 §5.4 门禁文件覆盖；S8~S10 由三迁移文件回归锚定）
REF-14-INV1 … INV2    # 不变量（§5.4 门禁文件）
```

dev-exe 要求：S4~S7 + INV1/INV2 由 §5.4 新文件覆盖；S8~S10 由既有三文件保持全绿 + 文件级 grep 校验（残留标识符零命中）覆盖；S1~S3 为现状锚定（实现前行为快照，不写测试）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-14-S4~S7 / INV1 / INV2（共享变体自身行为） | 零锚定（变体尚未存在） | §5.4 门禁文件 |
| REF-14-S8~S10（迁移回归） | 三文件既有用例全绿，迁移后断言不变即锚定 | 三文件自身 + grep 残留校验 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

新建：`test/helpers/hanging_secure_storage_test.dart`（命名已 grep 核实 test/ 下无同名/近名文件；测试共享 helper 的既有范式参照 `test/helpers/fake_helpers_test.dart`）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/helpers/hanging_secure_storage_test.dart | REF-14-S4、S5、S6、S7、REF-14-INV1、REF-14-INV2 | 门禁：dev-exe 完成后必须 PASS（cov-gate 内）。挂起断言统一用 `.timeout(Duration(milliseconds: 1))` 抛 TimeoutException 形态（无需 fake_async，永不完成对任意时长必超时） |
| test/features/bug_10_test.dart | REF-14-S8 | 既有文件，断言不变，迁移后保持绿 |
| test/features/coverage/bug_bug32_repro_test.dart | REF-14-S9 | 既有文件，断言不变，迁移后保持绿 |
| test/features/coverage/svc_storage_utils_test.dart | REF-14-S10 | 既有文件，断言不变，迁移后保持绿 |

---

## §6 算法样例

无纯函数算法，跳过。

---

## §7 跨模块影响

本条目为纯测试基础设施重构（test/ 下 helper），不触碰任何 lib/ 生产代码，`cross-imports.sh` 无影响面。受影响面按文件枚举：

| 其它测试文件 | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| test/features/bug_10_test.dart | 两本地挂起类删除、import 移除 | 迁移生效 | BUG-10-T01~T04 全绿；grep `_Hanging` 零残留 |
| test/features/coverage/bug_bug32_repro_test.dart | 三挂起类删除、import 移除、新 import helper | 迁移生效 | 全部用例全绿；`_MapStorage`/`_ThrowingReadStorage` 及其使用点零改动；grep 残留校验 |
| test/features/coverage/svc_storage_utils_test.dart | 本地挂起类删除、import 移除 | 迁移生效 | SVC10 两用例全绿（含 readCalls == 1） |
| test/helpers/fake_helpers_test.dart | 共享 helper 文件变更 | 新增类不触碰既有变体 | 既有 TEST-07 用例全绿 |
| 未来新增的超时类测试 | 挂起 fake 规范来源变为共享 helper | 后续任何测试需要挂起存储 | 一律用 HangingFakeSecureStorage，不再手写 Completer().future 本地类 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：本条目不触及 P1~P17 任何条目（纯测试辅助代码，不涉 audio_service / 监听器 / Provider / 平台通道 / 超时分层——storage_utils 的 5s 超时（P17 独立存储超时段）语义不在本次修改范围内，本次只动测试侧挂起模拟）。

**真机风险列**：

| 风险 | 近似测试方案 | 测不了 → 进 mqa-backlog |
|---|---|---|
| 无（本条目改动全部在 `flutter test` 可验证范围内：helper 类行为 + 三文件迁移回归） | §5.4 门禁文件 + 三迁移文件全绿 | 无 |

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证 → `manual_qa_required = false`。

---

## §9 dev-status.json 条目对照

```json
"REF-14": {
  "spec_file": "docs/features/REF-14.md",
  "spec_anchored_files": [
    "test/helpers/fake_secure_storage.dart",
    "test/features/bug_10_test.dart",
    "test/features/coverage/bug_bug32_repro_test.dart",
    "test/features/coverage/svc_storage_utils_test.dart"
  ],
  "scenarios": ["REF-14-S4", "REF-14-S5", "REF-14-S6", "REF-14-S7", "REF-14-S8", "REF-14-S9", "REF-14-S10"],
  "invariants": ["REF-14-INV1", "REF-14-INV2"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```

注：S1~S3 为现状逆抽锚定（实现前行为快照），不入 scenarios 清单（dev-exe 覆盖率门禁只要求待实施条目被覆盖）；如需并入可追加，但现状行为由迁移文件回归隐式锚定。
