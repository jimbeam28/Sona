# sona-dev plugin

Sona 项目的开发工作链 plugin：dev-plan / dev-exe / dev-check / cr 四个 skill 一组，
配套把所有**确定性命令**收编为脚本，skill 通过脚本间接执行，避免 agent 裸跑 bash
踩超时 / 误算 timeout / 重复拼接。

## 目录结构

```
.claude/plugins/sona-dev/
├── plugin.json                       # plugin 元数据
├── README.md                         # 本文件
├── skills/
│   ├── dev-plan/SKILL.md
│   ├── dev-exe/SKILL.md
│   ├── dev-check/SKILL.md
│   └── cr/SKILL.md
└── scripts/                          # 所有确定性脚本（skill 通过相对 `../scripts/` 调用）
    ├── dev-task.sh                   # 带时间预算跑任一命令（flutter test --coverage 默认 1200s）
    ├── dev-status.sh                 # 读 / 改 docs/dev/dev-status.json
    ├── repro-test.sh                 # Bug 复现测试必须 FAIL / 修复后必须 PASS 门禁
    ├── spec-scan.sh                  # 解析 {ID}.md §3/4/6 ID 列表 + test/ 命中矩阵
    ├── cross-imports.sh              # Domain 零 Flutter / Feature 隔离 / 密码泄露日志
    ├── cov-gate.sh                   # dev-exe 第 7 步一条龙：pubget+format+analyze+test+coverage 门禁
    ├── cov-drift.sh                  # dev-check 检查 6 基线漂移 / PASS 后刷基线
    ├── git-scope.sh                  # git log/show/diff 范围扫描
    └── neg-assert.sh                 # §3 否定断言提取 + test 命中查
```

## 加载机制

opencode 自动扫描 `.claude/skills/*/SKILL.md`。本 plugin 的 skill 实际位于
`.claude/plugins/sona-dev/skills/{name}/`，通过软链接挂回 `.claude/skills/{name}`：

```
.claude/skills/dev-plan   -> ../plugins/sona-dev/skills/dev-plan
.claude/skills/dev-exe    -> ../plugins/sona-dev/skills/dev-exe
.claude/skills/dev-check  -> ../plugins/sona-dev/skills/dev-check
.claude/skills/cr         -> ../plugins/sona-dev/skills/cr
```

git 跟踪软链接，clone 后无需额外 install 步骤即可生效。

## 脚本调用约定

每个 skill SKILL.md 顶部"脚本调用铁律"小节已列该 skill 用到的脚本清单。原则：

1. **凡表中已列动作，必须** `bash ../scripts/<name>.sh ...` 调用。
2. 脚本内部已自带 timeout 预算（核心是 `flutter test --coverage` 默认 1200s），
   bash 工具单次调 `bash ../scripts/cov-gate.sh` 即可，调用方无须再传 timeout。
3. 探索类动作（`grep`/`read` 定位代码、Agent 写代码、写报告）属非确定性，仍走 opencode 工具，不固化。

## ROOT 路径推算

所有脚本的 `ROOT` 均通过 `cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd`
解析，从 plugin 内 `.claude/plugins/sona-dev/scripts/` 上溯 4 级到项目根。
**移动 plugin 目录时无需改脚本**。

## 维护策略

- 新增确定性命令：在 `scripts/` 加新 `.sh`，同步在 `plugin.json` 的 `scripts` 数组登记。
- skill 文本调整：只动对应 `skills/<name>/SKILL.md`，软链接无需重建。
- 共享脚本破坏性改动须跑全部相关 skill 的冒烟测试。