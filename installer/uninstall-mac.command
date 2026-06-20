#!/bin/bash
# ============================================================
# iTerm2 中文汉化补丁 - 卸载脚本（macOS）
# 从备份还原英文原版界面。双击运行。
# ============================================================
set -uo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { printf "${BLUE}[信息]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[完成]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[注意]${NC} %s\n" "$*"; }
err()   { printf "${RED}[错误]${NC} %s\n" "$*"; }
die()   { err "$*"; echo ""; read -r -p "按回车键退出..." _; exit 1; }

echo ""
echo "================================================="
echo "      iTerm2 中文汉化补丁 - 卸载程序"
echo "================================================="
echo ""

BACKUP_DIR="$HOME/.iterm2-zh-backup"
[ -d "$BACKUP_DIR/latest" ] || die "找不到备份（$BACKUP_DIR/latest）。可能从未安装过汉化补丁。"

BK="$BACKUP_DIR/latest"
APP=$(cat "$BK/app_path.txt" 2>/dev/null)
[ -n "$APP" ] && [ -d "$APP" ] || die "找不到原应用路径。"
info "将从备份还原：$APP"
info "备份位置：$(readlink "$BK" 2>/dev/null || echo "$BK")"

# 退出 iTerm2
if pgrep -x "iTerm2" >/dev/null 2>&1; then
  osascript -e 'tell application "iTerm2" to quit' 2>/dev/null
  sleep 2; pkill -x "iTerm2" 2>/dev/null; sleep 1
fi

RES_DIR="$APP/Contents/Resources"

# 还原 nib 和 strings
info "还原界面文件..."
n=0
if [ -d "$BK/Resources" ]; then
  for item in "$BK/Resources"/*; do
    [ -e "$item" ] || continue
    name=$(basename "$item")
    rm -rf "$RES_DIR/$name"
    cp -R "$item" "$RES_DIR/$name" 2>/dev/null && n=$((n+1))
  done
fi
ok "已还原 $n 个文件"

# 还原主程序（如有）
if [ -f "$BK/iTerm2-bin.orig" ]; then
  info "还原主程序（右键菜单）..."
  cp "$BK/iTerm2-bin.orig" "$APP/Contents/MacOS/iTerm2" 2>/dev/null && chmod +x "$APP/Contents/MacOS/iTerm2"
  ok "主程序已还原"
fi

# 重新签名
info "重新签名..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
ok "完成"

echo ""
echo "================================================="
ok "已还原为英文原版！"
echo "================================================="
echo ""
read -r -p "按回车键退出..." _
