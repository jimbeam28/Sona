# SCHEMA — sona-dev 流程的唯一格式源

> 三个 skill（dev-plan / dev-exe / dev-check）引用本文件，不各自复制格式定义。
> 改格式只改这里。

---

## 1. dev-status.json

工作队列文件：`docs/dev/dev-status.json`。**所有读写经 `scripts/dev-status.sh`，禁止手拼 JSON。**

### 1.1 条目字段

| 字段 | 类型 | 说明 |
|---|---|---|
| name | string | 功能名 |
| spec_file | string | `docs/features/{ID}.md` |
| spec_anchored_files | string[] | 锚点文件清单（create 时校验存在，铁律） |
| scenarios / invariants / algorithms | string[] | 全部 spec ID（dev-exe 覆盖率门禁用） |
| test_files | string[] | 产出测试文件 |
| test_coverage_gaps | string[] | 未覆盖 ID（dev-exe 必补） |
| cross_module_impacts | string[] | 受影响 feature（由 `cross-imports.sh impact` 辅助识别） |
| manual_qa_required | bool | 涉平台原生 = true |
| manual_qa_file | string\|null | `docs/dev/mqa-{ID}.md` |
| user_acceptance_text | string | 固定 `见 {spec_file} §1.2` |
| impl_status | enum | pending / done / failed / blocked |
| test_status | enum | pending / passed |
| check_status | enum | pending / passed / round_N / blocked_after_rounds |
| check_round | int | dev-check 打回累计（0 起） |
| last_check_round_results | string | 指向 check_log.md 条目 |
| last_checked_at / last_updated | date | |
| dependencies | string[] | 依赖的 ID（全 done 才可实施） |
| retry_count / last_error | | dev-exe 失败记账 |

### 1.2 字段生命周期（谁能改什么）

| 时机 | 动作 | 命令 |
|---|---|---|
| dev-plan 创建条目 | 全字段初始化 pending，check_round=0 | `dev-status.sh create <ID> <name> <spec> <anchored...>` |
| dev-plan 补 ID 清单 | scenarios/invariants/algorithms/gaps | `dev-status.sh set <ID> <field> '<json>'` |
| dev-exe 全门禁通过 | impl=done, test=passed（**不动 check_**\*） | `set` |
| dev-check PASS | check=passed + last_checked_at；另刷覆盖率基线 | `dev-status.sh pass <ID>` + `coverage-check.sh refresh` |
| dev-check FAIL | check_round+1, check=round_N, impl/test 回 pending | `dev-status.sh bump-round <ID>` |
| 超 2 轮 FAIL | check=blocked_after_rounds, impl=blocked | `dev-status.sh block <ID>` |
| dev-plan 清理 | impl=done 且 test=passed 且 check=passed 的条目移出队列（spec 留存于 git 与 INDEX） | 手工编辑 + 同步 order/metadata |

### 1.3 编号

`dev-status.sh next-id <PREFIX>` — 扫 status.json 条目 + `docs/features/*.md` 文件名取下一个空闲号。模块前缀：CON / BRW / PLY / TMR / PRG / SET / INT；bug 专用 BUG-NN。

**门禁测试文件命名防撞名（cr-20260804-1922 §4 S5）**：BUG 条目命名门禁测试文件前，先 `grep -rn <候选文件名> test/` 确认无同名/近名文件。BUG 编号在跨 CR 轮次间会复用（如 9cd9ce2 轮 PRG2/BRW1 已占用 `test/features/browser/bug_11_repro_test.dart` / `bug_12_repro_test.dart`，与新一轮 BUG-11/BUG-12 撞名）——与既有文件冲突时改用全称形态（去连字符小写，如 `bug_bug11_test.dart`），**禁止覆盖或改名既有文件**。spec §5.4 登记的文件名必须与实际落盘文件名一致（spec-scan.sh --gate 按 §5.4 路径做存在性硬校验）。

---

## 2. spec 文档 docs/features/{ID}.md

骨架沿用 `docs/features/_TEMPLATE.md`，下列为 dev-plan 产出的**硬要求**（与模板冲突处以本节为准）：

| 章节 | 硬要求 |
|---|---|
| §0 元数据 | 照模板 yaml；bug 单特性折叠进父文档时不建新文件 |
| §1.0 原始需求 | **用户原话逐字引用**（跨会话/跨模型交接的唯一需求源，dev-check 核对用） |
| §1.2 用户视角表 | 纯中文无代码术语；**用户审的唯一部分** |
| §2 骨架 | 每条锚点 file:line；逆抽不得脑补 |
| §3 行为规约 | 每条 `{ID}-S{n}` 带 Code evidence；`status: new` 的每条**必带 `否定断言:` 块**；新需求 Scenario 写到**修改点级**：指明改哪个文件哪个函数、边界情况裁决，使弱模型不需判断即可实现 |
| §4 不变量 | 每条 `{ID}-INV{n}` 带证据 file:line |
| §6 算法样例 | ALG 锚点统一写全称 `[ID-ALG1-name]`（spec-scan 依赖） |
| §7 跨模块影响 | 用 `cross-imports.sh impact <锚点文件...>` 的输出辅助列引用方 |
| §8 平台特性 | 逐条列"真机风险列"：fake 测不到、只有真机会出问题的是什么；能近似测的写成测试，测不了的进 `docs/dev/mqa-backlog.md`；涉平台原生 → manual_qa_required=true |

**否定断言格式**（§3 GWT 块末尾）：
```
否定断言:
  - <不该发生的状态变化>（例：queue.length 不变）
  - <不该触发的事件/副作用>（例：不调用 IAudioHandler.play）
```
确无否定面写 `否定断言: 无`。`spec-scan.sh --neg <ID>` 做结构门禁。

---

## 3. 附属文件格式

### 3.1 docs/features/INDEX.md — 完整登记簿
功能/Bug 两张表，列：ID / 名称 / 状态 / 最近更新 / 主锚点文件 / S/INV/ALG（用 `spec-scan.sh --count`）/ impl/test/check / MQA / 在 status.json。dev-plan 每次产出后同步。

### 3.2 docs/dev/check_log.md — dev-check 问题清单
```
## [YYYY-MM-DD HH:MM] {ID} - 第 N 轮 dev-check
### 总 verdict: PASS / FAIL
### FAIL 问题清单
1. **{标题}**（检查项 N，@{ID}-S{n}）
   - 证据：file:line
   - 现象：...
   - 修复指令：{祈使句，精确到改哪个函数怎么改——dev-exe 弱模型照单执行}
```

### 3.3 docs/dev/mqa-backlog.md — 待真机清单（攒单制）
MQA 不阻塞 impl_status=done。每个 manual_qa_required 条目的验证项追加到此，格式：
```
## {ID} {名称}（追加于 YYYY-MM-DD）
- □ {验证步骤} — 期望：{...}
```
用户下次装真机时一次性跑完勾选。

### 3.4 docs/dev/baseline-coverage.json — 覆盖率基线
`docs/dev/scripts/coverage-check.sh` 管理：check-exe（dev-exe 门禁，critical ≥90%）/ check-check（dev-check 漂移检测）/ refresh（PASS 后刷基线，单调上行）。

### 3.5 docs/dev/arch-baseline.txt — 架构违规基线
`cross-imports.sh` 用；kind+file 粒度的 legacy debt 抑制清单，只减不增。

### 3.6 docs/dev/coverage-debt.txt — 覆盖率债务登记
`coverage-check.sh check-exe` 用：critical_files 中暂不达 90% 的文件登记 `<file> <floor%>`，豁免硬阈改守底线（不得低于登记值）。底线只能上调、条目只能删（达标后），新增须说明理由。

### 3.7 docs/cr/cr-{YYYYMMDD-HHMM}.md — 走查报告（cr skill）

时间戳精确到分钟防撞名。每条问题的字段：

| 字段 | 必填 | 说明 |
|---|---|---|
| 编号 | ✓ | 按类型前缀：B1（BUG）/ F1（FRAGILE）/ D1（DESIGN）/ T1（TEST-GAP） |
| 类型 | ✓ | BUG（复现路径确定）/ FRAGILE（条件触发）/ DESIGN（取舍待裁决）/ TEST-GAP（缺行为锚定） |
| 严重度 | ✓ | Critical / Major / Minor / Info |
| 维度 | ✓ | 架构一致性 / 正确性 / 并发时序 / 安全 / 可测性 / 性能 / 风格 / 功能-踩坑 / 功能-spec / 功能-测试锚定 / 功能-状态机 |
| 证据 | ✓ | `file:line` + 实际代码片段 |
| 复现路径 | BUG/FRAGILE 必填 | 用户操作或输入序列 → 期望行为 → 实际行为（代码推理）；写不出不得列 BUG |
| 自检答案 | BUG/FRAGILE 必填 | "现有测试为何没抓到"：测试空壳 / 分支零覆盖 / 测试假设错 |
| 修复建议 | ✓ | 改动方向，不给代码（改码权归 dev-exe） |

报告骨架：

```markdown
# 代码走查报告
> 生成时间：YYYY-MM-DD HH:MM
> 走查范围：<目录 / 功能 / git commit 列表 / 全量>
> 覆盖文件：N（含 impact 调用方 K 个）
> 问题总数：BUG X / FRAGILE Y / DESIGN Z / TEST-GAP W

## 摘要
<一段话概括总体健康度与主要风险点>

## 问题清单
### BUG
#### B1. <问题标题>
- 类型 / 严重度 / 维度 / 证据 / 复现路径 / 自检答案 / 修复建议
### FRAGILE
### DESIGN
### TEST-GAP

## 已检查文件清单
<必须真实覆盖第 1 步解析的全部文件（含 impact 调用方），便于复核追溯>
```

---

## 4. 脚本目录（确定性操作全在这里，skill 不裸跑等价命令）

| 脚本 | 用途 | 退出码语义 |
|---|---|---|
| `dev-status.sh` | dev-status.json 唯一读写入口（list/show/field/pending/impl-ready/next-id/create/set/bump-round/pass/block） | 1=业务错误 2=参数错 |
| `cov-gate.sh` | dev-exe 最终门禁一条龙：pubget→format→analyze(0 warnings)→test --coverage→critical 覆盖率 | 0=全过 |
| `coverage-check.sh`（docs/dev/scripts/） | 覆盖率三门禁：check-exe / check-check / refresh | 1=失败 2=数据缺 |
| `spec-scan.sh` | spec 机械扫描：默认覆盖矩阵 / --neg 否定断言结构检查 / --count ID 计数 | --neg 缺失=1 |
| `cross-imports.sh` | 架构门禁：domain-flutter / feature-isolation / secret-logs / all；`impact <files...>` 反查引用方 | 有未基线违规=1 |
| `repro-test.sh` | bug 复现测试双态门禁：`<test_path> fail|pass`；区分 rc=1(测试 FAIL) 与 rc≥2(编译错/超时) | 0=符合预期 |
| `dev-task.sh` | 超时预算运行器（cov-gate 内部库） | 124=超时 |

脚本路径：`.claude/plugins/sona-dev/scripts/`（coverage-check.sh 在 `docs/dev/scripts/`）。

---

## 5. 全局裁决：错误处理纪律（catch-log）

> cr-20260804-1922 §4 S6 单源化：复核判据「catch 可接受的前提是有日志」（CON1/BUG-19/LIST6/O7 同标准）升格为全局裁决。spec 不再逐条重复本裁决，引用本节即可。

- **静默吞错禁止**：任何 `catch` / `catchError` 必须先留日志（`debugPrint` 或 LogBuffer）才允许吞掉异常。dev-check / cr 复核遇无日志的静默 catch 一律按问题列出。
- **日志不得含凭证**：catch 日志遵守 secret-logs 门禁（`cross-imports.sh secret-logs`）——不打印密码明文；异常文本可能回显含 userinfo 的 URL 时先脱敏（参照 `redactUrlForLog` 用法）。
- **例外——spec 显式裁决的沉默**：spec 明文裁决允许静默的 catch 不受本条约束，但 spec 必须注明依据。现有清单：
  - `lib/core/services/audio_handler.dart` 六方法对平台调用超时/错误的静默 catch——BUG-17 spec 裁决「timeout 触发 → catch 静默处理，与 play/pause/stop 行为一致」（P4 平台坑：平台调用失败不向用户冒泡）；其中 play() 内层 completed 恢复 seek 的静默 catch 另见 BUG-05-S1 裁决「seek 失败不阻塞 play 调用」。
  - `lib/features/connection/domain/connection_service.dart` delete 的密码清理失败——BUG-24-S3 best-effort 裁决（DAO 已成功，存储清理失败仍吞，但**日志照留**，c8c0314）。
- **裁决冲突处理**：spec 文字与本裁决冲突时（如 BUG-32-S1 曾出现的表述张力），dev-plan 修订 spec 显式对齐本节；实现侧不得自行在「吞」与「日志」之间来回改。
