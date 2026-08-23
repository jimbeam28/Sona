#!/usr/bin/env bash
# dev-task.sh — 公共任务运行器：带时间预算跑任一 shell 命令，超时/非零退出即报错
#
# 设计动机：bash 工具默认 timeout=120s，对 flutter test --coverage 远不够；
# 调用方每次手算 budget 易踩坑。本脚本统一封装 "预算 + label + 输出摘要"。
#
# 由其它脚本以"内部库"形式 source 后调 run_with_budget，亦可直接 CLI 用：
#   scripts/dev/dev-task.sh <budget_sec> <label> <cmd...>
#
# 退出码：
#   0     = 命令成功
#   124   = 超时
#   其它  = 命令自身退出码
set -euo pipefail

# 仅在直接 CLI 调用时执行 arg 解析与末尾调用；被 source 时跳过
DEV_TASK_RUN_AS_CLI=0
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  DEV_TASK_RUN_AS_CLI=1
fi

if [[ "${DEV_TASK_RUN_AS_CLI:-0}" == "1" ]]; then
  if [[ $# -lt 3 ]]; then
    echo "usage: $0 <budget_sec> <label> <cmd...>" >&2
    exit 2
  fi
fi

run_with_budget() {
  local budget="$1"; shift
  local label="$1"; shift
  local start_ts; start_ts=$(date +%s)
  echo "==> [$label] 开始 (预算 ${budget}s)"
  local rc=0
  # 注意：不能写 `if ! timeout ...; then rc=$?` —— 取反管线的 $? 是 0，
  # 失败会被吞掉（门禁以退出码为准，铁律 3）
  timeout "${budget}" "$@" || rc=$?
  local elapsed=$(( $(date +%s) - start_ts ))
  if [[ $rc -eq 124 ]]; then
    echo "==> [$label] FAIL 超时 (${elapsed}s > ${budget}s 预算)" >&2
    return 124
  elif [[ $rc -ne 0 ]]; then
    echo "==> [$label] FAIL 退出码=$rc (${elapsed}s)" >&2
    return $rc
  fi
  echo "==> [$label] OK (${elapsed}s)"
  return 0
}

# 直接 CLI 调用时
if [[ "${DEV_TASK_RUN_AS_CLI:-0}" == "1" ]]; then
  run_with_budget "$@"
fi