#!/usr/bin/env bash
#
# apply-patches.sh - repo sync 之后一键应用 ~/patch 下的本地补丁
#
# 目录约定:
#   ~/patch/<任意名字>/
#       target       补丁对应的仓库相对路径，例如 external/skia
#       *.patch      补丁文件（git diff / git format-patch 输出都可以，按文件名顺序应用）
#
# 用法:
#   ./apply-patches.sh                 # 应用所有子目录里的补丁
#   ./apply-patches.sh skia base       # 只应用指定目录
#   ./apply-patches.sh -n              # 只检查，不落盘（按顺序模拟，不会误报顺序依赖）
#
# 环境变量:
#   ANDROID_ROOT   源码根目录，默认 ~/pixelos

set -u

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ANDROID_ROOT:-$HOME/pixelos}"
DRY_RUN=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

TARGETS=()
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    usage 0 ;;
        -*)           echo "未知参数: $arg" >&2; usage 1 ;;
        *)            TARGETS+=("$arg") ;;
    esac
done

if [ ! -d "$ROOT/.repo" ]; then
    echo "错误: $ROOT 不是 repo 工作区（找不到 .repo）" >&2
    exit 1
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    while IFS= read -r d; do
        TARGETS+=("$(basename "$d")")
    done < <(find "$PATCH_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

applied=0; skipped=0; failed=0

for name in "${TARGETS[@]}"; do
    dir="$PATCH_DIR/$name"
    [ -d "$dir" ] || { echo "!! 没有这个目录: $dir" >&2; failed=$((failed+1)); continue; }

    mapfile -t patches < <(find "$dir" -maxdepth 1 -name '*.patch' | sort)
    [ ${#patches[@]} -eq 0 ] && continue

    if [ -f "$dir/target" ]; then
        repo_rel="$(tr -d '[:space:]' < "$dir/target")"
    else
        echo "!! $name: 缺少 target 文件（内容为仓库相对路径，如 external/skia）" >&2
        failed=$((failed+1)); continue
    fi

    repo="$ROOT/$repo_rel"
    if [ ! -d "$repo/.git" ]; then
        echo "-- $name: 仓库未同步（$repo_rel），跳过"
        skipped=$((skipped+${#patches[@]})); continue
    fi

    tmp_idx=""
    if [ $DRY_RUN -eq 1 ]; then
        tmp_idx="$(mktemp)"
        GIT_INDEX_FILE="$tmp_idx" git -C "$repo" read-tree HEAD 2>/dev/null
    fi

    for p in "${patches[@]}"; do
        f="$(basename "$p")"
        if git -C "$repo" apply --reverse --check "$p" >/dev/null 2>&1; then
            echo "-- $name/$f: 已应用"
            skipped=$((skipped+1)); continue
        fi
        if [ $DRY_RUN -eq 1 ]; then
            if GIT_INDEX_FILE="$tmp_idx" git -C "$repo" apply --cached "$p" >/dev/null 2>&1; then
                echo "-- $name/$f: 可应用（dry-run）"
                applied=$((applied+1))
            else
                echo "!! $name/$f: 不能应用（有冲突）" >&2
                failed=$((failed+1))
            fi
            continue
        fi
        if git -C "$repo" apply "$p" 2>/dev/null || git -C "$repo" apply -3 "$p" 2>/dev/null; then
            echo "++ $name/$f: 已应用"
            applied=$((applied+1))
        else
            echo "!! $name/$f: 应用失败" >&2
            failed=$((failed+1))
        fi
    done

    [ -n "$tmp_idx" ] && rm -f "$tmp_idx"
done

echo
echo "完成: 应用 $applied, 跳过 $skipped, 失败 $failed"
[ $failed -eq 0 ] || exit 1
