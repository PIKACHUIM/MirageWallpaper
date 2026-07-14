#!/usr/bin/env bash
#
# MirageWallpaper — 一键构建脚本（macOS）。
#
# 按依赖顺序构建全部组件：
#   1. SceneRenderer  → SceneWallpaper   (Homebrew Clang + MoltenVK)
#   2. WebRenderer    → WebWallpaper     (系统框架)
#   3. VideoRenderer  → VideoWallpaper   (系统框架)
#   4. Mirage         → Mirage.app       (xcodebuild)，并内嵌上述三个渲染器
#
# 各子项目已有独立的 scripts/build.sh；本脚本只是把它们编排在一起，
# 参数与环境变量尽量沿用子脚本的约定。
#
# 用法：
#   scripts/build_all.sh                 全量构建（release，默认）：三个渲染器 + App
#   scripts/build_all.sh debug           debug 构建
#   scripts/build_all.sh renderers       只构建三个渲染器（不构建 App）
#   scripts/build_all.sh app             只构建 Mirage App（假定渲染器已就绪）
#   scripts/build_all.sh scene|web|video 只构建指定的单个渲染器
#   scripts/build_all.sh clean           清理所有子项目的 build 目录
#   scripts/build_all.sh -h|--help
#
# 环境变量：
#   JOBS=N                      并行编译任务数（默认 hw.logicalcpu），透传给渲染器构建
#   MIRAGE_ARCH=arm64|x86_64    Mirage App 目标架构（默认当前架构）
#   MIRAGE_STEAM_WEB_API_KEY    可选，内置的 Steam Web API Key（32 位十六进制）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- terminal colors (disabled when not a TTY) ---
if [[ -t 1 ]]; then
    C_CYAN=$'\033[1;36m'; C_GRN=$'\033[1;32m'; C_RED=$'\033[1;31m'; C_YLW=$'\033[1;33m'; C_MAG=$'\033[1;35m'; C_OFF=$'\033[0m'
else
    C_CYAN=''; C_GRN=''; C_RED=''; C_YLW=''; C_MAG=''; C_OFF=''
fi
step() { printf '\n%s========== %s ==========%s\n' "$C_MAG" "$*" "$C_OFF"; }
info() { printf '%s==>%s %s\n' "$C_CYAN" "$C_OFF" "$*"; }
good() { printf '%sOK:%s %s\n'  "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%sWARN:%s %s\n' "$C_YLW" "$C_OFF" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
MirageWallpaper 一键构建脚本（macOS）。

用法：
  scripts/build_all.sh                 全量构建（release，默认）：三个渲染器 + App
  scripts/build_all.sh debug           debug 构建
  scripts/build_all.sh renderers       只构建三个渲染器（不构建 App）
  scripts/build_all.sh app             只构建 Mirage App（假定渲染器已就绪）
  scripts/build_all.sh scene           只构建 SceneRenderer
  scripts/build_all.sh web             只构建 WebRenderer
  scripts/build_all.sh video           只构建 VideoRenderer
  scripts/build_all.sh clean           清理所有子项目的 build 目录
  scripts/build_all.sh -h|--help       显示帮助

环境变量：
  JOBS=N                      并行编译任务数（默认 hw.logicalcpu）
  MIRAGE_ARCH=arm64|x86_64    Mirage App 目标架构（默认当前架构）
  MIRAGE_STEAM_WEB_API_KEY    可选，内置的 Steam Web API Key（32 位十六进制）
EOF
}

# --- 解析参数 ---
TARGET="all"
CONFIG="release"      # 渲染器用的小写 preset（release|debug）
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        all|renderers|app|scene|web|video|clean) TARGET="$1"; shift ;;
        release|debug) CONFIG="$1"; shift ;;
        *) die "未知参数: $1（试试 --help）" ;;
    esac
done

# xcodebuild 用大写首字母的 configuration 名。
if [[ "$CONFIG" == "debug" ]]; then
    XCODE_CONFIG="Debug"
else
    XCODE_CONFIG="Release"
fi

# --- 平台检查 ---
[[ "$(uname -s)" == "Darwin" ]] || die "本脚本仅支持 macOS。"

SCENE_SH="$ROOT_DIR/SceneRenderer/scripts/build.sh"
WEB_SH="$ROOT_DIR/WebRenderer/scripts/build.sh"
VIDEO_SH="$ROOT_DIR/VideoRenderer/scripts/build.sh"
MIRAGE_SH="$ROOT_DIR/Mirage/scripts/build.sh"

for s in "$SCENE_SH" "$WEB_SH" "$VIDEO_SH" "$MIRAGE_SH"; do
    [[ -f "$s" ]] || die "缺少子构建脚本: $s"
done

# --- 单组件构建封装 ---
build_scene() {
    step "构建 SceneRenderer ($CONFIG)"
    bash "$SCENE_SH" "$CONFIG"
}
build_web() {
    step "构建 WebRenderer ($CONFIG)"
    bash "$WEB_SH" "$CONFIG"
}
build_video() {
    step "构建 VideoRenderer ($CONFIG)"
    bash "$VIDEO_SH" "$CONFIG"
}
build_renderers() {
    build_scene
    build_web
    build_video
}
build_app() {
    step "构建 Mirage App ($XCODE_CONFIG)"
    bash "$MIRAGE_SH" "$XCODE_CONFIG"
}

# --- clean：清理所有子项目 ---
clean_all() {
    step "清理所有 build 目录"
    bash "$SCENE_SH" clean "$CONFIG" || true
    bash "$WEB_SH"   clean "$CONFIG" || true
    bash "$VIDEO_SH" clean "$CONFIG" || true
    if [[ -d "$ROOT_DIR/Mirage/build" ]]; then
        info "清理 Mirage/build"
        rm -rf "$ROOT_DIR/Mirage/build"
    fi
    if [[ -d "$ROOT_DIR/Mirage/dist" ]]; then
        info "清理 Mirage/dist"
        rm -rf "$ROOT_DIR/Mirage/dist"
    fi
}

# --- 分发 ---
case "$TARGET" in
    scene)     build_scene ;;
    web)       build_web ;;
    video)     build_video ;;
    renderers) build_renderers ;;
    app)       build_app ;;
    clean)     clean_all ;;
    all)       build_renderers; build_app ;;
esac

if [[ "$TARGET" == "all" || "$TARGET" == "app" ]]; then
    APP="$ROOT_DIR/Mirage/dist/Mirage.app"
    step "构建完成"
    if [[ -d "$APP" ]]; then
        good "产物: $APP"
    else
        warn "未找到 App 产物: $APP"
    fi
else
    good "done."
fi
