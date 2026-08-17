# BUG-16 — 切换连接时 widget 层 invalidate 无 mounted 守卫 + catch 无日志

## §0 头部元数据

```yaml
id: BUG-16
name: 切换连接时 widget 层 invalidate 无 mounted 守卫 + catch 无日志
priority: P2
status: active
created_at: 2026-08-16
last_updated: 2026-08-16
spec_anchored_files:
  - lib/features/connection/connection_list_screen.dart
  - lib/features/connection/connection_provider.dart
cross_module_impacts: [Browser, Connection]
parent_feature: Connection（连接管理模块）
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求（用户原话逐字记录）

来源：`docs/cr/cr-20260816-0804-connection-playlist.md` F3（cr 复核 2026-08-16 已确认仍存在）：

> #### F3. 切换连接时 widget 层 invalidate 无 mounted 守卫（CON1 同类风险 + catch 无日志）
> - 类型 / 严重度 / 维度：FRAGILE / Minor / 并发时序 + 安全（catch-log）
> - 证据：
>   - `lib/features/connection/connection_list_screen.dart:76-101` — `_switchConnection`：`await ref.read(switchActiveConnectionProvider(id).future);` 之后**先** `ref.invalidate(directoryCacheProvider); ref.invalidate(navigationStackProvider);`（:79-80）**再** `if (context.mounted)`（:82）；`catch (e) { if (context.mounted) showSnackBar }`（:92-101）在 unmounted 时无任何日志
>   - 本项目自证：connection_provider.dart:250-256 CON1 注释明确记录"widget 级 invalidate 在元素 defunct 后抛被吞掉的 StateError"正是该模式的已知风险；对比 connection_screen.dart:218-224 的失败路径显式 debugPrint
>   - 复现路径（条件：setActive 事务期间用户 pop 列表页）：点某连接切换 → 立刻返回（切换在 in-flight）→ 完成后 `ref.invalidate` 在 defunct 元素上抛 StateError（或至少导航栈复位逻辑丢失）→ 被 catch 吞掉（unmounted 无 UI 无日志）→ 若 invalidate 未执行：navigationStack 保留旧连接深层路径，新活动连接下首次浏览按旧路径 PROPFIND → 404（CON3/BUG-16 同类）。
> - 自检答案：该分支零覆盖——test_02_con11 锚定的是"切换完成时 widget 仍挂载"的正常路径（其注释明言删 :79-80 两行即红），但从不测试"切换期间 pop"的 defunct 交错。
> - 修复建议：把浏览器状态复位并入 provider 层 hook（`resetBrowserStateOnActiveConnectionChange`，见 connection_provider.dart:322-325，switch 路径收敛进 CON3 钩子）；catch 分支补 unmounted 日志。

### 1.1 这一功能干什么（一句话）

把切换连接后的浏览器状态复位（目录缓存清空 + 导航栈回根）从 widget 层移到 provider 层 CON3 钩子，使页面销毁也不丢失复位；切换失败的 catch 在 unmounted 时留日志。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 点列表项切换连接，转圈时立刻按返回键退出列表页 | 切换仍完成，且下次进浏览器不会看到旧连接缓存的目录、不会按旧路径发起请求（修复前：复位逻辑随页面销毁丢失，新连接下可能 404/显示旧数据） |
| U2 | 切换失败（数据库异常）时恰好已退出列表页 | 日志有"切换失败"记录（修复前：无声无息，无任何日志） |
| U3 | 正常切换（页面不退出） | 行为完全不变：切换成功提示"已切换到「X」"、浏览器缓存清空、导航栈回根 |

---

## §2 已实现的功能骨架（代码锚点）

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/connection/connection_list_screen.dart` | 362 | `_switchConnection`（:66-102）：await 后 widget 层 invalidate（:79-80）→ mounted 检查（:82）；catch（:92-101）unmounted 无日志 |
| Provider | `lib/features/connection/connection_provider.dart` | 384 | `switchActiveConnectionProvider`（:216-224）；CON3 钩子 `resetBrowserStateOnActiveConnectionChange`（:322-325）；:309-311 注释明言 switch 收敛超出 CON3 范围（本 Bug 即收敛） |
| 测试 | `test/features/connection/bug_bug16_repro_test.dart` | 本 spec §5.4 | 本 Bug 门禁 |

### 2.2 关键 Provider 表

| Provider 名 | 类型 | 实现位置 | 用途 |
|---|---|---|---|
| switchActiveConnectionProvider | FutureProvider.family<void, int> | connection_provider.dart:216-224 | setActive + invalidate active/connectionList |
| resetBrowserStateOnActiveConnectionChange | void Function(Ref) | connection_provider.dart:322-325 | CON3 钩子：invalidate directoryCache + navigationStack |
| directoryCacheProvider / navigationStackProvider | 经 shared/di 桥接 | shared/di/providers.dart | 浏览器侧状态（REF-31 隔离） |

### 2.3 状态机图

```
用户点列表项 → _switchConnection（widget 层）
  → await switchActiveConnectionProvider(id).future   ← in-flight 期间用户可 pop
  → [widget 层] invalidate(directoryCache) + invalidate(navigationStack)  ← :79-80
       · 页面已销毁 → WidgetRef.invalidate 在 defunct 元素上抛 StateError
         → catch 吞掉（unmounted 无日志）→ 复位丢失
  → [widget 层] if (context.mounted) SnackBar
  失败 → catch: if (context.mounted) SnackBar；else 无日志
```

---

## §3 行为规约（Given-When-Then）

### 3.1 现有行为（逆抽，缺陷态）

- **[BUG-16-S1]** 浏览器状态复位在 widget 层、位于 mounted 检查之前，页面销毁后复位丢失
  ```
  Given 切换请求 in-flight（setActive 未完成）
  When 用户退出列表页（元素 defunct）
  Then await 完成后 :79-80 invalidate 在 defunct 元素上抛 StateError
       （connection_provider.dart:250-256 CON1 注释记录的同类风险）
  And catch（:92-101）context.mounted == false → 不显示 SnackBar、无日志
  And directoryCacheProvider / navigationStackProvider 未复位 → 残留
      旧连接深层路径
  ```
  Code evidence: `lib/features/connection/connection_list_screen.dart:76-101`；`connection_provider.dart:250-256`（CON1 注释自证）

- **[BUG-16-S2]** 失败路径 unmounted 无日志（catch-log 纪律违规，SCHEMA §5）
  ```
  Given 切换请求失败（setActive 抛错）
  When 用户已退出列表页
  Then catch 块 context.mounted == false → 无任何日志/UI（静默吞错）
  ```
  Code evidence: `lib/features/connection/connection_list_screen.dart:92-101`；对照 `connection_screen.dart:218-224`（失败路径显式 debugPrint）

### 3.2 修复方案（status: new）

- **[BUG-16-S3]** 浏览器状态复位并入 provider 层 CON3 钩子（status: new）
  ```
  Given 切换请求 in-flight
  When 切换成功（service.setActive 完成）
  Then switchActiveConnectionProvider 内调用
       resetBrowserStateOnActiveConnectionChange(ref)（provider 层 invalidate，
       container 级，与页面生命周期无关）
  And widget 层 :79-80 两行 invalidate 删除
  And 页面存活时行为不变（cache 清空 + 导航栈回根仍发生）
  And 页面销毁后复位仍发生（本 Bug 修复目标）
  否定断言:
    - 切换失败（setActive 抛错）时不得复位浏览器状态（S3 的钩子在
      await 成功之后才调用）
    - 复位不得发生在 DB 写入完成之前（顺序：setActive 成功后）
    - activeConnectionProvider / connectionListProvider 的既有 invalidate
      顺序不变（:221-222 保持）
  ```
  **修改点 1（provider 层）**：`lib/features/connection/connection_provider.dart:216-224` `switchActiveConnectionProvider`：
  ```dart
  // 修改前（216-224 行）:
  final switchActiveConnectionProvider =
      FutureProvider.family<void, int>((ref, id) async {
    final service = ref.watch(connectionServiceProvider);
    debugPrint('[Conn] switch: id=$id');
    await service.setActive(id);
    ref.invalidate(activeConnectionProvider);
    ref.invalidate(connectionListProvider);
    debugPrint('[Conn] switch: done id=$id');
  });
  // 修改后:
  final switchActiveConnectionProvider =
      FutureProvider.family<void, int>((ref, id) async {
    final service = ref.watch(connectionServiceProvider);
    debugPrint('[Conn] switch: id=$id');
    await service.setActive(id);
    ref.invalidate(activeConnectionProvider);
    ref.invalidate(connectionListProvider);
    // BUG-16: switch 路径收敛进 CON3 钩子 —— 浏览器状态复位从 widget 层
    // （connection_list_screen.dart:79-80，随页面销毁丢失）上移到 provider
    // 层，切换期间退出列表页不再丢复位（cr-20260816-0804 F3）。
    resetBrowserStateOnActiveConnectionChange(ref);
    debugPrint('[Conn] switch: done id=$id');
  });
  ```
  **修改点 2（widget 层）**：`lib/features/connection/connection_list_screen.dart:78-81` 删除两行 invalidate：
  ```dart
  // 修改前（76-82 行）:
      await ref.read(switchActiveConnectionProvider(id).future);

      // B-1: clear browser cache so the old connection's data isn't shown.
      ref.invalidate(directoryCacheProvider);
      ref.invalidate(navigationStackProvider);

      if (context.mounted) {
  // 修改后:
      await ref.read(switchActiveConnectionProvider(id).future);

      if (context.mounted) {
  ```
  删除后 `directoryCacheProvider` / `navigationStackProvider` 的 import 若不再使用需一并清理（检查 connection_list_screen.dart 内其它使用点——grep 确认仅 :79-80 两处则删除 `import '../../shared/di/providers.dart'` 中的 show 列表对应项，connection_list_screen.dart:13 仍在使用 connectionDaoProvider 需保留）。

- **[BUG-16-S4]** catch 分支 unmounted 时留日志（status: new）
  ```
  Given 切换请求失败
  When 用户已退出列表页（context.mounted == false）
  Then catch 分支执行 debugPrint（不静默吞错，SCHEMA §5 catch-log 纪律）
  否定断言:
    - 日志不得包含密码/凭据（secret-logs 门禁：只记异常文本与 id）
    - mounted 时行为不变（SnackBar '切换失败：$e' 照旧）
  ```
  **修改点**：`lib/features/connection/connection_list_screen.dart:92-101`：
  ```dart
  // 修改前（92-101 行）:
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  // 修改后:
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        // BUG-16（cr-20260816-0804 F3）：catch-log 纪律 —— 页面已销毁
        // 无 UI 可反馈，但错误不得静默消失。
        debugPrint('[Conn] switch failed after page disposed: $e');
      }
    }
  ```

**边界裁决（弱模型照此实现，无需二次判断）**：

| 边界情况 | 裁决 |
|---|---|
| 切换成功且页面存活 | provider 层钩子复位 + widget SnackBar（:82-91 不变）——用户可见行为与修复前一致 |
| 切换成功但页面销毁 | provider 层钩子复位（修复目标）；widget catch 不触发（无异常） |
| 切换失败且页面存活 | provider 层不调用钩子（S3 否定断言）；widget catch 显示 SnackBar（不变） |
| 切换失败且页面销毁 | provider 层不调用钩子；widget catch 走 else 分支 debugPrint（S4） |
| 既有 test_02_con11 测试（页面存活路径） | 断言行为级（cache 清空 + 栈回根）——修复后仍全绿（复位从 provider 层发生，观察结果相同）；其文件注释"删掉 :79-80 两行本文件即红"过时，**允许 dev-exe 更新注释文字，严禁改断言** |
| import 清理 | connection_list_screen.dart:13 的 `show` 列表按实际使用保留（connectionDaoProvider 用于 :73 `findById`） |

---

## §4 不变量

- **[BUG-16-INV1]** 浏览器状态复位（directoryCache + navigationStack）与页面生命周期无关：任何"活动连接变更"的写路径（switch/update/delete）都必须在 provider 层完成复位
  证据：修复后 switchActiveConnectionProvider（connection_provider.dart:216-224）走 CON3 钩子；update/delete 已走钩子（:349/:382）；缺陷态证据 connection_list_screen.dart:79-80

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖的 Scenario / INV | 备注 |
|---|---|---|
| test/features/connection/test_02_con11_test.dart（TEST-02-S1/S2） | 切换完成时 widget 仍挂载的正常路径 | 注释明言"删 :79-80 即红"——修复后断言仍绿，注释过时（§3 裁决） |
| test/features/connection/bug_bug16_repro_test.dart | 本 Bug 门禁 | 切换期间 pop 的 defunct 交错（自检答案：零覆盖） |

### 5.2 测试 ID 派生清单（dev-exe 派发测试 Agent 用）

```
BUG-16-S1, S2        # 缺陷态/现状锚定
BUG-16-S3, S4        # 修复目标
BUG-16-INV1          # 不变量
```

dev-exe 要求：S3 由 §5.4 门禁测试覆盖（含切换期间 pop 的交错路径）；S4 由门禁测试顺带锚定（失败注入 + pop 组合的日志断言可选，dev-exe 可加）；S1/S2 由门禁测试驱动（缺陷态断言）。

### 5.3 测试覆盖盲点（dev-plan 写本文档时识别）

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-16-S4（unmounted 失败日志） | 门禁测试主断言是状态复位；日志断言需注入失败 | dev-exe 在门禁测试内加一个失败注入用例（setActiveGate 完成前抛错 + pop + debugPrint 捕获断言）——如无法捕获 debugPrint（testWidgets 默认吞 debugPrint 输出），可改用 LogBuffer/日志侧断言或标记为逻辑层手动核对 |

### 5.4 测试文件位置（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/connection/bug_bug16_repro_test.dart | BUG-16-S3、BUG-16-INV1 | 门禁：修复前 FAIL（已用 repro-test.sh fail 确认——切换期间 pop 后 cache 残留/栈不复位）；dev-exe 修复后必须 PASS（repro-test.sh pass） |
| test/features/connection/test_02_con11_test.dart | BUG-16-S3（页面存活路径） | 既有测试，断言不变；允许更新过时注释 |

---

## §6 算法样例

本 Bug 不涉纯函数算法，跳过。

---

## §7 跨模块影响

`bash cross-imports.sh impact lib/features/connection/connection_list_screen.dart lib/features/connection/connection_provider.dart`（2026-08-16）→ 引用方：

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| Browser（directoryCacheProvider / navigationStackProvider，经 shared/di 桥接） | 复位来源从 widget 层改 provider 层 | 复位时机同为 setActive 成功后（顺序不变）；浏览器侧观察行为一致 | browser 既有测试全绿；test_02_con11 S1/S2 全绿 |
| App（router.dart:33-36） | /connections 路由 | 类签名不变 | 编译 + analyze 0 warning |
| Connection 自身（connection_screen / connection_edit_screen 的 CON1/CON3 注释链） | 注释中"switch 收敛超出 CON3 范围"（:309-311）到期 | 修复后注释需同步（dev-exe 更新 :309-311 注释，声明已收敛） | con_01 / con_05 / con_02 既有测试全绿 |
| deleteConnectionProvider（:364-384） | 已走 CON3 钩子（:382），不受影响 | 无 | bug_bug24 / ref_22 既有测试全绿 |
| Connection 测试（test/features/connection/con_09_test.dart TST-T93） | 原断言"切换后 conn2 缓存条目保留"（targeted 语义）与全清实现互斥 → 失败 | **跨模块影响漏识**（2026-08-17 补记；裁决 A：全清语义，与旧生产 connection_list_screen.dart:79-80 及本 spec §3 一致，TST-T93 的 targeted 假定生产从未实现） | 测试体修订为断言切换后整个缓存清空（含 conn1 与 conn2 条目），群名/测试名同步改 |

---

## §8 平台特性与手动 QA

设计前已逐条核对 `docs/dev/platform-pitfalls.md`：触及 **P9**（defunct 元素上调用抛错——本 Bug 的 widget 层 invalidate 即 P9 变体，修复把副作用移到 provider 层从根上消除）；**P14**（并发写状态——复位动作收敛为 provider 层唯一入口，消除 widget/provider 双路径）。P10（数据源订阅方）已在本节 §7 列出。

**真机风险列**：无。本功能不涉及平台原生特性（无 audio_service / MethodChannel / 通知栏 / 真机时序），全部可在 `flutter test` 中验证（unmount 交错用 pumpWidget 替换即可模拟）。

---

## §9 dev-status.json 条目对照

```json
"BUG-16": {
  "spec_file": "docs/features/BUG-16.md",
  "spec_anchored_files": ["lib/features/connection/connection_list_screen.dart", "lib/features/connection/connection_provider.dart"],
  "scenarios": ["BUG-16-S1", "BUG-16-S2", "BUG-16-S3", "BUG-16-S4"],
  "invariants": ["BUG-16-INV1"],
  "algorithms": [],
  "manual_qa_required": false,
  "user_acceptance_text": "见 §1.2"
}
```
