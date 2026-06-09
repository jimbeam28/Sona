#!/bin/bash
# 提交前快速检查脚本
# 使用方法: ./scripts/check.sh

set -e

echo "🔍 Step 1: 格式化代码..."
dart format lib test

echo "🔍 Step 2: 静态分析..."
flutter analyze --no-fatal-infos

echo "🔍 Step 3: 运行测试..."
flutter test

echo "✅ 所有检查通过！可以安全提交了。"