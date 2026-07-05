#!/usr/bin/env bash
# cov-drift.sh — dev-check 检查 6 "基线覆盖率漂移" + dev-check PASS 后刷基线
#
# 用法:
#   scripts/dev/cov-drift.sh check          # 当前 lcov vs baseline-coverage.json，任一下降超容忍 FAIL
#   scripts/dev/cov-drift.sh refresh        # 把当前 lcov 写入 baseline-coverage.json (PASS 后调)
#
# 是 docs/dev/scripts/coverage-check.sh 的薄封装，统一调用入口；保留原始脚本以便兼容单跑。
#
# 退出码同步 coverage-check.sh: 0 / 1 / 2
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

SUB="${1:-}"
case "$SUB" in
  check)   bash docs/dev/scripts/coverage-check.sh check-check ;;
  refresh) bash docs/dev/scripts/coverage-check.sh refresh ;;
  *)
    cat <<EOF
usage: $0 {check|refresh}
  check   dev-check 检查 6：当前 lcov vs baseline-coverage.json 漂移检测
  refresh dev-check PASS 后刷基线快照
EOF
    exit 2 ;;
esac