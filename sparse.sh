#!/usr/bin/env bash
#
# sparse.sh - 重新应用 sparse-checkout 配置
#
# 什么时候用：
#   repo sync --force-sync / -d / 全新 init+sync 之后，git 目录被重建，
#   sparse 配置会丢失，跑这个脚本恢复（普通 repo sync 不需要）。
#
# 配置：同目录下 sparse.conf，每行 "仓库相对路径 = 目录1 目录2 ..."
#   只有列出的目录会被 checkout，仓库根目录的文件始终保留。
#
# 用法：
#   ./sparse.sh            # 应用所有
#   ./sparse.sh -n         # 只显示会做什么

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ANDROID_ROOT:-$HOME/pixelos}"
CONF="$HERE/sparse.conf"
DRY=0
[ "${1:-}" = "-n" ] && DRY=1

[ -f "$CONF" ] || { echo "缺少 $CONF" >&2; exit 1; }

fail=0
while IFS='=' read -r repo dirs; do
    repo="$(echo "$repo" | xargs)"
    [ -z "$repo" ] && continue
    case "$repo" in \#*) continue ;; esac

    full="$ROOT/$repo"
    if [ ! -d "$full/.git" ]; then
        echo "-- $repo: 未同步，跳过"
        continue
    fi
    [ -n "$dirs" ] || { echo "!! $repo: 目录列表为空，跳过（防止清空工作区）" >&2; fail=1; continue; }

    echo "== $repo"
    echo "   keep: $dirs"
    if [ $DRY -eq 1 ]; then continue; fi

    git -C "$full" sparse-checkout init --cone || { fail=1; continue; }
    # shellcheck disable=SC2086
    git -C "$full" sparse-checkout set $dirs || fail=1
done < "$CONF"

echo
[ $fail -eq 0 ] && echo "完成" || echo "有失败项" >&2
exit $fail
