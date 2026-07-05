#!/usr/bin/env bash
# neg-assert.sh — 从 docs/features/{ID}.md §3 提取"否定断言"标记 + 在 test/ 下查对应断言命中
#
# 用法:
#   scripts/dev/neg-assert.sh <ID>
#
# 输出（TSV）→ 退出码 0/1
#   scenario_id<TAB>neg_line<TAB>test_files(分号分隔 或 -)
#
#   scenario_id: 规约于出现的 Scenario ID（如 BRW-09-S5）
#   neg_line:    "否定断言:" 后第一行字面文本（用于在 test 中穷取一段做引用）
#   test_files:  test 中出现该 neg_line 关键词的文件清单；未命中 = -
#
# 用途: dev-check 检查 7 "否定断言未被破坏" + dev-plan 铁律 4 "每条新 Scenario 必带否定断言"
# 本脚本两用：
#   - dev-plan 用来检查自己生成的 §3 是否每条 status: new Scenario 都带了否定断言
#   - dev-check 用来验证这些否定断言在 test 中真有对应 expect(..., isFalse/isNot/equals?) 类断言
#
# 设计动机：dev-plan 铁律 4 + dev-check 检查 7 两段都需要这机械扫描，原本散见在 SKILL.md 散笔，
#      本脚本统一进 plugin。
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

# 1. 扫所有 Scenario 锚点 + 距离最近的"否定断言:"块
#    输出: scenario_id<TAB>neg_text
#    策略: awk 逐行扫，遇 [ID-SN] 记下当前 scenario，遇 否定断言块（"否定断言:" 后缩进若干行
#          至空行 / 下一 [BRW-09-...] 锚点）输出 缩进首行
awk -v id="$ID" '
  function emit_neg() {
    if (cur_scn != "" && neg_buf != "") {
      first = neg_buf
      sub(/\n.*/, "", first)
      gsub(/^[ \t]+- /, "", first)
      print cur_scn "\t" first
    }
    neg_buf = ""
  }
  # 提取 [ID-SN]：不要求行首，因为 spec 内多为 `- **[BUG-03-S3]** status: new`
  $0 ~ "\\[" id "-S[0-9]+\\]" {
    emit_neg()
    cur_scn = $0
    if (match(cur_scn, "\\[" id "-S[0-9]+\\]")) {
      cur_scn = substr(cur_scn, RSTART+1, RLENGTH-2)
    }
    next
  }
  # "否定断言:" 可能行首有缩进（在 ``` 代码块内）
  $0 ~ "^[[:space:]]*否定断言:" {
    in_neg = 1
    neg_buf = ""
    next
  }
  in_neg {
    if ($0 ~ /^[ \t]+- / || $0 ~ /^[ \t]+/) {
      if (neg_buf != "") neg_buf = neg_buf "\n" $0
      else neg_buf = $0
    } else {
      emit_neg()
      in_neg = 0
    }
  }
  END { emit_neg() }
' "$SPEC" > /tmp/neg-assert.$$.tmp

# 2. 对每条 neg_text 在 test/ 下找出现该关键词的 test 文件
printf "scenario_id\tneg_text\ttest_files\n"
while IFS=$'\t' read -r scn neg; do
  [[ -z "$neg" ]] && continue
  # 取连续非空白 token 拼关键词做检索，避免单条长串难以匹配
  keyword=$(echo "$neg" | awk '{
    gsub(/[，。、：；""()（）{}]/, " ")
    out=""; for(i=1;i<=NF;i++){ if(length($i)>=2) out=out " " $i }
    sub(/^ /, "", out); print out
  }' | head -c 80)
  files=""
  if [[ -n "$keyword" ]]; then
    if command -v rg >/dev/null 2>&1; then
      files=$(rg -l --no-heading -F -i "$keyword" test/ 2>/dev/null | sort | paste -sd';' || true)
    else
      files=$(grep -rlF -i -- "$keyword" test/ 2>/dev/null | sort | paste -sd';' || true)
    fi
  fi
  [[ -z "$files" ]] && files="-"
  printf "%s\t%s\t%s\n" "$scn" "$neg" "$files"
done < /tmp/neg-assert.$$.tmp
rm -f /tmp/neg-assert.$$.tmp