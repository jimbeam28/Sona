---
name: cr
description: |
  代码走查与复核（双模式，二选一，默认走查）。
  走查模式：扫描用户指定范围（目录 / 功能模块 / git 记录，未指定时默认 lib/ + test/），按 7 维度（正确性 / 架构一致性 / 并发时序 / 安全 / 可测性 / 性能 / 风格）检查，输出分级问题清单到 docs/cr/cr-{YYYYMMDD-HHMM}.md。
  复核模式：遍历 docs/cr/ 下所有走查报告，逐条复核问题是否仍存在；仍存在则调用 dev-plan 生成修复 spec，然后删除该 cr 文档；如 docs/cr/ 为空则提示后退出。
  触发场景：用户提到"走查"、"代码走查"、"code review"、"review 代码"、"/cr"、"复核"、"复核走查"——默认走查，用户明说"复核"切复核模式。
  与 dev-check 的区别：dev-check 是 dev-exe 流程内的独立 spec 评审（贴合度 / 忠实度 / 覆盖率漂移）；/cr 是与 spec 流程无关的通用代码 review，用于日常任意代码片段走查。
  不触发：用户提到"检查"、"审查"、"dev-check"、"验证 spec"时归 dev-check；"实现"、"开发"归 dev-exe。
---

# 代码走查与复核 (cr)

通用代码 review 工具，独立于 dev-plan / dev-exe / dev-check 流程。两种模式互斥，默认走查。

## 模式判定

读用户原话：

- 含"**复核**" / "**复核走查**" / "verify cr reports" → **复核模式**
- 其余（含"走查"、"code review"、"review 代码"、"/cr" 等）→ **走查模式**（默认）

---

## 走查模式

### 第 1 步：解析范围

从用户原话抽取范围参数。四类范围互斥（同一次走查只取其一，若用户给出多个则优先级 git > 功能 > 目录；默认兜底）：

| 类型 | 用户表达示例 | 解析为 |
|---|---|---|
| **git 记录** | "走查上周的提交" / "review 含 'WebDAV' 的提交" / "看最近 3 个 commit" | `git log --since=...` / `--grep=...` / `-<N>` 筛 commit，再用 `git show <sha> --name-only` 列出改动文件作为走查对象 |
| **功能模块** | "走查 player 模块" / "看 browser" | `lib/features/{name}/` + `test/features/{name}/` |
| **目录** | "看 lib/shared/" / "走查 lib/core/database/" | 用户指定的目录路径（同时覆盖 lib 与 test 内同路径） |
| **默认** | 未指定 | `lib/` + `test/` 全量 |

git 范围的执行细节：
- 时间筛选：`git log --since="2026-06-01" --until="2026-06-28" --name-only --pretty=format:"%h %s"` —— 仅取改动文件清单，每个文件独立走查（不限于 git diff 增量行，整文件都要看）。
- 关键字筛选：`git log --grep="<关键字>" -i --name-only --pretty=format:"%h %s"` —— 大小写不敏感。
- 数量限制：`git log -<N>` —— 取最近 N 个 commit。

### 第 2 步：加载项目硬约束（铁律）

走查前**必读** `CLAUDE.md` 的"架构分层"与"数据库"两节，把以下硬约束作为检查项：

1. **分层**：UI → Provider → Domain → Contract → Data。Domain 层零 Flutter 依赖，可独立单元测试。
2. **Feature 隔离**：跨 feature 依赖必须经 `shared/di/providers.dart` 桥接，**禁止 feature 间直接 import**。
3. **契约层不可绕过**：数据源访问必须经 `core/contracts/` 抽象接口（`IAudioPlayer` / `IAudioHandler` / `IConnectionDao` / `IProgressDao` / `IPlaylistDao` / `ISecureStorage`），不允许 Domain/Provider 层直接用 `just_audio` / `audio_service` / `sqflite` / `flutter_secure_storage`。
4. **密码安全**：明文密码只能存 `flutter_secure_storage`，key 格式 `connection_password_{id}`；**严禁**密码明文进 SQLite、日志、`print`/`debugPrint`。
5. **Basic Auth**：URL 构建时凭证编码不得落日志。

### 第 3 步：7 维度走查

对每个文件按以下维度逐项检查，每发现一个问题打 severity（Critical / Major / Minor / Info）+ 证据（`file:line`）+ 现象 + 修复建议。**修不修由用户决定——本 skill 不改代码**。

#### 维度 1：正确性与健壮性

- 空值 / 边界（空列表、null、单元素、越界 index）
- 异常路径：是否 `try/catch` 静默吞掉错误？是否向用户暴露原始异常栈？
- 资源释放：`StreamSubscription` / `Timer` / `TextEditingController` / `AnimationController` / `ScrollController` 是否在 `dispose()` 中 cancel / close？
- 数值边界：`Duration` / `position` 是否经 `clampSeek` 等工具约束？速度档位是否限定 6 档？
- 异步竞态：`Future.then` 链是否考虑中途被新请求作废？播放编排是否经 `SerializedRequestGate`？

#### 维度 2：架构一致性（CLAUDE.md 硬约束）

- **Domain 零 Flutter**：grep `lib/features/*/domain/` 是否 import `flutter/`、`flutter_riverpod`、`package:flutter_*`、`dart:ui`、`shared_preferences`、`just_audio`、`audio_service`、`sqflite`、`flutter_secure_storage`。任何一条 → Critical。
- **Feature 隔离**：grep `lib/features/A/` 是否 import `lib/features/B/`（除 `shared/` 外）。任何直接 feature 间 import → Major。
- **契约层是否被绕过**：在 `lib/features/*/domain/` 或 `*/provider/` 中直接 `import package:just_audio/just_audio.dart` / `package:audio_service/...` / `package:sqflite/sqflite.dart` / `package:flutter_secure_storage/...` → Major（应经 Contract 接口注入）。
- **Provider 不直连 Data Source**：`Provider` 应调 `Domain Service` 或 `Contract`，不应直接调 WebDAV / SQLite。

#### 维度 3：并发与时序

- **`SerializedRequestGate`**：`playback_orchestrator` 的 load / skip / remove 是否都走门？绕过门直达 `AudioPlayer` → Critical（可能竞态）。
- **`setState` 后异步回调**：`await` 之后调 `setState` / 读 `widget.` 之前是否检查 `mounted` / `!disposed`？Widget 重建后回调还活着可能崩。
- **Provider `autoDispose`**：在 `autoDispose` Provider 里持有 `ref` 长生命周期对象是否泄漏？是否用 `ref.onDispose` 清理？
- **`fake_async` 兼容**：Timer / Future.delayed 用于业务逻辑时是否在测试中可控？

#### 维度 4：安全（CLAUDE.md 硬约束）

- grep `print(` / `debugPrint(` / `log(` 附近是否含 `password` / `pwd` / `credential` / `Authorization` 字样 → Critical。
- SQLite 表 `connections` 中 `password` 字段应只存 secure_storage 引用 key，而非明文 → 否则 Critical。
- 连接 URL 中是否泄露 Basic Auth（`https://user:pass@host`）→ Major。
- WebDAV PROPFIND 验证或列目录时的请求 body / 响应是否被记录到日志？敏感头是否脱敏？

#### 维度 5：可测性

- 纯逻辑是否抽到 Domain 层（widget 内混业务判断 → 难测）。
- 是否在 Widget / Provider 中直接调 `MethodChannel` 导致难测？（应经 `background_service` 抽象层）。
- 测试 helper 是否被绕过：直接 new 真实 `AudioPlayer` / 真实 `sqflite` 而非 `mock_audio_player` / `test_database`？
- `test/` 下是否存在"只构造不调方法"的空骨架测试？是否 `expect(true, isTrue)` 形式通过而不测行为？ → Minor 但要列。

#### 维度 6：性能

- 列表 `Widget` 是否缺 `const` / 缺 `Key` → 不必要 rebuild。
- 长列表是否用 `ListView.builder` 而非 `Column` + `地图`？
- `cache_policy` TTL/LRU 是否在 `directory_service` 中被正确引用？目录缓存是否过期才 fetch？
- 是否在 `build` 方法里做重活（IO、JSON parse、排序）？应 memoize 或挪到 Provider。

#### 维度 7：风格

- 跑 `flutter analyze` —— 任何 warning 计 Minor（应为 0）。
- 跑 `dart format --set-exit-if-changed lib test` —— 任何未格式化文件计 Info。

### 第 4 步：写走查报告

输出文件 `docs/cr/cr-{YYYYMMDD-HHMM}.md`（时间戳精确到分钟，避免同日多次走查撞名）。模板：

```markdown
# 代码走查报告

> 生成时间：YYYY-MM-DD HH:MM
> 走查范围：<范围描述：目录 / 功能 / git commit hash 列表 / 全量>
> 检查文件数：N
> 问题总数：N（Critical: X / Major: Y / Minor: Z / Info: W）

## 摘要

<一段话概括总体健康度与主要风险点>

## 问题清单

### Critical

#### C1. <问题标题>
- 严重度：Critical
- 维度：<架构一致性 / 安全 / ...>
- 证据：`lib/.../x.dart:42`
- 现象：<代码片段 + 为何是问题>
- 修复建议：<具体改动方向，不给代码>

### Major
...

### Minor
...

### Info
...

## 维度统计

| 维度 | Critical | Major | Minor | Info |
|---|---|---|---|---|
| 正确性 | ... | ... | ... | ... |
| 架构一致性 | ... |
| 并发时序 | ... |
| 安全 | ... |
| 可测性 | ... |
| 性能 | ... |
| 风格 | ... |

## 已检查文件清单

<列出本次走查覆盖的文件路径，便于复核追溯>
```

写完后在终端报告：报告路径 + Critical/Major 数量 + 一句话下一步（"可启动 dev-plan 修复 / 或手动修 / 或 /cr 复核"）。

**铁律**：
1. **不修代码**：本 skill 只出清单，修复归用户手动或后续 dev-exe。
2. **不脑补**：每条问题必须给 `file:line` 证据 + 实际代码片段，不允许只说"可能有"。
3. **走查范围要列全**：报告末尾"已检查文件清单"必须真实覆盖第 1 步解析的所有文件，便于复核时追溯。

---

## 复核模式

### 第 1 步：列出待复核报告

```bash
ls docs/cr/cr-*.md 2>/dev/null
```

- 无文件 → 输出"`docs/cr/` 为空，无可复核的走查报告"并退出。
- 有文件 → 全部纳入复核清单，按文件名时间戳升序处理。

### 第 2 步：逐报告逐条复核

对每个 `docs/cr/cr-{ts}.md` 中的每条问题：

1. 读问题记录的 `证据：lib/.../x.dart:行号`
2. 打开该文件该行，**重新判定**问题是否仍存在：
   - **已修复**（代码已改、文件已删、行已不存在）→ 标"已修复"，跳过。
   - **仍存在** → 进入第 3 步（调 dev-plan）。
3. 全报告复核完后进入第 4 步（删 cr 文档）。

### 第 3 步：对仍存在的问题调 dev-plan

对每条**仍存在**的问题：

1. 加载 `dev-plan` skill。
2. 把该问题作为"Bug 修复场景"输入 dev-plan：
   - 证据出处 = 本 cr 报告的 `file:line` + 现象描述
   - 需求描述 = "修复 cr 报告 C1：{现象}"
   - dev-plan 将按其流程：先写**失败复现测试**（硬门禁） → 再逆抽 + 输出 `docs/features/BUG-{N}.md`（参照现有 BUG-01/02/03 的格式）+ 更新 `docs/dev/dev-status.json`
3. 等待 dev-plan 完成（向用户呈现 §1.2 用户视角 Scenario 表 → 用户 ack 后**不自动继**，由用户手动决定是否启动 dev-exe）。

### 第 4 步：删除已复核的 cr 文档

每个 cr 报告处理完所有问题后（无论全修复、还是已调 dev-plan 派生 spec），**删除**该 `docs/cr/cr-{ts}.md` 文件。

理由：cr 报告是一次性走查快照，问题要么已修复要么已被 dev-plan 派生为正式 spec 进入 dev 流程，cr 文档本身不需长期留存。引用规范参照 BUG-01/02/03 spec 已迁移到 `docs/cr/cr-2026-06-28.md` 路径。

### 第 5 步：终端汇报

```
═══════════════════════════════════
  cr 复核完成
═══════════════════════════════════
  复核报告数：N
  问题总数：M
    已修复：X
    仍存在 → 派生 dev-plan spec：
      - BUG-{K1}（来源 cr-{ts1}.md C1）
      - BUG-{K2}（来源 cr-{ts2}.md M3）
  已清理 cr 文档：cr-{ts1}.md / cr-{ts2}.md
  下一步：用户可手动启动 dev-exe {BUG-ID} 执行修复
═══════════════════════════════════
```

**复核模式铁律**：
1. **不修代码**：复核也只判定"是否仍存在"，修复走 dev-plan / dev-exe 链。
2. **不跳过 dev-plan**：仍存在的问题必须经 dev-plan 写 spec + 复现测试，不允许直接调 dev-exe。
3. **cr 文档必删**：处理完即删，不留堆积。

---

## 与其它 skill 的协作

| 场景 | 链路 |
|---|---|
| `/cr` 走查发现问题 → 用户想修 | 用户手动启动 `/cr 复核` → 调 dev-plan → 用户 ack spec → 用户手动启动 dev-exe → 用户手动启动 dev-check |
| 一次性 Bug 直接修复 | `/cr` 仅出清单，用户自行编辑代码 |
| 复核发现 docs/cr 空 | 提示后退出，不擅自调 dev-plan |

`dev-plan` 接收到 cr 派来的 bug 修复场景时，必须遵守其铁律 2：先写**失败复现测试**（`test/features/{feature}/bug_{ID}_repro_test.dart`）且该测试必须在修复前 FAIL，才允许分析根因。cr 报告的 `file:line` + 现象描述作为 Bug 输入证据。

---

## 完成后汇报

走查模式：
```
═══════════════════════════════════
  cr 走查完成
═══════════════════════════════════
  走查范围：<范围描述>
  覆盖文件：N
  报告路径：docs/cr/cr-{ts}.md
  问题分布：Critical X / Major Y / Minor Z / Info W
  下一步：
    - 想修：手动编辑代码，或 /cr 复核 派生 dev-plan
    - 想看清单一问题：直接报告里查证据 file:line
═══════════════════════════════════
```

复核模式见上文第 5 步格式。