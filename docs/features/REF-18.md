# REF-18 — switch/delete 连接的写副作用移出 FutureProvider build 体（P11 模式收敛）

```yaml
id: REF-18
name: switchActiveConnection / deleteConnection 写动作改 Provider<Function> 回调形态，写副作用不再内嵌 build 体
priority: P3
status: active
created_at: 2026-08-22
last_updated: 2026-08-22
spec_anchored_files:
  - lib/features/connection/connection_provider.dart
  - lib/features/connection/connection_list_screen.dart
cross_module_impacts: [BRW]
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260822-2051.md D2（DESIGN/Minor，2026-08-22 用户裁决"修"，转需求流程）。
>
> "switchActiveConnectionProvider / deleteConnectionProvider 的写副作用内嵌 FutureProvider build 体。两处 body 首个语句即 await，规避了 Riverpod build 期断言，且两 provider 均 keepAlive + 仅 ref.read 单发，当前实际单次执行。风险在于未来任何 watch/invalidate 触发重建即重复执行写库（delete 幂等但 LastConnectionException 守卫可能误触发）。是否收敛到统一模式待裁决。"
>
> 处置裁决：修——写动作改 `Provider<Function>` 回调模式（项目内 setDefaultSpeedProvider 同款，player_provider.dart:174-178）。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 在连接列表切换/删除连接 | 行为与现在完全一致：切换立即生效、删除有守卫提示、浏览器状态复位 |
| U2 | （对开发者）未来任何原因导致这两个 provider 元素重建 | 不再隐式重放一次数据库写操作 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| Provider | lib/features/connection/connection_provider.dart:223-235 | switchActiveConnectionProvider = FutureProvider.family<void,int>，body 内 DB 写 + 双 invalidate + CON3 钩子（缺陷点） |
| Provider | 同文件 :375-395 | deleteConnectionProvider 同型（缺陷点） |
| UI | lib/features/connection/connection_list_screen.dart:83,:163 | 生产调用方：`ref.read(...(id).future)` 形态 |
| 桥接 | lib/shared/di/providers.dart:72-73 | 两 provider re-export（签名变化透明） |
| 参照范式 | lib/features/player/player_provider.dart:174-178 | setDefaultSpeedProvider 的 Provider\<void Function(double)\> 回调形态 |

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[REF-18-S0]** 现行语义：body 内依序执行 setActive/delete → invalidate(activeConnection) → invalidate(connectionList) → resetBrowserStateOnActiveConnectionChange（delete 仅 wasActive 时）；LastConnectionException 上抛
  Code evidence: connection_provider.dart:226-234、:379-394

### 3.2 修复目标

- **[REF-18-S1]** 切换连接改回调形态，运行时语义逐字保留 （`status: new`）
  ```
  Given 现行 FutureProvider.family<void,int> 实现
  When 改为 Provider<void Function(int)> 闭包形态
  Then ① 闭包体内语句与 S0 逆抽序列完全一致（setActive → invalidate×2 →
          CON3 钩子 + debugPrint 日志）；
       ② 调用方 await ref.read(switchActiveConnectionProvider)(id) 直调；
       ③ 任何对该 provider 元素的重建只重建闭包本身，不再执行 DB 写
  否定断言:
    - build 体零写副作用、零 ref.invalidate（全部移入闭包）
    - 异常传播不变：setActive 抛错经闭包原样上抛给调用方
    - shared/di re-export 名称不变（调用方 import 面零改动）
  ```
  Code evidence: 修改点 connection_provider.dart:223-235；范式 player_provider.dart:174-178
- **[REF-18-S2]** 删除连接同改回调形态 （`status: new`）
  ```
  Given 同 S1 模式
  When 应用于 deleteConnectionProvider
  Then 闭包含 LastConnectionException 转译（'无法删除最后一个连接'）、
          wasActive 条件 CON3 钩子等既有逻辑；调用方直调
  否定断言: 同 S1 三条
  ```
  Code evidence: 修改点 connection_provider.dart:375-395

---

## §4 不变量

- **[REF-18-INV1]** 切换/删除连接的用户可见行为不变：active 生效、列表刷新、浏览器缓存+导航栈复位条件（switch 无条件 / delete 仅 wasActive）、LastConnectionException 文案
  证据：connection_provider.dart:226-234、:379-394（迁移前后逐字一致）

---

## §5 测试规约

### 5.1 现有测试清单（调用面机械更新清单——仅改调用形态，不改断言）

| 测试文件:行号 | 现调用 | 改为 |
|---|---|---|
| test/features/connection/con_04_test.dart:127 | `read(switchActiveConnectionProvider(id2).future)` | `read(switchActiveConnectionProvider)(id2)` |
| test/features/connection/con_09_test.dart:74,148,203,354,403,455 | 同上形态 | 同上 |
| test/features/connection/con_06_test.dart:311,370,399-400 | `read(deleteConnectionProvider(id).future)` | `read(deleteConnectionProvider)(id)` |
| test/features/connection/con_06_test.dart:377 | `read(deleteConnectionProvider(id2))` 读 AsyncValue 态 | 删除该断言行（回调形态无 AsyncValue 快照；其意图由 :370 后续行为断言覆盖） |
| test/features/connection/bug_bug10_repro_test.dart:196,269,389 | `.future` 形态 | 直调形态 |

### 5.2 测试 ID 派生清单

```
REF-18-S0（现状锚定，由更新后测试全绿承载）
REF-18-S1, REF-18-S2, REF-18-INV1
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| "provider 重建不重放写库" | 回调形态下结构性成立（build 体只剩闭包构造），无法用行为测试有意义地锚定 | 以源码级否定断言（INV/S1 否定面）+ dev-check 审阅承担 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| （无新测试文件——§5.1 清单内的既有测试更新后全绿即为门禁） | — | dev-status test_coverage_gaps 记空 |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| BRW | CON3 钩子清缓存/导航栈时序 | 逻辑逐字迁移，触发点由 build 体移入用户回调闭包，均在事件循环内 | bug_bug16_repro（切连复位场景）全绿 |

**修改点（弱模型照单执行）**：
1. `lib/features/connection/connection_provider.dart:223-235` — 整块替换为：
   ```dart
   final switchActiveConnectionProvider =
       Provider<Future<void> Function(int)>((ref) {
     final service = ref.watch(connectionServiceProvider);
     return (int id) async {
       debugPrint('[Conn] switch: id=$id');
       await service.setActive(id);
       ref.invalidate(activeConnectionProvider);
       ref.invalidate(connectionListProvider);
       // BUG-16: switch 路径收敛进 CON3 钩子（cr-20260816-0804 F3）。
       resetBrowserStateOnActiveConnectionChange(ref);
       debugPrint('[Conn] switch: done id=$id');
     };
   });
   ```
2. `lib/features/connection/connection_provider.dart:375-395` — 同构替换 deleteConnectionProvider 为 `Provider<Future<void> Function(int)>`，闭包体保留现 :379-394 全部语句。
3. `lib/features/connection/connection_list_screen.dart:83` — `await ref.read(switchActiveConnectionProvider(id).future);` → `await ref.read(switchActiveConnectionProvider)(id);`
4. 同文件 `:163` — `await ref.read(deleteConnectionProvider(id).future);` → `await ref.read(deleteConnectionProvider)(id);`
5. 按 §5.1 表更新五个测试文件的调用形态（不得改动任何 expect 断言）。
6. 全量回归：`flutter analyze --no-fatal-infos` 0 warning + `flutter test` 全绿。

---

## §8 平台特性与手动 QA

核对踩坑库：P11 直接相关（本 spec 即把跨 provider 写从 build 期收敛到事件回调）；P10 无交集（invalidate 集合未变）。

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

```json
"REF-18": {
  "spec_file": "docs/features/REF-18.md",
  "spec_anchored_files": [
    "lib/features/connection/connection_provider.dart",
    "lib/features/connection/connection_list_screen.dart"
  ],
  "scenarios": ["REF-18-S0", "REF-18-S1", "REF-18-S2"],
  "invariants": ["REF-18-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
