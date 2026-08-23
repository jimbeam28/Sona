#!/usr/bin/env bash
# cross-imports.sh — 架构硬约束机械门禁（CLAUDE.md 架构分层）
#
# 用法:
#   cross-imports.sh [kind...]
#     kind = domain-flutter | feature-isolation | secret-logs | provider-platform | all(默认)
#   cross-imports.sh impact <file...>
#     反查引用方：列出哪些 feature/层 import 了给定文件（dev-plan §7 / dev-check 跨模块检查用）
#
# 输出（TSV，stdout）:
#   kind 模式: kind<TAB>severity<TAB>file:line<TAB>现象        退出码 0=无违规 1=有违规
#   impact 模式: target<TAB>importer_area<TAB>file:line       退出码恒 0
#
# 使用者: cr 走查维度 2/4、dev-check 跨模块检查、CI 架构边界检查（.github/workflows/ci.yml）
# 依赖: bash + GNU grep（本地与 CI 均可用；不依赖 rg——本机 rg 仅是 Claude Code shell 函数，脚本内不可用）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

PKG="$(grep -m1 '^name:' pubspec.yaml | awk '{print $2}')"
BASELINE="$ROOT/docs/dev/arch-baseline.txt"
VIOLATIONS=0

# 违规是否已入基线（legacy debt，按 kind+file 抑制；基线只能减不能增）
baselined() { # kind file
  [[ -f "$BASELINE" ]] || return 1
  awk -F'\t' -v k="$1" -v f="$2" '$1 == k && $2 == f { found=1 } END { exit !found }' "$BASELINE"
}

emit() { # kind severity location detail
  local file="${3%%:*}"
  if baselined "$1" "$file"; then
    echo "BASELINED: $1 $3 (legacy debt, 见 docs/dev/arch-baseline.txt)" >&2
    return
  fi
  printf "%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4"
  VIOLATIONS=$((VIOLATIONS + 1))
}

# ── 维度 1: Domain 层零 Flutter/Riverpod/平台 SDK 依赖 → Critical ──
check_domain_flutter() {
  local out
  out=$(grep -rnE --include='*.dart' \
    "import[[:space:]]*['\"](package:flutter/|package:flutter_riverpod/|package:flutter_[a-z_]+/|dart:ui|package:shared_preferences/|package:just_audio/|package:audio_service/|package:sqflite/|package:flutter_secure_storage/)" \
    lib/features/*/domain/ 2>/dev/null || true)
  if [[ -n "$out" ]]; then
    while IFS= read -r line; do
      emit "domain-flutter" "Critical" "$line" "Domain 层禁止 Flutter/平台 SDK 依赖"
    done <<<"$out"
  else
    echo "domain-flutter: clean" >&2
  fi
}

# ── 维度 2: Feature 隔离 — feature 间不得直接 import（须经 shared/di 桥接）→ Major ──
# 实现：取全部 import 语句 → 解析目标路径 → 落在其它 feature 目录下即违规。
# 不用正则 lookahead（grep/rg 默认引擎不支持，旧版此处永远假 PASS）。
check_feature_isolation() {
  local before=$VIOLATIONS
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    local file lineno import_path src_feature resolved target
    file="${hit%%:*}"
    lineno="${hit#*:}"; lineno="${lineno%%:*}"
    import_path=$(sed -n "s/.*import[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" <<<"$hit")
    [[ -z "$import_path" ]] && continue
    case "$file" in
      lib/features/*) src_feature=$(cut -d/ -f3 <<<"$file") ;;
      *) continue ;;
    esac
    # 解析 import 目标到 lib/ 相对路径
    if [[ "$import_path" == dart:* ]]; then
      continue
    elif [[ "$import_path" == package:"$PKG"/* ]]; then
      resolved="lib/${import_path#package:$PKG/}"
    elif [[ "$import_path" == package:* ]]; then
      continue   # 外部包
    else
      resolved=$(realpath -m "$(dirname "$file")/$import_path" 2>/dev/null || true)
      resolved="${resolved#"$(pwd)/"}"
    fi
    case "$resolved" in
      lib/features/*)
        target=$(cut -d/ -f3 <<<"$resolved")
        if [[ "$target" != "$src_feature" ]]; then
          emit "feature-isolation" "Major" "$file:$lineno" "跨 feature 直接 import $target（须经 shared/di/providers.dart）: $import_path"
        fi
        ;;
    esac
  done < <(grep -rnE --include='*.dart' "^[[:space:]]*import[[:space:]]+['\"]" lib/features/ 2>/dev/null || true)
  [[ $VIOLATIONS -eq $before ]] && echo "feature-isolation: clean" >&2
}

# ── 维度 3: 日志泄露密码/凭证 → Critical ──
check_secret_logs() {
  local out
  out=$(grep -rnE --include='*.dart' \
    '(print|debugPrint|log)[[:space:]]*\([^)]{0,80}(password|pwd|credential|Authorization)' \
    lib/ 2>/dev/null || true)
  if [[ -n "$out" ]]; then
    while IFS= read -r line; do
      emit "secret-logs" "Critical" "$line" "日志含敏感字面量"
    done <<<"$out"
  else
    echo "secret-logs: clean" >&2
  fi
}

# ── 维度 4: Core 层零 feature 依赖 — core 不得反向 import feature → Major ──
# 实现：扫描 lib/core/ 全部 import 语句 → 解析目标路径 → 落在 lib/features/** 下即违规
# （REF-09：数据层被 feature 反向依赖会连带击穿 core/database 与 core/services）。
check_core_feature() {
  local before=$VIOLATIONS
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    local file lineno import_path resolved
    file="${hit%%:*}"
    lineno="${hit#*:}"; lineno="${lineno%%:*}"
    import_path=$(sed -n "s/.*import[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" <<<"$hit")
    [[ -z "$import_path" ]] && continue
    # 解析 import 目标到 lib/ 相对路径
    if [[ "$import_path" == dart:* ]]; then
      continue
    elif [[ "$import_path" == package:"$PKG"/* ]]; then
      resolved="lib/${import_path#package:$PKG/}"
    elif [[ "$import_path" == package:* ]]; then
      continue   # 外部包
    else
      resolved=$(realpath -m "$(dirname "$file")/$import_path" 2>/dev/null || true)
      resolved="${resolved#"$(pwd)/"}"
    fi
    case "$resolved" in
      lib/features/*)
        emit "core-feature" "Major" "$file:$lineno" "core 层反向依赖 feature（须下沉到 core/contracts 或 shared）: $import_path"
        ;;
    esac
  done < <(grep -rnE --include='*.dart' "^[[:space:]]*import[[:space:]]+['\"]" lib/core/ 2>/dev/null || true)
  [[ $VIOLATIONS -eq $before ]] && echo "core-feature: clean" >&2
}

# ── 维度 5: Provider 层平台包直引 — 装配点之外禁止直引平台包（REF-17-S3）→ Major ──
# 扫描 lib/features/**/*_provider*.dart 的平台包 import 行；
# 两处合法装配点（S1 豁免）按 kind+file 登记 arch-baseline.txt。
check_provider_platform() {
  local out
  out=$(grep -rnE --include='*_provider*.dart' \
    "import[[:space:]]*['\"]package:(just_audio|audio_service|sqflite|flutter_secure_storage|dio)/" \
    lib/features/ 2>/dev/null || true)
  if [[ -n "$out" ]]; then
    while IFS= read -r line; do
      emit "provider-platform" "Major" "$line" "Provider 层平台包直引（仅 REF-17-S1 两装配点豁免，经 core/contracts/）"
    done <<<"$out"
  else
    echo "provider-platform: clean" >&2
  fi
}

# ── impact 模式: 反查引用方 ──
# 对每个目标文件，找 lib/ 下所有 import 行中引用其 lib 相对路径或文件名的，按来源区域分组。
cmd_impact() {
  [[ $# -ge 1 ]] || { echo "usage: $0 impact <file...>" >&2; exit 2; }
  printf "target\timporter_area\tfile:line\n"
  local target rel base hit file area
  for target in "$@"; do
    rel="${target#lib/}"
    base="$(basename "$target")"
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      file="${hit%%:*}"
      # 区域: features/X → X；其它 → 二级目录名（core / shared）
      case "$file" in
        lib/features/*) area=$(cut -d/ -f3 <<<"$file") ;;
        lib/*)          area=$(cut -d/ -f2 <<<"$file") ;;
        *)              area="-" ;;
      esac
      printf "%s\t%s\t%s\n" "$target" "$area" "$file"
    done < <(grep -rnE --include='*.dart' "^[[:space:]]*import[[:space:]]+['\"]" lib/ 2>/dev/null \
             | grep -F -e "$rel" -e "$base" || true)
  done
}

main() {
  if [[ "${1:-}" == "impact" ]]; then
    shift
    cmd_impact "$@"
    exit 0
  fi
  local kinds=("$@")
  [[ ${#kinds[@]} -eq 0 ]] && kinds=(all)
  for k in "${kinds[@]}"; do
    case "$k" in
      domain-flutter)    check_domain_flutter ;;
      feature-isolation) check_feature_isolation ;;
      secret-logs)       check_secret_logs ;;
      core-feature)      check_core_feature ;;
      provider-platform) check_provider_platform ;;
      all)
        check_domain_flutter
        check_feature_isolation
        check_secret_logs
        check_provider_platform
        check_core_feature
        ;;
      *) echo "unknown kind: $k" >&2; exit 2 ;;
    esac
  done
  [[ $VIOLATIONS -gt 0 ]] && exit 1
  exit 0
}

main "$@"
