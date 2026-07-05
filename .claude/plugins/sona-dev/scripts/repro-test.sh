#!/usr/bin/env bash
# repro-test.sh — 跑单条 Bug 复现测试并校验"修复前 FAIL / 修复后 PASS" 双态门禁
#
# 用法:
#   scripts/dev/repro-test.sh <test_path> <expect>
#
#   test_path  test/ 下相对路径，如 test/features/player/bug_bug01_repro_test.dart
#   expect     fail | pass
#
# 退出码:
#   0 = 实际结果与 expect 一致（门禁通过）
#   1 = 实际与 expect 不符（修复前应 FAIL 却 PASS / 修复后应 PASS 却 FAIL）
#   2 = 参数错 / 文件不存在 / 命令超时
#
# 设计动机：dev-plan 铁律 2 "Bug 修复先写失败复现测试"——dev-plan 必须确认 repro 测试 FAIL 才允继续；
# dev-exe 必须确认 repro 测试现 PASS 才允标 done。两段都用这个脚本统一校验。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <test_path> <expect: fail|pass>" >&2
  exit 2
fi
TEST_PATH="$1"
EXPECT="$2"
[[ -f "$TEST_PATH" ]] || { echo "ERROR: $TEST_PATH 不存在" >&2; exit 2; }
[[ "$EXPECT" == "fail" || "$EXPECT" == "pass" ]] || {
  echo "ERROR: expect 必须是 fail 或 pass" >&2; exit 2; }

LOG=$(mktemp -t repro-test.XXXXXX)
trap 'rm -f "$LOG"' EXIT

# flutter test 单文件通常 < 60s，留宽松预算到 180s
if ! timeout 180 flutter test "$TEST_PATH" >"$LOG" 2>&1; then
  rc=$?
  if [[ $rc -ne 1 && $rc -ne 124 ]]; then
    echo "==> [$TEST_PATH] 编译或运行错误（rc=$rc）："
    tail -30 "$LOG"
    exit 2
  fi
  # rc=1 测试 FAIL；rc=124 超时
  ACTUAL="fail"
else
  ACTUAL="pass"
fi

if [[ "$ACTUAL" == "$EXPECT" ]]; then
  echo "==> [$TEST_PATH] $EXPECT ✓ 符合预期"
  exit 0
fi
echo "==> [$TEST_PATH] expect=$EXPECT actual=$ACTUAL ✗"
tail -40 "$LOG"
exit 1