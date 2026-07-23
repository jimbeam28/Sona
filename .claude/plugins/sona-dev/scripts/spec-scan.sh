#!/usr/bin/env bash
# spec-scan.sh — docs/features/{ID}.md 的机械结构扫描（三种模式）
#
# 用法:
#   spec-scan.sh <ID>            覆盖矩阵：每条 §3/4/6 spec ID 在 test/ 下的命中文件
#       输出 TSV: kind  id  spec_section  spec_line  test_files(分号分隔或-)   退出码恒 0
#   spec-scan.sh --neg <ID>      否定断言结构检查：每条 status:new 的 Scenario 是否带 否定断言: 块
#       输出 TSV: scenario_id  has_neg(yes|no)                                缺失 → 退出码 1
#   spec-scan.sh --count <ID>    输出 S/INV/ALG 计数（INDEX.md 同步用）: S=n INV=m ALG=k
#
# 边界: 本脚本只做结构/字面量机械扫描，不判断测试是否"真断言了行为"——那是 dev-check 的判断题。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

MODE="matrix"
if [[ "${1:-}" == "--neg" ]]; then MODE="neg"; shift; fi
if [[ "${1:-}" == "--count" ]]; then MODE="count"; shift; fi
[[ $# -eq 1 ]] || { echo "usage: $0 [--neg|--count] <ID>" >&2; exit 2; }
ID="$1"
SPEC="docs/features/${ID}.md"
[[ -f "$SPEC" ]] || { echo "ERROR: $SPEC 不存在" >&2; exit 2; }

# 抽取 spec 内锚点 ID（去重，保留首次行号）。两种写法都认：
#   §3/4 方括号锚点  [ID-S1] / [ID-INV1] / [ID-ALG1-name]
#   §9 JSON 引号写法 "ID-ALG1-name"（§6 纯函数样例无方括号，ID 仅在 §9 镜像中出现）
extract_ids() {
  awk -v id="$ID" '
    {
      line=$0
      while (match(line, "\\[" id "-(S[0-9]+|INV[0-9]+|ALG[0-9A-Za-z_-]*)\\]") \
          || match(line, "\"" id "-(S[0-9]+|INV[0-9]+|ALG[0-9A-Za-z_-]*)\"")) {
        print substr(line, RSTART+1, RLENGTH-2) "\t" NR
        line = substr(line, RSTART+RLENGTH)
      }
    }' "$SPEC" | awk '!seen[$1]++'
}

find_test_files() { # 字面量 ID 在 test/ 下出现的文件
  grep -rlF -- "$1" test/ 2>/dev/null | sort | paste -sd';' || true
}

section_of() {
  case "$1" in
    *-S[0-9]*)   echo "§3" ;;
    *-INV[0-9]*) echo "§4" ;;
    *)           echo "§6" ;;
  esac
}

case "$MODE" in
  matrix)
    printf "kind\tid\tspec_section\tspec_line\ttest_files\n"
    while IFS=$'\t' read -r id line; do
      kind="S"
      [[ "$id" == *INV* ]] && kind="INV"
      [[ "$id" == *ALG* ]] && kind="ALG"
      files=$(find_test_files "$id")
      [[ -z "$files" ]] && files="-"
      printf "%s\t%s\t%s\t%s\t%s\n" "$kind" "$id" "$(section_of "$id")" "$line" "$files"
    done < <(extract_ids)
    ;;

  neg)
    # status:new 兼容两种写法：锚点行内联 `status: new` 或行尾 (status: new)。
    # 否定断言块：同一 Scenario 范围内（至下一锚点前）出现 否定断言: 行即 yes。
    printf "scenario_id\thas_neg\n"
    MISSING=0
    while IFS=$'\t' read -r scn has; do
      printf "%s\t%s\n" "$scn" "$has"
      [[ "$has" == "no" ]] && MISSING=$((MISSING + 1))
    done < <(awk -v id="$ID" '
      function flush() {
        if (scn != "" && is_new) print scn "\t" (has_neg ? "yes" : "no")
        scn=""; is_new=0; has_neg=0
      }
      $0 ~ "\\[" id "-S[0-9]+\\]" {
        flush()
        line=$0
        match(line, "\\[" id "-S[0-9]+\\]")
        scn = substr(line, RSTART+1, RLENGTH-2)
        if (line ~ /status: new/) is_new=1
        next
      }
      scn != "" && $0 ~ /^[[:space:]]*否定断言:/ { has_neg=1 }
      END { flush() }
    ' "$SPEC")
    [[ $MISSING -gt 0 ]] && { echo "FAIL: $MISSING 条 status:new Scenario 缺否定断言块" >&2; exit 1; }
    exit 0
    ;;

  count)
    s=$(extract_ids | cut -f1 | grep -cE -- "-S[0-9]+$" || true)
    inv=$(extract_ids | cut -f1 | grep -cE -- "-INV[0-9]+$" || true)
    alg=$(extract_ids | cut -f1 | grep -cE -- "-ALG" || true)
    echo "S=$s INV=$inv ALG=$alg"
    ;;
esac
