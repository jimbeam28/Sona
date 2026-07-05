#!/usr/bin/env bash
# cov-gate.sh — dev-exe 最终门禁 / dev-check 检查前一键流水线
# pubget → format --set-exit-if-changed → analyze --no-fatal-infos → test --coverage → coverage-check.sh check-exe
#
# 用法:
#   scripts/dev/cov-gate.sh [flags]
#     --skip-test  跳过 test 与 coverage
#     --skip-cov   跑 test 但不生成 lcov（不做门禁）
#     --no-pubget  跳过 flutter pub get
#     --only <stage>  只跑某阶段: pub-get | format | analyze | test | gate
#
# 退出码: 0 = 全过；非0 = 任一阶段失败
#
# 设计动机：原本 SKILL.md 中散见多条裸命令（flutter analyze / dart format / flutter test --coverage
# + awk 解 lcov），超时与组合都靠 agent 临时记忆。本脚本把 5 步确定性串起，每步自带预算。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/dev-task.sh"  # 引入 run_with_budget

B_PUBGET="${DEVV_BUDGET_PUBGET:-120}"
B_FORMAT="${DEVV_BUDGET_FORMAT:-180}"
B_ANALYZE="${DEVV_BUDGET_ANALYZE:-300}"
B_TEST="${DEVV_BUDGET_TEST:-1200}"   # coverage 跑得慢，给 20 分钟
B_GATE="${DEVV_BUDGET_GATE:-60}"

SKIP_TEST=0
SKIP_COV=0
SKIP_PUBGET=0
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-test)  SKIP_TEST=1; SKIP_COV=1; shift ;;
    --skip-cov)   SKIP_COV=1; shift ;;
    --no-pubget)  SKIP_PUBGET=1; shift ;;
    --only)       ONLY="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

want() {
  if [[ -n "$ONLY" ]]; then
    [[ "$ONLY" == "$1" ]]
  else
    return 0
  fi
}

FAIL=0

# Step 0: pub get 按需
if [[ $SKIP_PUBGET -eq 0 ]] && want pub-get; then
  NEED=0
  [[ ! -f pubspec.lock ]] && NEED=1
  [[ ! -d .dart_tool ]] && NEED=1
  [[ pubspec.yaml -nt pubspec.lock ]] && NEED=1
  if [[ $NEED -eq 1 ]]; then
    run_with_budget "$B_PUBGET" pub-get flutter pub get || FAIL=1
  else
    echo "==> [pub-get] SKIP (已是最新)"
  fi
fi

# Step 1: format
if want format && [[ $FAIL -eq 0 ]]; then
  run_with_budget "$B_FORMAT" format-check \
    dart format --set-exit-if-changed lib test || FAIL=1
fi

# Step 2: analyze
if want analyze && [[ $FAIL -eq 0 ]]; then
  run_with_budget "$B_ANALYZE" analyze \
    flutter analyze --no-fatal-infos --no-fatal-warnings || FAIL=1
fi

# Step 3: test (+ coverage)
if [[ $SKIP_TEST -eq 0 ]] && want test && [[ $FAIL -eq 0 ]]; then
  rm -rf coverage/
  if [[ $SKIP_COV -eq 0 ]]; then
    run_with_budget "$B_TEST" test+coverage \
      flutter test --coverage || FAIL=1
  else
    run_with_budget "$B_TEST" test \
      flutter test || FAIL=1
  fi
fi

# Step 4: critical_files 门禁
if [[ $SKIP_TEST -eq 0 && $SKIP_COV -eq 0 ]] && want gate && [[ $FAIL -eq 0 ]]; then
  if [[ ! -f coverage/lcov.info ]]; then
    echo "==> [gate] FAIL coverage/lcov.info 不存在"
    FAIL=1
  else
    run_with_budget "$B_GATE" coverage-gate \
      bash "$ROOT/docs/dev/scripts/coverage-check.sh" check-exe || FAIL=1
  fi
fi

echo "===================================================="
if [[ $FAIL -eq 0 ]]; then
  echo "  cov-gate: ALL PASS"
  exit 0
fi
echo "  cov-gate: FAILED"
exit 1