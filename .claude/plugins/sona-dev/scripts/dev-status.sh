#!/usr/bin/env bash
# dev-status.sh — 读 / 改 docs/dev/dev-status.json 条目
#
# 设计动机：每个 skill 都需要读 dev-status.json 找条目、查字段、写状态；
# 重复解析 JSON 易错。本脚本用 jq 集中封装所有读写。
#
# 用法:
#   scripts/dev/dev-status.sh list
#       列出 items 中所有 ID + impl/test/check 状态 + name
#   scripts/dev/dev-status.sh show <ID>
#       全字段打印某条目（pretty JSON）
#   scripts/dev/dev-status.sh field <ID> <field>
#       读单字段（impl_status / test_status / check_status / check_round / ...）
#   scripts/dev/dev-status.sh pending
#       列 impl_status=done 且 check_status≠passed 的条目（dev-check 输入）
#   scripts/dev/dev-status.sh impl-ready
#       列 impl_status=pending 且 dependencies 全 done 的条目（dev-exe 输入）
#   scripts/dev/dev-status.sh set <ID> <field> <value>
#       写字段；value 须是合法 JSON 字面量（true/false/string/null/"\"str\""/数字）
#       例: dev-status.sh set BRW-09 impl_status '"done"'
#           dev-status.sh set BRW-09 check_round 2
#           dev-status.sh set BRW-09 last_checked_at '"2026-07-05"'
#   scripts/dev/dev-status.sh bump-round <ID>
#       check_round += 1；同步把 check_status 改 "round_N"，impl_status 改 "pending"
#       （dev-check FAIL 时调）
#   scripts/dev/dev-status.sh pass <ID>
#       check_status="passed"，写 last_checked_at=今天
#       （dev-check PASS 时调；刷新基线另调 coverage-drift.sh refresh）
#   scripts/dev/dev-status.sh block <ID>
#       check_status="blocked_after_3_rounds"，impl_status="blocked"
#
# 退出码: 0 = 成功；非 0 = 错误（条目不存在 / jq 失败 / 参数错）
set -euo pipefail

# ROOT = 项目根：plugin 路径 .claude/plugins/sona-dev/scripts/, 上溯 4 级
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
STATUS="$ROOT/docs/dev/dev-status.json"

# 仅运行测试用 fixture 时不强制存在；生产必存在
[[ -f "$STATUS" ]] || { echo "ERROR: 缺 $STATUS" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: 缺 jq" >&2; exit 2; }

cmd_list() {
  jq -r '.items | to_entries[] |
    "\(.key)\t\(.value.impl_status)\t\(.value.test_status)\t\(.value.check_status // "-")\t\(.value.check_round // 0)\t\(.value.name)"' "$STATUS" \
    | awk 'BEGIN{print "ID\timpl\ttest\tcheck\tround\tname"} {print}' \
    | column -t -s$'\t'
}

cmd_show() {
  local id="$1"
  jq --arg id "$id" '.items[$id]' "$STATUS"
}

cmd_field() {
  local id="$1" field="$2"
  jq -r --arg id "$id" --arg f "$field" '.items[$id][$f] // null' "$STATUS"
}

cmd_pending() {
  jq -r '.items | to_entries[] |
    select(.value.impl_status == "done" and (.value.check_status // "pending") != "passed") |
    "\(.key)\t\(.value.name)"' "$STATUS"
}

cmd_impl_ready() {
  jq -r '
    .items as $items
    | .items | to_entries[]
    | select(.value.impl_status == "pending")
    | . as $e
    | ($e.value.dependencies // [])
      | map($items[.] // {impl_status:"missing"})
      | all(.impl_status == "done")
    | select(.)
    | $e.key + "\t" + $e.value.name
  ' "$STATUS"
}

cmd_set() {
  local id="$1" field="$2" val="$3"
  jq --arg id "$id" --arg f "$field" --argjson v "$val" \
    '.items[$id][$f] = $v | .metadata.last_updated = (now | strftime("%Y-%m-%d"))' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

cmd_bump_round() {
  local id="$1"
  local new_round
  new_round=$(jq -r --arg id "$id" '(.items[$id].check_round // 0) + 1' "$STATUS")
  local check_status="round_${new_round}"
  local today; today=$(date +%Y-%m-%d)
  jq --arg id "$id" --argjson r "$new_round" --arg cs "$check_status" --arg t "$today" \
    '.items[$id].check_round = $r
     | .items[$id].check_status = $cs
     | .items[$id].impl_status = "pending"
     | .items[$id].test_status = "pending"
     | .items[$id].last_checked_at = $t
     | .metadata.last_updated = $t' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
  echo "bumped: $id check_round=$new_round impl_status=pending"
}

cmd_pass() {
  local id="$1"
  local today; today=$(date +%Y-%m-%d)
  jq --arg id "$id" --arg t "$today" \
    '.items[$id].check_status = "passed"
     | .items[$id].last_checked_at = $t
     | .metadata.last_updated = $t' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

cmd_block() {
  local id="$1"
  local today; today=$(date +%Y-%m-%d)
  jq --arg id "$id" --arg t "$today" \
    '.items[$id].check_status = "blocked_after_3_rounds"
     | .items[$id].impl_status = "blocked"
     | .items[$id].last_checked_at = $t
     | .metadata.last_updated = $t' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

case "${1:-}" in
  list)         cmd_list ;;
  show)         cmd_show "${2:?missing ID}" ;;
  field)        cmd_field "${2:?missing ID}" "${3:?missing field}" ;;
  pending)      cmd_pending ;;
  impl-ready)   cmd_impl_ready ;;
  set)          cmd_set "${2:?missing ID}" "${3:?missing field}" "${4:?missing value}" ;;
  bump-round)   cmd_bump_round "${2:?missing ID}" ;;
  pass)         cmd_pass "${2:?missing ID}" ;;
  block)        cmd_block "${2:?missing ID}" ;;
  *) echo "usage: $0 {list|show <id>|field <id> <f>|pending|impl-ready|set <id> <f> <v>|bump-round <id>|pass <id>|block <id>}" >&2; exit 2 ;;
esac