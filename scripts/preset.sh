#!/bin/bash
# 共享的 CMake preset 命名约定。
# SceneRenderer 使用 `macos-{arch}-clang-{config}` 格式。
# 本文件由 Mirage/scripts/build.sh、Mirage/scripts/bundle_renderers.sh
# 和 SceneRenderer/scripts/build.sh 共同 source。
#
# 使用方式：
#   source "${SCRIPT_DIR}/../../scripts/preset.sh"   # 从 Mirage/scripts/ 下
#   source "${SCRIPT_DIR}/../scripts/preset.sh"      # 从 SceneRenderer/scripts/ 下
#
# 导出函数：
#   scene_preset [config]   → 输出 "macos-arm64-clang-release" 或 "macos-clang-release"

scene_preset() {
    local config="${1:-release}"
    local arch
    arch="$(uname -m)"
    echo "macos-${arch}-clang-${config}"
}
