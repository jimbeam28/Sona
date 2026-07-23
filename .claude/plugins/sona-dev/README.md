# sona-dev plugin

Sona 开发工作链：dev-plan / dev-exe / dev-check / cr 四个 skill + 确定性脚本层 + reference 规约。

**设计原则**：
1. skill 只写必要步骤与硬约束，格式细节全部单源化到 `reference/SCHEMA.md`
2. 确定性操作全部脚本化（退出码即证据，弱模型报不了假）；语义判断留给模型
3. 按模型能力分层执行：**强模型 dev-plan（设计）→ 弱模型 dev-exe（实施）→ 强模型 dev-check（审计）**

## 目录结构

```
.claude/plugins/sona-dev/
├── plugin.json
├── README.md
├── reference/
│   ├── SCHEMA.md                     # 唯一格式源：dev-status.json 字段生命周期 / spec 章节要求 /
│   │                                 #   check_log / mqa-backlog / INDEX / cr 报告 格式 / 脚本目录
│   └── cr-dimensions.md              # cr 走查执行细则：硬约束 / 三层 checklist / 功能层四锚定法 / 自检细则
├── skills/
│   ├── dev-plan/SKILL.md             # 访谈 → 逆抽 → spec 落地（≤100 行）
│   ├── dev-exe/SKILL.md              # 测试先行 → 实现 → 脚本门禁（≤110 行）
│   ├── dev-check/SKILL.md            # 3 项判断审计 + 机械项走脚本（≤80 行）
│   └── cr/SKILL.md                   # 通用代码走查（三层检查 + 功能缺陷分析，独立于三 skill 链）
└── scripts/                          # 确定性门禁（skill 相对 `../../scripts/` 调用）
    ├── dev-status.sh                 # dev-status.json 唯一读写入口（create 校验锚点存在 / next-id / 状态流转）
    ├── cov-gate.sh                   # dev-exe 最终门禁一条龙：pubget+format+analyze(0 warning)+test+覆盖率
    ├── spec-scan.sh                  # spec 机械扫描：覆盖矩阵 / --neg 否定断言结构 / --count 计数
    ├── cross-imports.sh              # 架构门禁：feature 隔离 / Domain 零平台依赖 / 敏感日志；impact 反查引用方
    ├── repro-test.sh                 # Bug 复现测试双态门禁（区分测试 FAIL 与编译错/超时）
    └── dev-task.sh                   # 超时预算运行器（cov-gate 内部库）
```

另：`docs/dev/scripts/coverage-check.sh`（覆盖率三门禁：check-exe / check-check / refresh）。

## 配套数据文件（docs/dev/）

- `dev-status.json` — 工作队列（经 dev-status.sh 读写）
- `platform-pitfalls.md` — 真机踩坑库（dev-plan 设计前核对，dev-exe 修真机 bug 后回写）
- `arch-baseline.txt` — 架构违规基线（legacy debt 抑制，只减不增）
- `baseline-coverage.json` — 覆盖率基线（dev-check PASS 后单调上行）
- `check_log.md` / `mqa-backlog.md` — 评审问题清单 / 待真机攒单

## 加载机制

skill 经软链接挂载：`.claude/skills/{dev-plan,dev-exe,dev-check,cr}` → `../plugins/sona-dev/skills/*`，git 跟踪软链接，clone 后即生效。

## 维护约定

- 脚本 ROOT 经 `BASH_SOURCE` 上溯 4 级解析，移动 plugin 目录无需改脚本
- 格式变更只改 `reference/SCHEMA.md`；skill 文本保持精简（步骤 + 约束）
- CI 架构边界检查（`.github/workflows/ci.yml`）直调 `cross-imports.sh all`，与本地门禁同源
