# BUG-20 — 退出播放页后自动保存/暂停保存监听被取消，后台收听进度丢失

```yaml
id: BUG-20
name: 退出全屏播放页后自动保存/暂停保存监听被取消（后台收听进度丢失窗口）
priority: P1
status: active
created_at: 2026-08-22
last_updated: 2026-08-22
spec_anchored_files:
  - lib/features/player/player_screen.dart
  - lib/features/player/player_provider.dart
cross_module_impacts: [HOME, PRG]
parent_feature: Player
manual_qa_required: true
```

---

## §1 用户视角

### 1.0 原始需求（来源逐字记录）

> 来源：docs/cr/cr-20260822-2051.md F1（走查发现，复核确认仍存在）。
>
> "复现路径：播放有声书长章节 → 打开全屏播放页后返回退出（触发 dispose）→ 后台连续收听 40 分钟（不切歌）→ 从通知栏暂停或直接划掉应用 → 重新打开。期望：恢复到暂停处；实际：进度回退到最后一次保存点（通常是离开播放页时 :97 那次），丢失整个后台收听区间。"
>
> 处置裁决（2026-08-22 cr 复核）：FRAGILE/Major，用户选定进入 dev-plan Bug 流程第一批。

### 1.1 一句话

退出全屏播放页不应终止进度持久化——只要还在播，进度就必须持续保存。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 听有声书时进过一次全屏播放页又退出来，之后一直用通知栏/耳机听 | 暂停、切走、杀掉应用后再进来，进度停在你听到的地方 |
| U2 | 后台连听几十分钟一章没听完 | 中途任何时刻退出应用，重开后从最近的保存点继续（最多差几秒），而不是回到几十分钟前 |
| U3 | 在全屏播放页内暂停 | 行为不变：暂停即保存 |

---

## §2 已实现骨架（逆抽锚点）

| 层 | 文件 | 角色 |
|---|---|---|
| UI | lib/features/player/player_screen.dart | dispose 内 :97 一次性收尾保存；:102 调 cancelPlaybackSubscriptionsProvider（缺陷点）；initState fast-path :59 重连监听器 |
| Provider | lib/features/player/player_provider.dart | :268-302 autoSave Timer / pauseSave 订阅的启动与取消；:431-435 cancelPlaybackSubscriptionsProvider（同时杀两者）；:342-347 _startPlaybackListeners 三监听器同启 |
| 门禁测试 | test/features/player/bug_bug20_repro_test.dart | widget 级复现（真实 dispose 链路），修复前 FAIL。**脚手架修订（2026-08-23，dev-exe round-1 发现）**：退页模拟改为外部 ProviderContainer + UncontrolledProviderScope 保活、仅卸载页面路由（模拟生产 pop）；原整树 pumpWidget(SizedBox) 会连带销毁根容器触发 ref.onDispose 合法清理，与 INV1 自相矛盾且任何合规实现均无法通过 |

关键事实：三类播放监听器由 `_startPlaybackListeners`（player_provider.dart:342-347）一起启动，但 completed 监听器不受页面 dispose 影响（P8 合规），另两类被 :102 取消——同生不同死。

---

## §3 行为规约

### 3.1 现状锚定（逆抽）

- **[BUG-20-S1]** 页面存活期间，playing→paused 转换触发保存、10s 周期自动保存持续生效
  ```
  Given 监听器已随加载成功启动（player_provider.dart:377）
  When 页面存活期间发生暂停转换 / 每 10 秒
  Then saveProgressProvider 各触发一次
  ```
  Code evidence: `lib/features/player/player_provider.dart:276-278`（Timer.periodic）、`:292-295`（playerStateStream 转换检测）

### 3.2 修复目标

- **[BUG-20-S2]** 退出全屏播放页后，暂停转换仍必须持久化进度 （`status: new`）
  ```
  Given 监听器已启动且用户曾进入并退出 PlayerScreen
  When 退出后发生 playing→paused 转换（如通知栏暂停）
  Then saveProgressProvider 正常触发，进度落库
  否定断言:
    - PlayerScreen.dispose 不得调用任何终止 autosave/pausesave 的清理入口
      （现 :102 的 cancelPlaybackSubscriptionsProvider 调用必须移除）
    - dispose 的一次性收尾保存（现 :97 _saveProgressWithContainer）必须保留
    - completed 自动切歌监听器行为不得变化
  ```
  Code evidence: 缺陷点 `lib/features/player/player_screen.dart:102`；修复后由容器 ref.onDispose 兜底清理（BUG-21 机制，player_provider.dart:273/:288/:312）
- **[BUG-20-S3]** 退出全屏播放页后，10s 周期自动保存仍持续触发 （`status: new`）
  ```
  Given 同 S2
  When 退出后每 10 秒
  Then saveProgressProvider 周期触发直至容器销毁或下一次成功加载重启
  否定断言:
    - Timer 不得在页面退出时被 cancel（仅容器 dispose 或显式 API 触发）
  ```
  Code evidence: 缺陷点同上；Timer 创建于 player_provider.dart:276-278

---

## §4 不变量

- **[BUG-20-INV1]** 播放生命周期监听器（autosave/pausesave/completed）的生命周期 = Provider 容器生命周期，归 ref.onDispose 清理；任何页面 State 的 dispose 不得触碰
  证据：player_provider.dart:272-273/:287-288/:311-312（既有 onDispose）+ P8 条款
- **[BUG-20-INV2]** PlayerScreen.dispose 的一次性进度收尾保留（退出瞬间至少存一次当前进度）
  证据：player_screen.dart:97 `_saveProgressWithContainer(_container);`

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| test/features/player/bug_bug21_repro_test.dart | 显式 cancel 路径语义 | 其断言对象是 provider 自身语义，本 Bug 不改该语义，无需改动 |
| test/features/player/ply_14_test.dart | PlayerScreen widget 装配配方来源 | 不变 |

### 5.2 测试 ID 派生清单

```
BUG-20-S1, BUG-20-S2, BUG-20-S3, BUG-20-INV1, BUG-20-INV2
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| 无 | S1/S2/S3 均已由门禁文件覆盖（S1 对照组恒真锚定，S2/S3 修复前 FAIL） | dev-exe 实现后全绿即可 |

### 5.4 门禁测试文件（spec-scan --gate 硬校验）

| 测试文件 | 覆盖 ID | 说明 |
|---|---|---|
| test/features/player/bug_bug20_repro_test.dart | BUG-20-S1、BUG-20-S2、BUG-20-S3 | 修复前 FAIL 已由 repro-test.sh fail 确认（2026-08-22）；修复后必须 PASS。脚手架修订见 §2 门禁测试行（退页=卸载页面路由，容器保活；断言逐字不变） |

---

## §6 算法样例

不涉及纯函数算法，跳过。

---

## §7 跨模块影响

impact 反查（2026-08-22）：player_screen.dart ← app/router.dart；player_provider.dart ← main.dart、app/onboarding.dart。

| 其它 feature | 影响点 | 影响条件 | 回归断言要求 |
|---|---|---|---|
| HOME | MiniPlayerBar 场景的后台收听即本 Bug 主场景 | 删除 :102 后监听器更长寿 | home 既有测试全绿 |
| PRG | 进度写入频率上升（后台也每 10s 写） | upsert 幂等（ConflictAlgorithm.replace） | prg 既有测试全绿；注意 prg_test.dart:1831 引用 cancelPlaybackSubscriptionsProvider —— provider 本体保留不删，仅页面不再调用，该测试无需改动 |

**修改点（弱模型照单执行）**：
1. `lib/features/player/player_screen.dart:102` — 删除整行 `_container.read(cancelPlaybackSubscriptionsProvider)();`。dispose 顺序变为：收尾保存(:97) → 定时器取消(:101) → removeObserver。不改其它行。
2. 不删除 cancelPlaybackSubscriptionsProvider 定义与 re-export（prg_test.dart 仍引用；作为显式停止 API 保留）。
3. 全量回归：`flutter analyze --no-fatal-infos` 0 warning + `flutter test` 全绿。

## §8 平台特性与手动 QA

核对踩坑库：P8 直接相关（本 Bug 即其精神在 autosave/pausesave 上的延伸违规）；P16/P17 无交集。

| 风险 | 近似测试 | 测不了 → mqa-backlog |
|---|---|---|
| 真机后台收听 30+ 分钟后经通知栏暂停 → 杀进程 → 重开恢复位置 | widget 门禁已近似覆盖订阅存活 | BUG-20-MAN1：真机播长章节→进出播放页→后台 5 分钟→通知栏暂停→杀进程→重开验证进度 |

涉及后台播放/通知栏 → manual_qa_required = true。

---

## §9 dev-status.json 条目对照

```json
"BUG-20": {
  "spec_file": "docs/features/BUG-20.md",
  "spec_anchored_files": [
    "lib/features/player/player_screen.dart",
    "lib/features/player/player_provider.dart"
  ],
  "scenarios": ["BUG-20-S1", "BUG-20-S2", "BUG-20-S3"],
  "invariants": ["BUG-20-INV1", "BUG-20-INV2"],
  "algorithms": [],
  "manual_qa_required": true,
  "user_acceptance_text": "见 §1.2"
}
```
