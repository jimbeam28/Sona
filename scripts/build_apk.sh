#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

export ANDROID_HOME="$HOME/Android"
export PATH="$HOME/development/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ---------- 清理上次 APK 构建产物 ----------
echo "==> 清理构建缓存..."
rm -rf build/

# ---------- flutter pub get ----------
NEED_PUB_GET=false
if [ ! -f "pubspec.lock" ] || [ ! -d ".dart_tool" ]; then
    NEED_PUB_GET=true
elif [ "pubspec.yaml" -nt "pubspec.lock" ]; then
    NEED_PUB_GET=true
fi

if $NEED_PUB_GET; then
    echo "==> 安装依赖..."
    flutter pub get
else
    echo "==> 跳过依赖安装 (已是最新)"
fi

# ---------- build_runner ----------
NEED_BUILD=false
if [ ! -d ".dart_tool/build" ]; then
    NEED_BUILD=true
else
    while IFS= read -r -d '' src; do
        gen="${src%.dart}.g.dart"
        if [ ! -f "$gen" ] || [ "$src" -nt "$gen" ]; then
            NEED_BUILD=true
            break
        fi
    done < <(find lib -name '*.dart' ! -name '*.g.dart' -print0)
fi

if $NEED_BUILD; then
    echo "==> 生成代码..."
    dart run build_runner build --delete-conflicting-outputs
else
    echo "==> 跳过代码生成 (已是最新)"
fi

# ---------- analyze ----------
echo "==> 静态分析..."
flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 || true

# ---------- test ----------
# 测试依赖 sqlite3 native lib，离线环境可能下载失败，此处跳过
# 开发时手动运行: flutter test
echo "==> 跳过测试 (离线环境)"

# ---------- build ----------
echo "==> 构建 release APK..."
flutter build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    SIZE=$(du -sh "$APK_PATH" | cut -f1)
    echo "==> 构建完成: $APK_PATH ($SIZE)"
else
    echo "==> 构建失败: APK 未生成"
    exit 1
fi
