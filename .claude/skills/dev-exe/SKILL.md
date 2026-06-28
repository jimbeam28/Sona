---
name: dev-exe
description: |
  按 docs/features/{ID}.md 详细设计文档实现代码、写测试、做验证。三 Agent 分离（测试先行 → 实现 → spec 覆盖门禁），平台特性失败强制手动 QA。
  触发场景：用户提到"开始开发"、"实现"、"执行计划"、"dev-exe"，或任何明确按已有计划实现代码的请求。
  不触发：用户提到"分析"、"规划"、"制定计划"时——应由 dev-plan 处理。
  注意：当用户给出功能编号（如 CON-01），如果文档 `docs/features/{ID}.md` 不存在或 `dev-status.json` 中无对应条目 → 提示先执行 dev-plan。
---

# 代码实现 (dev-exe)

按 `docs/features/{ID}.md` 详细设计文档实现代码与测试。
**核心原则**：测试先行（只读 spec）、实现按 spec、验证对 spec 覆盖——而不是对"是否跑得过"打勾。

## 三条铁律

1. **测试与实现分离**：测试 Agent 只能读 `docs/features/{ID}.md` 的 §3 / §4 / §6，**不能读现有实现代码**——避免测试贴合实现而非贴合规约。
2. **Spec 覆盖门禁**：验证 Agent 必须确认 §3 每条 Scenario、§4 每条不变量、§6 每条算法样例都有对应 test。**< 100% 覆盖 = FAIL**，不允许标 done。
3. **手动 QA 门禁**：`§0 manual_qa_required = true` 时，`impl_status = done` 必须等待 `docs/dev/mqa-{ID}.md` 全部步骤勾选完毕。**严禁**自动标 done。

---

## 输入

可选的功能**条目编号**（如 `CON-01`、`BUG-03`）：
- **有编号**：只处理该条目（单条模式）
- **无编号**：循环处理所有 pending 条目（批量模式）

## 前置：读取上下文

读取以下文件，缺一不可：
- `docs/dev/dev-status.json` — 进度跟踪
- `docs/features/{ID}.md` — 详细设计文档（**核心**，dev-exe 严格按此实施）
- `docs/features/_TEMPLATE.md` — 字段定义（仅参考，不参与实施）
- `test/features/{feature}/bug_{ID}_repro_test.dart`（**Bug 修复时**，必须确认已 FAIL）

---

## 单条模式工作流

### 第 1 步：解析条目配置

1. 从 `dev-status.json` 的 `items` 中找到目标条目
2. 提取：`name`、`spec_file`、`scenarios`、`invariants`、`algorithms`、`test_coverage_gaps`、`cross_module_impacts`、`manual_qa_required`、`dependencies`、`impl_status`
3. 该条目**同时**满足以下条件才允许实施：
   - `spec_file` 指向的 `docs/features/{ID}.md` 实际存在
   - `dependencies`（含传递依赖）全部 `impl_status = done`
   - `impl_status` 非 `blocked`（blocked = 需人工介入）
4. Bug 修复场景：必须确认 `docs/features/{ID}.md` 中已记录复现测试路径，且测试文件存在并当前 FAIL
5. **dev-check 打回场景（关键）**：检查 `check_round` 字段——
   - `check_round > 0` → 本轮是 dev-check 打回后的返工。**必须**读 `docs/dev/check_log.md` 最末条目作为本轮修复靶点清单：
     - 每个问题点（"证据：file:line"）必须在本次实现中被显式修复
     - 修复后不允许跳过原 §3 其它 Scenario 的覆盖门禁
     - 完成后在 `docs/dev/dev_log.md` 追加："第 N 轮 dev-check 返工修复点：[问题清单]"——便于追溯
   - `check_round == 0` 或缺失 → 首轮开发，正常流程
6. `check_status == "blocked_after_3_rounds"` → **停止**，提示用户该条目已被 dev-check 3 轮打回，需人工介入

**向用户确认：**
- 条目编号、名称
- §1.2 用户视角 Scenario 表（用户已审过，但执行前再呈现一次）
- 涉及文件
- 依赖项状态
- 平台特性 manual_qa_required
- 若为 dev-check 打回：呈现上一轮问题清单及本轮修复靶点

### 第 1.5 步：收集代码上下文

实施前给三个后续 Agent 共用的代码上下文：
1. 读 `docs/features/{ID}.md` §0 中 `spec_anchored_files` 列出的每个文件
2. 读 §2 中 §2.1 文件清单和 §2.2 Provider 表涉及的所有文件
3. 读 `test/helpers/` 已有的 fakes / mocks / test_database / widget_helpers 清单（避免重复造轮子）
4. 汇总为结构化上下文：
   - 既有代码（按 spec_anchored_files 排序）
   - 已有测试文件清单
   - 测试工具清单（mockito / sqflite_ffi / fake_async / ProviderContainer / widget test helper）

### 第 2 步：测试先行（Agent A — 只读 spec）

启动新 Agent，**只**看 `docs/features/{ID}.md`，不看实现代码：

Agent prompt 必须包含：
- `docs/features/{ID}.md` 全文（§3 / §4 / §6 用于测试，§1.2 用于命名测试用例）
- `test/helpers/` 现存 fakes / mocks 清单
- 测试工具配置说明（mockito、sqflite_ffi、fake_async、ProviderContainer 等）
- **强制约束**：
  - 每一个 `§3 Scenario {ID}-S{n}` 须有 ≥1 个 test，按 Scenario ID 命名：`test('{ID}-S{n}: {场景描述}', () { ... })`
  - 每一个 `§4 INV {ID}-INV{n}` 须有 ≥1 个 test，按 INV ID 命名：`test('{ID}-INV{n}: {不变量一句话}', () { ... })`
  - 每一个 `§6 ALG {ID}-ALG{n}` 须有黄金样例 + 边界 + 异常 三档 test
  - **禁止读 `lib/` 实现代码**——只能基于 spec 写测试
  - Bug 修复时：**先在 `test/features/.../bug_{ID}_repro_test.dart` 已存在的失败测试基础上**新增修复后预期 PASS 的 Scenario 测试

Agent A 输出：
- 测试文件路径列表（可能新建 / 可能扩展现有 test 文件）
- 每条 Scenario / INV / ALG 对应的测试函数签名（不要求实现完整 body——但是断言必须已写出）
- 测试无法独立写出的"阻塞点"清单（如某 Scenario 涉及平台原生，需手动 QA 兜底）

**注意**：Agent A 此时**不运行测试**——他知道当前没有实现，测试 FAIL 是必然的。他的产出是测试骨架 + 断言。

### 第 3 步：实现代码（Agent B — 按 spec 实现）

启动新 Agent，读 `docs/features/{ID}.md` 全文 + Agent A 输出的测试文件，按要求实现。

Agent B prompt 必须包含：
- `docs/features/{ID}.md` 全文（§2 锚点用于定位修改位置）
- Agent A 输出的测试文件清单与断言要求
- 第 1.5 步收集的代码上下文
- 架构约束：
  - 分层：UI → Provider → Domain → Contract
  - Domain 层零 Flutter 依赖
  - 跨 feature 依赖通过 `shared/di/providers.dart`，禁止 feature 间直接 import
  - 类型安全：禁用 `as any` / `dynamic` 替身等价，必须有显式类型
- **强制约束**：
  - 严格按 §2 锚点定位修改位置，不自行全项目搜索
  - 不允许跳过 §3 任一 Scenario；
  - 不允许违反 §4 任一不变量
  - Bug 修复场景：必须使 `bug_{ID}_repro_test.dart` 测试 PASS（这是修复已落地的硬指标）
  - 增量新代码必须补充单元/集成测试覆盖（不能依赖 widget test 代偿 domain 测试）
- **平台原生事项**（涉及时）：通知栏、锁屏、AudioFocus、后台 service 等 fake 测了等于没测，必须在 Agent B 实施完成后自动产出 `docs/dev/mqa-{ID}.md` 模板，等待用户手动 QA 勾选

Agent B 输出：
- 修改/创建的代码文件列表（含每条修改对应哪个 Scenario）
- 实现决策记录（计划有多种实现方式时记录选择）
- §7 跨模块影响是否会触发其它 feature 的回归断言变化（说明会否触发哪些旧 test 失败）

**注意**：Agent B **不修改测试断言**——若某 Agent A 已写测试因实现方案选择无法通过，Agent B 必须回头在 §3 spec 内重新协商 Scenario 描述。**严禁**通过修改测试断言来"通过"。

### 第 4 步：运行测试 + 修复实现（本地执行，不另启 Agent）

在本会话直接执行：

1. `flutter test test/features/{feature}/`
   - Bug 修复复现测试**必须 PASS**（否则修复无效）
   - Agent A 新写测试若 FAIL：
     - FAIL 原因是断言错误 → Agent B 实现错，修实现
     - FAIL 原因是 spec 本身歧义 → 回 dev-plan 修 §3，**严禁**直接改测试
2. **回归测试**：`flutter test`（全量）
   - 任一原测试 FAIL = **未完成**——说明本次改动影响了别的不变量
   - 回到 §7 跨模块影响清单确认是否已识别；未识别 = spec 漏分析
3. `flutter analyze --no-fatal-infos`：必须 0 warnings（infos 可接受）
4. `dart format --set-exit-if-changed lib test`：必须无变更

**修复循环上限**：5 轮。任一项 5 轮后未通过 → `impl_status = failed`，`retry_count += 1`，向用户报告。retry_count ≥ 3 → `blocked`。

### 第 5 步：Spec 覆盖门禁验证（Agent C — 对 spec 不对实现）

启动新 Agent 验证 spec 覆盖率，**不**对实现是否"看起来对"，只对"每条 spec 是否被测"做硬门禁：

Agent C prompt 必须包含：
- `docs/features/{ID}.md` 全文
- Agent A 输出的测试文件清单
- Agent B 输出的代码文件清单 + 实现决策记录
- **强制验证项**：
  1. §3 每条 Scenario 都能在测试中找到一条对应 `test('{ID}-S{n}: ...')`
  2. §4 每条不变量都能在测试中找到至少一条对应断言（`grep '{ID}-INV{n}' test/`）
  3. §6 每条算法样例都有典型 + 边界 + 异常 三档测
  4. §7 跨模块影响每条都在 `test/features/{cross_module}/` 或 `test/features/coverage/` 下有相应回归断言
  5. Bug 修复场景：`bug_{ID}_repro_test.dart` 现 PASS（运行确认）

Agent C 输出：
- 覆盖矩阵（Scenario → test 文件 / INV → test 文件 / ALG → test 文件； missing 行单列）
- 不满足任一项 → 返回 `spec_coverage: FAIL` + 缺失清单
- 缺失项必须由 Agent A 补完，再次进 Agent C 验证（循环上限 3 轮）

**Spec 覆盖门禁**：循环结束后任然 < 100% → `impl_status = failed`，向用户报告。

### 第 6 步：手动 QA 门禁（若 §0 manual_qa_required = true）

1. 实现 Agent（步骤 3）已产出 `docs/dev/mqa-{ID}.md` 初稿
2. dev-exe 输出该文件路径给用户，并要求用户：
   - 在真机 / 模拟器上跑完每步
   - 手动勾选每条
   - 失败项写明失败现象
3. **只有所有手动 QA 项都勾选了"已通过"，dev-exe 才允许把 impl_status 标 done**
4. 用户当前不在场或拒绝执行 → `impl_status = "blocked"`, `last_error = "等待手动 QA"`

### 第 7 步：静态分析与回归与覆盖率（最终门禁）

**在本会话直接执行（不使用 Agent）：**

1. `flutter analyze --no-fatal-infos` —— 0 warnings
2. `dart format --set-exit-if-changed lib test` —— 无变更
3. `flutter test` —— 全量回归通过
4. `flutter test --coverage` —— 输出 `coverage/lcov.info`，**强制门禁**（不再"参考"）

**覆盖率门禁（关键路径守护）：**

读取 `docs/dev/baseline-coverage.json` 获取 `critical_files` 清单与 `baseline_overall` 值，按 4 项检查：

| 项 | 阈值 | 怎么测 |
|---|---|---|
| critical_files 单文件覆盖率 | ≥ 90% | 从 lcov.info 解析每文件 LF / LH 比率 |
| critical_files 总体覆盖率 | ≥ baseline_overall − 2% | 同上累加 |
| 任一 critical_files 文件 | 不得从基线下降 | 比 baseline-coverage.json 中对应文件 coverage% 任一下降即 FAIL |
| 新增 critical_files 文件 | 100% 覆盖 | 文件被列入 `critical_files` 但基线中无对应行 → 视为新增，必须 100% |

**critical_files 默认清单（基线无文件时退化用）：**
- `lib/shared/models/play_queue.dart`
- `lib/features/player/domain/playback_orchestrator.dart`
- `lib/features/player/domain/play_mode.dart`
- `lib/features/player/domain/seek_utils.dart`
- `lib/features/player/domain/speed_manager.dart`
- `lib/features/browser/domain/cache_policy.dart`
- `lib/features/browser/domain/navigation_stack.dart`
- `lib/features/progress/domain/progress_policy.dart`
- `lib/features/connection/domain/connection_validator.dart`
- `lib/features/playlist/domain/playlist_service.dart`
- `lib/features/timer/domain/timer_service.dart`
- `lib/features/settings/domain/settings_service.dart`
（domain 层全部 + PlayQueue 共享模型——这层是 bug 高发区，覆盖率必须高）

**解析 lcov.info 脚本（直接 fork 到 sh）：**
```bash
# 关键路径单文件覆盖率
for f in "${CRITICAL_FILES[@]}"; do
  perc=$(awk -v f="$f" '
    /^SF:/ { cur = substr($0, 4); if (cur == f) { found=1; lf=0; lh=0 } else { found=0 } }
    found && /^LF:/ { lf += substr($0, 4) }
    found && /^LH:/ { lh += substr($0, 4) }
    END { if (lf > 0) printf "%.2f", 100.0 * lh / lf; else print "0" }
  ' coverage/lcov.info)
  if (( $(echo "$perc < 90" | bc -l) )); then
    echo "COVERAGE FAIL: $f 覆盖率 $perc% < 90%"; exit 1
  fi
done
```

基线无 `docs/dev/baseline-coverage.json` 时（基线未建立）：本步只打印每文件覆盖率 + 总覆盖率，**不强制阈值**，但必须把当前 lcov.info 结果作为本次 dev-exe 的输出发给 dev-check 作为基线对照源。dev-check 通过后由它把 lcov.info 写入 baseline-coverage.json。

任一覆盖率门禁不满足 → 回 Agent B 补测试 / 修实现。修复循环上限：3 轮。

**质量门禁汇总**：
| 门禁项 | 阈值 | 失败动作 |
|---|---|---|
| Step 4 现有测试 FAIL | 0 个 FAIL | 修实现 |
| Step 4 Bug 复现测试 PASS | 必须 PASS | 修复无效 → 回 dev-plan |
| Step 4 全量回归 | 全部 PASS | 出现旧测试 FAIL → 跨模块影响未被识别 → 回 dev-plan §7 |
| Step 5 Spec 覆盖 | 100% | 补测试 |
| Step 6 手动 QA | 100% 勾选 | 等待用户 |
| Step 7 静态分析 | 0 warnings | 修代码 |
| Step 7 格式 | 0 变更 | 格式化 |
| Step 7 critical_files 覆盖率 | 各 ≥ 90%，总 ≥ baseline-2% | 补测试 |
| Step 7 新增 critical_files | 100% 覆盖 | 补测试 |

任一项不满足 → 视为未完成。**严禁**绕过门禁提交代码。

### 第 8 步：标记 done 与 dev-check 提醒

**所有 1-7 步门禁都通过后**：
1. 更新 `dev-status.json`：
   ```json
   "impl_status": "done",
   "test_status": "passed",
   "last_updated": "{YYYY-MM-DD}"
   ```
   **不写** `check_status`（dev-check 还没跑）——若已存在 `check_status` / `check_round` 字段（dev-check 打回的返工场景）则**保留**，dev-check 会读它们决定本轮是第几轮。
2. 提示用户：
   ```
   ✅ {ID} 实施完成，已通过 dev-exe 内部门禁
       （spec 覆盖率 / 回归 / 静态分析 / 格式 / 手动 QA / 关键路径覆盖率）
   
   本次 lcov.info 摘要：
     critical_files 总覆盖率: {X}%
     critical_files 单文件最低: {file} {Y}%
     全量 lcov.info 已保存 coverage/lcov.info
   
   下一步建议：
   手动启动 dev-check {ID} —— 由独立视角评审 spec 贴合度、实现忠实度、跨模块破坏、跨模块漏识、基线漂移
   ```
3. **不自动启动 dev-check**——dev-check 是独立视角，必须由用户手动启动以确保独立审查不被 dev-exe 流程框住。

---

## 批量模式工作流

### 循环前：环境检查

1. git 仓库有 origin 且可 push
2. `docs/dev/dev-status.json` 存在
3. `docs/dev/dev_log.md` 存在（不存在则创建）

### 循环体（每轮一个条目）

**步骤 A：选择条目**

读 `dev-status.json` 的 `order` 数组，按顺序找第一个 `impl_status = pending`：
- 跳过依赖未完成项
- 跳过 `blocked` 项

无 pending → 报告完成并结束。

显示进度：
```
─── 进度 [N/M] ───
  当前: [编号] - [名称]
  §0 manual_qa_required: true | false
  已完成: N 个 | 剩余: M 个 | 失败: K 个 | 阻塞: J 个
──────────────────
```

**步骤 B：执行单条模式工作流第 1-7 步**

**步骤 C：追加日志到 `docs/dev/dev_log.md`**

```markdown
## [YYYY-MM-DD HH:MM] [编号] - [名称]

**状态**: ✅ 成功 / ⚠️ 失败（原因）
**§0 manual_qa_required**: true | false
**§6 手动 QA**: 已完成 / 等待用户

### 修改文件
- `lib/path/to/file.dart` — 说明（@{ID}-S{n}）

### 测试结果
- 通过: X / 总计: Y
- Bug 复现测试: PASS | FAIL
- 全量回归: PASS | FAIL
- Spec 覆盖: 100% | 缺失：[清单]

### 手动 QA 项（若有）
- 文档: docs/dev/mqa-{ID}.md
- 状态: 全部勾选 | 待勾选
```

**步骤 D：更新 `dev-status.json` 并提交**

1. 更新条目状态：
   - 成功（手动 QA 已完成或不需要）：
     ```
     impl_status = "done"
     test_status = "passed"
     last_updated = "{YYYY-MM-DD}"
     ```
   - 实施中失败：
     ```
     impl_status = "failed"
     retry_count += 1
     last_error = "失败原因摘要"
     ```
   - 手动 QA 待用户：保留 `impl_status = "pending"`，但增加字段 `"pending_manual_qa": true`，**不**视为失败
   - `retry_count >= 3` 且非待手动 QA：`impl_status = "blocked"`
2. **提交前强制**：运行 `flutter analyze --no-fatal-infos`，0 warnings 才允许提交
3. Git 提交（**手动 QA 已完成才提交**）：
   ```bash
   git add -A
   git commit -m "feat: {ID} - {名称}"
   git push
   ```
   提交信息格式：
   ```
   feat: {ID} - {名称}

   - 修改文件: lib/path/a.dart, lib/path/b.dart
   - 测试: X/Y 通过
   - 静态分析: 0 issues
   - Spec 覆盖: 100%
   - 手动 QA: 已完成（Y/N 项）/ 不涉及
   ```
4. **手动 QA 待用户场景**：dev-exe 暂停，输出提示给用户：
   ```
   ⏸ [编号] 实施完成，等待手动 QA
   请运行 docs/dev/mqa-{ID}.md 所有步骤并勾选，
   完成后告知我或者直接说"[编号] QA 通过"——再继续 push。
   ```

**步骤 E：继续下一个 / 等待 QA**

---

## 中断处理

| 中断类型 | 处理 |
|----|----|
| 单条目 5 轮修复未通过 | `failed`，retry_count+1，记录 last_error，继续下一个 |
| 单条目 retry_count = 3（非待 QA） | `blocked`，跳过，单独汇报 |
| git push 失败 | 暂停，等用户处理 |
| 依赖未完成 | 跳过，单列汇报 |
| 手动 QA 待用户 | `pending_manual_qa=true`，不视为失败，但 push 等用户 ack |

---

## 完成后汇报

```
═══════════════════════════════════
  实现完成
═══════════════════════════════════
  条目编号:        {ID}
  名称:            ...
  修改文件:        N 个
  新增/修改测试:    M 个文件
  Spec 覆盖:        100% （n Scenarios + m INV + k ALG）
  Bug 复现测试:     PASS（仅 Bug 修复）
  静态分析:         0 warnings
  全量回归:         PASS
  §6 手动 QA:       已完成 / 不涉及 / 待用户（mqa-{ID}.md）
  跨模块影响回归:    n 项（其中 m 项被识别并补足，无新失败）
  关键路径覆盖率:   critical_files 总 {X}% / 各 ≥ 90% / 新增 100%
═══════════════════════════════════
```

---

## 失败上报

任一硬门禁不通过，向用户输出汇总：

1. 失败的具体门禁项（spec 覆盖不足 / 全量回归 FAIL / 提交失败 / 静态分析 FAIL / 手动 QA 不通过）
2. 失败原因（如旧测试失败的具体 test 名与现象）
3. 已尝试的修复轮次
4. 建议下一步：
   - Bug 已识别属于变更影响 → 回 dev-plan §7 重评估
   - Spec 自身歧义 → 回 dev-plan §3 改 Scenario
   - 平台行为无法自动化 → 转 mqa-{ID}.md
   - 已 3 轮失败 → 标 `blocked`，建议用户亲自介入