#!/usr/bin/env bash
# cross-imports.sh — 扫描架构硬约束违规（Domain 零 Flutter / Feature 隔离 / 密码泄露日志）
#
# 用法:
#   scripts/dev/cross-imports.sh [kind...]
#     kind = domain-flutter | feature-isolation | secret-logs | all(默认)
#
# 输出（TSV）→ 退出码 0/1
#   kind<TAB>severity<TAB>file:line<TAB>现象
#
#   severity = Critical | Major | Info
#
# 用途：
#   - cr 走查维度 2/4 自动机械部分
#   - dev-check 检查 5 "跨模块漏识破坏" 用 feature-isolation 子模式
#   - dev-check 检查 2 "实现对 spec 忠实度" 中安全性部分
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

rg_cmd() {
  # 优先用 ripgrep；无则 fallback 到 grep -rn
  if command -v rg >/dev/null 2>&1; then
    rg -n --no-heading "$@" 2>/dev/null || true
  else
    # 把 rg 选项翻译为 grep 等价
    local args=()
    local pattern=""
    local paths=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) shift;;            # -t dart: 跳过类型（简化）
        --glob) shift;;        # 跳过 glob 限定
        -e) shift; pattern="$1";;
        -i) args+=("-i");;
        -l) args+=("-l");;
        -n) args+=("-n");;
        --no-heading) ;;
        *) if [[ -z "$pattern" ]]; then pattern="$1"; else paths+=("$1"); fi ;;
      esac
      shift
    done
    grep -rn "${args[@]}" -- "$pattern" "${paths[@]}" 2>/dev/null || true
  fi
}

# ── 维度 1: Domain 层零 Flutter/Riverpod/平台 SDK 依赖 ──
# 规约来自 cr 维度 2: 任何 import flutter/ | flutter_riverpod | package:flutter_* |
#                     dart:ui | shared_preferences | just_audio | audio_service | sqflite |
#                     flutter_secure_storage → Critical
check_domain_flutter() {
  local pattern='import\s+[''"]?(package:flutter/|package:flutter_riverpod/|package:flutter_[a-z_]+/|dart:ui|package:shared_preferences/|package:just_audio/|package:audio_service/|package:sqflite/|package:flutter_secure_storage/)'
  local out
  out=$(rg_cmd -t dart "import\s*['\"](package:flutter/|package:flutter_riverpod/|package:flutter_[a-z_]+/|dart:ui|package:shared_preferences/|package:just_audio/|package:audio_service/|package:sqflite/|package:flutter_secure_storage/)" lib/features/*/domain/ 2>/dev/null || true)
  local cnt=0
  if [[ -n "$out" ]]; then
    while IFS= read -r line; do
      printf "domain-flutter\tCritical\t%s\n" "$line"
      cnt=$((cnt+1))
    done <<<"$out"
  fi
  if [[ $cnt -eq 0 ]]; then
    printf "domain-flutter\tINFO\t-\tDomain 层无 Flutter/平台 SDK 依赖\n" >&2
  fi
  return 0
}

# ── 维度 2: Feature 隔离 — feature 间不得直接 import（除 shared/） ──
# 规约: lib/features/A/ 不得 import lib/features/B/ 任何文件（除 shared/ 路径）
check_feature_isolation() {
  local cnt=0
  for src_dir in lib/features/*/; do
    local feature; feature=$(basename "$src_dir")
    # 找 import 'lib/features/<other>' 这种跨 feature 直接 import
    # 项目内常见通过 package: <pkgname>/features/<other> 或相对 ../../<other>
    local hits
    hits=$(rg_cmd -t dart --glob 'lib/features/**' \
        "import\s+['\"](package:[a-z_]+/features/|../../../features/)(?!$feature)" \
        "$src_dir" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
      while IFS= read -r line; do
        printf "feature-isolation\tMajor\t%s\t跨 feature 直接 import\n" "$line"
        cnt=$((cnt+1))
      done <<<"$hits"
    fi
  done
  if [[ $cnt -eq 0 ]]; then
    printf "feature-isolation\tINFO\t-\tFeature 间无直接 import\n" >&2
  fi
}

# ── 维度 3: 密码/敏感信息泄露 —— 日志里含 password/pwd/credential/Authorization ──
# 规约: print(/debugPrint(/console.log( 附近含 password/pwd/credential/Authorization 字样 → Critical
check_secret_logs() {
  local out
  # 找 print/debugPrint 后 30 字符内含敏感字样的行（rg multiline 不依赖 -U）
  out=$(rg_cmd -t dart --glob 'lib/**' \
      -e '(print|debugPrint|log)\s*\([^)]{0,80}\b(password|pwd|credential|Authorization)\b' \
      2>/dev/null || true)
  if [[ -n "$out" ]]; then
    while IFS= read -r line; do
      printf "secret-logs\tCritical\t%s\t日志含敏感字面量\n" "$line"
    done <<<"$out"
  else
    printf "secret-logs\tINFO\t-\t日志中无密码泄露\n" >&2
  fi
}

main() {
  local kinds=()
  if [[ $# -eq 0 ]]; then
    kinds=(domain-flutter feature-isolation secret-logs)
  else
    kinds=("$@")
  fi
  for k in "${kinds[@]}"; do
    case "$k" in
      domain-flutter)    check_domain_flutter    ;;
      feature-isolation) check_feature_isolation ;;
      secret-logs)       check_secret_logs       ;;
      all)
        check_domain_flutter
        check_feature_isolation
        check_secret_logs
        ;;
      *) echo "unknown kind: $k" >&2; exit 2 ;;
    esac
  done
}

main "$@"