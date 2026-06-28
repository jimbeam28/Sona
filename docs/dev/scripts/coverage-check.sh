#!/usr/bin/env bash
# coverage-check.sh — 由 dev-exe 第 7 步 与 dev-check 第 6 项调用
#
# 用法:
#   ./docs/dev/scripts/coverage-check.sh check-exe   # dev-exe 用：守 critical_files 单文件 ≥90%, 新增 100%
#   ./docs/dev/scripts/coverage-check.sh check-check # dev-check 用：当前 lcov vs baseline-coverage.json，下降超容忍 FAIL
#   ./docs/dev/scripts/coverage-check.sh refresh   # dev-check PASS 后调用：把当前 lcov 写入 baseline-coverage.json
#
# 退出码:
#   0 = 通过
#   1 = 失败（含详细原因）
#   2 = 数据缺失（lcov.info 不存在 / baseline 缺）
#
# 依赖: bash, awk, jq, python3(可选)

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LCOV="$ROOT/coverage/lcov.info"
BASELINE="$ROOT/docs/dev/baseline-coverage.json"

# 关键路径默认清单（与 baseline-coverage.json _schema 一致）
DEFAULT_CRITICAL=(
  "lib/shared/models/play_queue.dart"
  "lib/features/player/domain/playback_orchestrator.dart"
  "lib/features/player/domain/play_mode.dart"
  "lib/features/player/domain/seek_utils.dart"
  "lib/features/player/domain/speed_manager.dart"
  "lib/features/browser/domain/cache_policy.dart"
  "lib/features/browser/domain/navigation_stack.dart"
  "lib/features/progress/domain/progress_policy.dart"
  "lib/features/connection/domain/connection_validator.dart"
  "lib/features/playlist/domain/playlist_service.dart"
  "lib/features/timer/domain/timer_service.dart"
  "lib/features/settings/domain/settings_service.dart"
)

if [[ ! -f "$LCOV" ]]; then
  echo "ERROR: lcov.info 不存在 ($LCOV)，请先 flutter test --coverage"
  exit 2
fi

# 解析 lcov.info -> per-file coverage%
# 输出: <file_path>\t<LF>\t<LH>\t<coverage%> 一行一个文件
parse_lcov() {
  awk '
    /^SF:/ { cur = substr($0, 4); lf = 0; lh = 0; found = 1 }
    found && /^LF:/ { lf += substr($0, 4) }
    found && /^LH:/ { lh += substr($0, 4) }
    found && /^end_of_record$/ {
      if (lf > 0) {
        printf "%s\t%d\t%d\t%.2f\n", cur, lh, lf, 100.0 * lh / lf
      } else {
        printf "%s\t%d\t%d\t0.00\n", cur, lh, lf
      }
      found = 0
    }
  ' "$LCOV"
}

# 同 parse_lcov，但只取 total 行
overall_coverage() {
  awk '
    /^LF:/ { lf += substr($0, 4) }
    /^LH:/ { lh += substr($0, 4) }
    END { if (lf > 0) printf "%.2f", 100.0 * lh / lf; else print "0.00" }
  ' "$LCOV"
}

# 检查 critical_files 字符串数组（从 JSON 读，否则用 DEFAULT_CRITICAL）
# param1: bash 数组名
load_critical_files() {
  local __name=$1
  if [[ -f "$BASELINE" ]] && command -v jq >/dev/null 2>&1; then
    # 尝试从 baseline 中读 critical_files 的 keys（若有数据）
    local keys
    keys=$(jq -r '.critical_files // {} | keys[]' "$BASELINE" 2>/dev/null || true)
    if [[ -n "$keys" ]]; then
      eval "$__name=( $(printf '%q\n' $keys) )"
      return
    fi
  fi
  eval "$__name=( \"${DEFAULT_CRITICAL[@]}\" )"
}

# ---- check-exe 子命令 ----
cmd_check_exe() {
  local -a critical
  load_critical_files critical

  local fail=0
  local min_perc=100.0
  local min_file=""

  echo "=== dev-exe 第 7 步覆盖率门禁 (critical_files) ==="
  for f in "${critical[@]}"; do
    local line
    line=$(parse_lcov | awk -v f="$f" -F'\t' '$1 == f { print }')
    if [[ -z "$line" ]]; then
      # 文件不在 lcov.info，可能是新增未测试文件——按 launch
      if [[ -f "$ROOT/$f" ]]; then
        echo "  [FAIL] $f — 文件存在但 lcov.info 无记录 (新增未测试? 覆盖率 0%)"
        fail=1
        continue
      else
        echo "  [SKIP] $f — 文件不存在"
        continue
      fi
    fi
    local perc
    perc=$(echo "$line" | cut -f4)
    awk -v p="$perc" -v t=90.0 'BEGIN { exit !(p < t) }' && {
      echo "  [FAIL] $f — $perc% < 90%"
      fail=1
    } || echo "  [ OK ] $f — $perc%"
    awk -v p="$perc" -v m="$min_perc" 'BEGIN { exit !(p < m) }' && {
      min_perc=$perc
      min_file=$f
    }
  done

  # 总体
  local overall
  overall=$(overall_coverage)
  echo "  总覆盖率: $overall%"

  echo "  单文件最低: $min_file $min_perc%"

  if [[ $fail -eq 1 ]]; then
    exit 1
  fi
  exit 0
}

# ---- check-check 子命令 ----
cmd_check_check() {
  if [[ ! -f "$BASELINE" ]] || [[ "$(jq -r '._status // "empty"' "$BASELINE")" == "empty" ]]; then
    echo "WARN: baseline-coverage.json 未建立——本次 dev-check 建立基线（非阻断）"
    cmd_refresh
    exit 0
  fi

  local base_overall
  base_overall=$(jq -r '.baseline_overall' "$BASELINE")
  local tol_overall
  tol_overall=$(jq -r '.tolerance_overall_drop // 1.0' "$BASELINE")
  local tol_critical
  tol_critical=$(jq -r '.tolerance_critical_drop // 2.0' "$BASELINE")

  local cur_overall
  cur_overall=$(overall_coverage)
  local fail=0

  echo "=== dev-check 第 6 项 基线漂移检测 ==="
  echo "  当前总覆盖率: $cur_overall%"
  echo "  基线总覆盖率: $base_overall% (容忍下降 $tol_overall%)"

  # 总体下降
  local drop_overall
  drop_overall=$(awk -v c="$cur_overall" -v b="$base_overall" 'BEGIN { printf "%.2f", b - c }')
  awk -v d="$drop_overall" -v t="$tol_overall" 'BEGIN { exit !(d > t) }' && {
    echo "  [FAIL] 总覆盖率下降 $drop_overall% > $tol_overall%"
    fail=1
  } || echo "  [ OK ] 总覆盖率下降 $drop_overall% <= $tol_overall%"

  # 单文件 critical 下降
  while IFS=$'\t' read -r f lf lh perc; do
    local base_perc
    base_perc=$(jq -r --arg f "$f" '.critical_files[$f] // empty' "$BASELINE")
    if [[ -n "$base_perc" ]]; then
      local drop
      drop=$(awk -v b="$base_perc" -v c="$perc" 'BEGIN { printf "%.2f", b - c }')
      awk -v d="$drop" -v t="$tol_critical" 'BEGIN { exit !(d > t) }' && {
        echo "  [FAIL] $f: $perc% < 基线 $base_perc% (下降 $drop% > $tol_critical%)"
        fail=1
      } || echo "  [ OK ] $f: $perc% (基线 $base_perc%, 下降 $drop%)"
    fi
  done < <(parse_lcov)

  # 文件缺失
  for f in $(jq -r '.critical_files | keys[]' "$BASELINE"); do
    if ! parse_lcov | awk -v f="$f" -F'\t' '$1 == f { found=1 } END { exit !found }'; then
      echo "  [FAIL] $f 在基线中存在但当前 lcov.info 缺失"
      fail=1
    fi
  done

  if [[ $fail -eq 1 ]]; then
    exit 1
  fi
  exit 0
}

# ---- refresh 子命令 ----
cmd_refresh() {
  # 整理 lcov.info 为 per-file JSON
  local tmp_all tmp_critical
  tmp_all=$(mktemp)
  tmp_critical=$(mktemp)

  parse_lcov | while IFS=$'\t' read -r f lh lf perc; do
    printf ' "%s": %s,\n' "$f" "$perc"
  done > "$tmp_all"

  local -a critical
  load_critical_files critical
  for f in "${critical[@]}"; do
    local perc
    perc=$(parse_lcov | awk -v f="$f" -F'\t' '$1 == f { print $4 }')
    perc=${perc:-0}
    printf ' "%s": %s,\n' "$f" "$perc"
  done > "$tmp_critical"

  local overall
  overall=$(overall_coverage)
  local today
  today=$(date +%Y-%m-%d)

  # 拼装 JSON
  {
    echo '{'
    echo '  "_comment": "由 docs/dev/scripts/coverage-check.sh refresh 自动生成——dev-check PASS 后刷新。",'
    echo "  \"_status\": \"active\","
    echo "  \"last_updated\": \"$today\","
    echo "  \"last_passed_feature\": null,"
    echo "  \"baseline_overall\": $overall,"
    echo "  \"tolerance_overall_drop\": 1.0,"
    echo "  \"tolerance_critical_drop\": 2.0,"
    echo "  \"critical_files_threshold\": 90.0,"
    echo "  \"critical_files\": {"
    # 去掉末尾逗号
    sed '$ s/,$//' "$tmp_critical"
    echo "  },"
    echo "  \"all_files\": {"
    sed '$ s/,$//' "$tmp_all"
    echo "  }"
    echo '}'
  } > "$BASELINE"

  rm -f "$tmp_all" "$tmp_critical"

  echo "已刷新 $BASELINE"
  echo "  baseline_overall: $overall%"
}

# ---- 入口 ----
subcmd="${1:-}"
case "$subcmd" in
  check-exe)   cmd_check_exe ;;
  check-check) cmd_check_check ;;
  refresh)     cmd_refresh ;;
  *) echo "usage: $0 {check-exe|check-check|refresh}"; exit 2 ;;
esac