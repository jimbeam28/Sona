#!/usr/bin/env bash
# dev-status.sh — docs/dev/dev-status.json 的唯一读写入口（jq 集中封装，防手拼 JSON 出错）
#
# 用法:
#   dev-status.sh list                          列全部条目状态总览
#   dev-status.sh show <ID>                     全字段 pretty JSON
#   dev-status.sh field <ID> <field>            读单字段
#   dev-status.sh pending                       列 impl=done 且 check≠passed（dev-check 输入）
#   dev-status.sh impl-ready                    列 impl=pending 且依赖全 done（dev-exe 输入）
#   dev-status.sh list-pending                  按 .order 顺序列待执行项（批量 dev-exe 输入）
#   dev-status.sh next-id <PREFIX>              按 status.json + docs/features/*.md 算下一个空闲编号（如 SET-03）
#   dev-status.sh create <ID> <name> <spec_file> <anchored_file>...
#       创建完整骨架条目（全部必填字段初始化 pending）；
#       校验：ID 不得已存在、spec_file 与每个 anchored_file 必须真实存在（锚到代码硬门禁）
#   dev-status.sh set <ID> <field> <json_value> 写字段；ID 不存在直接报错（防 typo 幻影条目）
#       例: dev-status.sh set BRW-09 scenarios '["BRW-09-S1","BRW-09-S2"]'
#   dev-status.sh bump-round <ID>               dev-check FAIL: check_round+1, 状态回 pending
#   dev-status.sh pass <ID>                     dev-check PASS: check_status=passed
#   dev-status.sh block <ID>                    超轮上限: blocked_after_3_rounds
#
# 退出码: 0 成功；1 业务错误（条目不存在/已存在/文件缺失）；2 参数错
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
STATUS="$ROOT/docs/dev/dev-status.json"

[[ -f "$STATUS" ]] || { echo "ERROR: 缺 $STATUS" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: 缺 jq" >&2; exit 2; }

exists() { # <ID>
  [[ "$(jq -r --arg id "$1" '.items | has($id)' "$STATUS")" == "true" ]]
}

cmd_list() {
  { jq -r '.items | to_entries[] |
      "\(.key)\t\(.value.impl_status)\t\(.value.test_status)\t\(.value.check_status // "-")\t\(.value.check_round // 0)\t\(.value.name)"' "$STATUS"; } \
    | awk 'BEGIN{print "ID\timpl\ttest\tcheck\tround\tname"} {print}' \
    | column -t -s$'\t'
}

cmd_show()  { jq --arg id "$1" '.items[$id]' "$STATUS"; }
cmd_field() { jq -r --arg id "$1" --arg f "$2" '.items[$id][$f] // null' "$STATUS"; }

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

cmd_list_pending() {
  # 按 .order 顺序列出待执行项（impl_status 为 null/pending/failed，且 dependencies 全 done）
  jq -r '
    .items as $items
    | .order[]
    | . as $id
    | $items[$id] as $item
    | select($item.impl_status == null or $item.impl_status == "pending" or $item.impl_status == "failed")
    | select($item.impl_status != "blocked" and $item.impl_status != "done")
    | . as $id
    | ($item.dependencies // [])
      | map($items[.] // {impl_status:"missing"})
      | all(.impl_status == "done")
    | select(.)
    | $id + "\t" + $items[$id].name + "\t" + ($items[$id].impl_status // "null")
  ' "$STATUS"
}

cmd_next_id() { # <PREFIX>
  local prefix="$1" max=0 n
  # 来源 1: status.json 条目 ID
  while IFS= read -r n; do
    [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n > max )) && max=$((10#$n))
  done < <(jq -r --arg p "$prefix" '.items | keys[] | select(startswith($p + "-")) | split("-")[-1]' "$STATUS")
  # 来源 2: docs/features/ 已有文档（含已从 status.json 清出的历史 spec）
  if [[ -d "$ROOT/docs/features" ]]; then
    while IFS= read -r n; do
      [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n > max )) && max=$((10#$n))
    done < <(ls "$ROOT/docs/features/" | grep -oE "^${prefix}-[0-9]+" | cut -d- -f2 || true)
  fi
  printf "%s-%02d\n" "$prefix" "$((max + 1))"
}

cmd_create() { # <ID> <name> <spec_file> <anchored_file>...
  local id="$1" name="$2" spec="$3"; shift 3
  exists "$id" && { echo "ERROR: $id 已存在，不得重复创建" >&2; exit 1; }
  [[ -f "$ROOT/$spec" ]] || { echo "ERROR: spec_file 不存在: $spec" >&2; exit 1; }
  local f
  for f in "$@"; do
    [[ -f "$ROOT/$f" ]] || { echo "ERROR: 锚点文件不存在: $f（锚到代码是硬门禁）" >&2; exit 1; }
  done
  local anchored_json today
  anchored_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
  today=$(date +%Y-%m-%d)
  jq --arg id "$id" --arg name "$name" --arg spec "$spec" \
     --argjson anchored "$anchored_json" --arg today "$today" '
    .items[$id] = {
      "name": $name,
      "spec_file": $spec,
      "spec_anchored_files": $anchored,
      "scenarios": [],
      "invariants": [],
      "algorithms": [],
      "test_files": [],
      "test_coverage_gaps": [],
      "cross_module_impacts": [],
      "manual_qa_required": false,
      "manual_qa_file": null,
      "user_acceptance_text": ("见 " + $spec + " §1.2"),
      "impl_status": "pending",
      "test_status": "pending",
      "check_status": "pending",
      "check_round": 0,
      "last_check_round_results": "",
      "last_checked_at": "",
      "dependencies": [],
      "retry_count": 0,
      "last_error": "",
      "last_updated": $today
    }
    | .order += [$id]
    | .metadata.last_updated = $today
    | .metadata.total = (.items | length)
    | .metadata.pending = ([.items[] | select(.impl_status == "pending")] | length)
  ' "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
  echo "created: $id ($name)"
}

cmd_set() { # <ID> <field> <json_value>
  local id="$1" field="$2" val="$3"
  exists "$id" || { echo "ERROR: 条目 $id 不存在（禁止对不存在的条目 set，防 typo 幻影条目）" >&2; exit 1; }
  jq --arg id "$id" --arg f "$field" --argjson v "$val" \
    '.items[$id][$f] = $v | .metadata.last_updated = (now | strftime("%Y-%m-%d"))' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

cmd_bump_round() {
  local id="$1"
  exists "$id" || { echo "ERROR: 条目 $id 不存在" >&2; exit 1; }
  local new_round today
  new_round=$(jq -r --arg id "$id" '(.items[$id].check_round // 0) + 1' "$STATUS")
  today=$(date +%Y-%m-%d)
  jq --arg id "$id" --argjson r "$new_round" --arg cs "round_${new_round}" --arg t "$today" '
    .items[$id].check_round = $r
    | .items[$id].check_status = $cs
    | .items[$id].impl_status = "pending"
    | .items[$id].test_status = "pending"
    | .items[$id].last_check_round_results = ("见 docs/dev/check_log.md @ " + $id + " 第 " + ($r|tostring) + " 轮")
    | .items[$id].last_checked_at = $t
    | .metadata.last_updated = $t' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
  echo "bumped: $id check_round=$new_round impl_status=pending"
}

cmd_pass() {
  local id="$1"
  exists "$id" || { echo "ERROR: 条目 $id 不存在" >&2; exit 1; }
  local today; today=$(date +%Y-%m-%d)
  jq --arg id "$id" --arg t "$today" '
    .items[$id].check_status = "passed"
    | .items[$id].last_checked_at = $t
    | .metadata.last_updated = $t' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
  echo "passed: $id"
}

cmd_block() {
  local id="$1"
  exists "$id" || { echo "ERROR: 条目 $id 不存在" >&2; exit 1; }
  local today; today=$(date +%Y-%m-%d)
  jq --arg id "$id" --arg t "$today" '
    .items[$id].check_status = "blocked_after_3_rounds"
    | .items[$id].impl_status = "blocked"
    | .items[$id].last_error = "dev-check 多轮未通过，需人工介入"
    | .items[$id].last_checked_at = $t
    | .metadata.last_updated = $t' \
    "$STATUS" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
  echo "blocked: $id"
}

case "${1:-}" in
  list)         cmd_list ;;
  show)         cmd_show "${2:?missing ID}" ;;
  field)        cmd_field "${2:?missing ID}" "${3:?missing field}" ;;
  pending)      cmd_pending ;;
  impl-ready)   cmd_impl_ready ;;
  list-pending) cmd_list_pending ;;
  next-id)      cmd_next_id "${2:?missing PREFIX}" ;;
  create)       cmd_create "${2:?missing ID}" "${3:?missing name}" "${4:?missing spec_file}" "${@:5}" ;;
  set)          cmd_set "${2:?missing ID}" "${3:?missing field}" "${4:?missing value}" ;;
  bump-round)   cmd_bump_round "${2:?missing ID}" ;;
  pass)         cmd_pass "${2:?missing ID}" ;;
  block)        cmd_block "${2:?missing ID}" ;;
  *) echo "usage: $0 {list|show|field|pending|impl-ready|list-pending|next-id|create|set|bump-round|pass|block} ..." >&2; exit 2 ;;
esac
