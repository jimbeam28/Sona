#!/usr/bin/env bash
# spec-scan.sh — 解析 docs/features/{ID}.md §3/§4/§6 锚点 ID 列表 + 在 test/ 下查测试命中
#
# 用法:
#   scripts/dev/spec-scan.sh <ID>
#
# 输出（TSV）：
#   kind<TAB>id<TAB>anchor_line<TAB>spec_section<TAB>test_files(分号分隔或-)
#
#   kind: S | INV | ALG
#   test_files: 命中 = 文件路径(分号分隔)；未命中 = -
#
# 用途：dev-exe Agent C "spec 覆盖门禁" + dev-check 检查 7 "否定断言被破坏" 用本脚本
#      确认每条 §3/4/6 spec ID 在 test/ 都有对应断言。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <ID>" >&2
  exit 2
fi
ID="$1"
SPEC="docs/features/${ID}.md"
[[ -f "$SPEC" ]] || { echo "ERROR: $SPEC 不存在" >&2; exit 2; }

# 1. 扫 spec 内 ID：§3 Scenario "S", §4 INV "INV", §6 ALG "ALG"
#    匹配形如 "[{ID}-S1]" / "[{ID}-INV2]" / "[{ID}-ALG-foo]" / "{ID}-S1"
#    在文档第一列或代码块第一列，正则取 `ID-` 前缀后接 S/INV/ALG 的 token
extract_ids() {
  awk -v id="$ID" '
    {
      # 匹配 [ID-Sxx] 或 [ID-INVxx] 或 [ID-ALGxxx]
      line=$0
      while (match(line, "\\[" id "-(S[0-9]+|INV[0-9]+|ALG[0-9A-Za-z_-]*)\\]")) {
        tag = substr(line, RSTART+1, RLENGTH-2)
        print tag "\t" NR
        line = substr(line, RSTART+RLENGTH)
      }
    }
  ' "$SPEC" | awk '!seen[$1]++'
}

# 2. 对每 ID 在 test/ 下找出现该 ID 字面量的 test 文件
#    兼容无 rg 的环境（fallback 到 grep -rlE）
find_test_files() {
  local id="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -l --no-heading -F "$id" test/ 2>/dev/null | sort | paste -sd';' || true
  else
    grep -rlF -- "$id" test/ 2>/dev/null | sort | paste -sd';' || true
  fi
}

# 3. 推 section：S→§3, INV→§4, ALG§6
#    传入的 id 形如 "BUG-03-S1" / "BUG-03-INV1" / "BUG-03-ALG-resume"
section_of() {
  case "$1" in
    *-S[0-9]*)    echo "§3" ;;
    *-INV[0-9]*)  echo "§4" ;;
    *-ALG[0-9A-Za-z_-]*) echo "§6" ;;
    *)            echo "?" ;;
  esac
}

printf "kind\tid\tspec_section\tspec_line\ttest_files\n"
while IFS=$'\t' read -r id line; do
  kind="S"
  [[ "$id" == *INV* ]] && kind="INV"
  [[ "$id" == *ALG* ]] && kind="ALG"
  section=$(section_of "$id")
  files=$(find_test_files "$id")
  [[ -z "$files" ]] && files="-"
  printf "%s\t%s\t%s\t%s\t%s\n" "$kind" "$id" "$section" "$line" "$files"
done < <(extract_ids)