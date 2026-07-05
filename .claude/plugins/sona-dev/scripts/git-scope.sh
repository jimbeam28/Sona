#!/usr/bin/env bash
# git-scope.sh — git 范围扫描：列 commit + 各 commit 改动文件 + diff 文件清单
#
# 用法:
#   scripts/dev/git-scope.sh recent [-N <count>]
#     列最近 N 个 commit 的 sha + subject + 改动文件
#   scripts/dev/git-scope.sh since --since <date> [--until <date>]
#     按时间区间列 commit + 改动文件
#   scripts/dev/git-scope.sh grep --grep <keyword> [-i]
#     关键字筛 commit (大小写不敏感可选)
#   scripts/dev/git-scope.sh files <sha>
#     列某 sha 改动的文件清单
#   scripts/dev/git-scope.sh diff <sha>
#     列 <sha>..HEAD 间所有改动文件清单
#
# 输出格式：
#   recent/since/grep 模式：blocks 以 sha 提头，后跟每个改动文件
#   files/diff 模式：一行一个文件
#
# 设计动机：cr 走查与 dev-check 检查 5"跨模块漏识破坏"都需要列本次 commit 文件清单，
#      原本 SKILL.md 中散见 git log --since=... / git log -N / git show <sha> --name-only 等裸命令，
#      本脚本统一封装。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

SUB="${1:-}"
shift || true

case "$SUB" in
  recent)
    N=3
    [[ "${1:-}" == "-N" ]] && { N="$2"; shift 2; }
    git log -"$N" --name-only --pretty=format:"=== %h %s" "$@"
    ;;
  since)
    SINCE=""; UNTIL=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        --until) UNTIL="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    ARGS=()
    [[ -n "$SINCE" ]] && ARGS+=(--since="$SINCE")
    [[ -n "$UNTIL" ]] && ARGS+=(--until="$UNTIL")
    git log "${ARGS[@]}" --name-only --pretty=format:"=== %h %s"
    ;;
  grep)
    KEYWORD=""; ICASE=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --grep) KEYWORD="$2"; shift 2 ;;
        -i)     ICASE=1; shift ;;
        *) shift ;;
      esac
    done
    ARGS=(--grep="$KEYWORD")
    [[ $ICASE -eq 1 ]] && ARGS+=(-i)
    git log "${ARGS[@]}" --name-only --pretty=format:"=== %h %s"
    ;;
  files)
    SHA="${1:?missing sha}"
    git show "$SHA" --name-only --pretty=format:"=== %h %s"
    ;;
  diff)
    SHA="${1:?missing sha}"
    git diff --name-only "$SHA"..HEAD
    ;;
  *)
    cat <<EOF
usage: $0 {recent [-N n] | since --since d [--until d] | grep --grep k [-i] | files <sha> | diff <sha>}
EOF
    exit 2 ;;
esac