#!/bin/bash
# ============================================================
# iTerm2 中文汉化补丁 - 注入式安装脚本（macOS）
# 双击运行即可。把中文界面注入到已安装的官方 iTerm2，
# 无需重新编译、无需 Xcode。
#
# 适用：iTerm2 3.6.11（其他版本结构可能不同，会提示）
# 更新 iTerm2 后被官方英文覆盖，重新双击本脚本即可恢复汉化。
# ============================================================
set -uo pipefail

# 切到脚本所在目录
cd "$(dirname "$0")"
RES="resources"
TARGET_VERSION="3.6.11"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { printf "${BLUE}[信息]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[完成]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[注意]${NC} %s\n" "$*"; }
err()   { printf "${RED}[错误]${NC} %s\n" "$*"; }
die()   { err "$*"; echo ""; read -r -p "按回车键退出..." _; exit 1; }

echo ""
echo "================================================="
echo "      iTerm2 中文汉化补丁 - 安装程序"
echo "================================================="
echo ""

# -------- 资源检查 --------
[ -d "$RES/nibs" ] || die "找不到资源目录 $RES/nibs，请确保完整解压补丁包。"
[ -f "$RES/nib_list.txt" ] || die "找不到 $RES/nib_list.txt。"

# -------- 定位已安装的 iTerm2 --------
info "查找已安装的 iTerm2..."
APP=""
for cand in "/Applications/iTerm.app" "/Applications/iTerm2.app" "$HOME/Applications/iTerm.app" "$HOME/Applications/iTerm2.app"; do
  if [ -d "$cand" ]; then
    bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$cand/Contents/Info.plist" 2>/dev/null)
    if [ "$bid" = "com.googlecode.iterm2" ]; then APP="$cand"; break; fi
  fi
done
[ -n "$APP" ] || die "未找到已安装的 iTerm2，请先从 https://iterm2.com 安装官方版。"
ok "找到 iTerm2：$APP"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null)
info "已安装版本：$VER"
if [ "$VER" != "$TARGET_VERSION" ]; then
  warn "本补丁针对 iTerm2 $TARGET_VERSION 制作，你的版本是 $VER。"
  warn "界面结构若有变化，可能部分汉化不生效或异常。"
  read -r -p "仍要继续吗？(y/N) " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || die "已取消。"
fi

RES_DIR="$APP/Contents/Resources"
[ -w "$APP" ] || die "没有写入 $APP 的权限。请将 iTerm2 放在 /Applications 并确保当前用户可写，或用管理员账户运行。"

# -------- 退出正在运行的 iTerm2 --------
if pgrep -x "iTerm2" >/dev/null 2>&1; then
  warn "iTerm2 正在运行，需要退出后才能打补丁。"
  read -r -p "现在退出 iTerm2 吗？(y/N) " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || die "请先手动退出 iTerm2 再运行本脚本。"
  osascript -e 'tell application "iTerm2" to quit' 2>/dev/null
  sleep 2
  pkill -x "iTerm2" 2>/dev/null
  sleep 1
fi

# -------- 备份 --------
BACKUP_DIR="$HOME/.iterm2-zh-backup"
STAMP=$(date +%Y%m%d-%H%M%S)
BK="$BACKUP_DIR/$STAMP"
info "备份原始文件到：$BK"
mkdir -p "$BK/Resources"
# 备份将被覆盖的 nib 和 strings
while IFS= read -r base; do
  [ -z "$base" ] && continue
  [ -e "$RES_DIR/$base.nib" ] && cp -R "$RES_DIR/$base.nib" "$BK/Resources/" 2>/dev/null
done < "$RES/nib_list.txt"
for s in iTerm.strings MainMenu.strings; do
  [ -e "$RES_DIR/$s" ] && cp "$RES_DIR/$s" "$BK/Resources/" 2>/dev/null
done
# 记录被打补丁的 app 路径，便于卸载
echo "$APP" > "$BK/app_path.txt"
ln -sfn "$BK" "$BACKUP_DIR/latest"
ok "备份完成"

# -------- 注入中文 nib --------
info "注入中文界面（菜单栏 / 偏好设置 / 所有窗口）..."
cnt=0; fail=0
while IFS= read -r base; do
  [ -z "$base" ] && continue
  src="$RES/nibs/$base.nib"
  dst="$RES_DIR/$base.nib"
  if [ -e "$src" ] && [ -e "$dst" ]; then
    rm -rf "$dst"
    if cp -R "$src" "$dst" 2>/dev/null; then cnt=$((cnt+1)); else fail=$((fail+1)); fi
  fi
done < "$RES/nib_list.txt"
ok "已注入 $cnt 个界面文件（跳过/失败 $fail）"

# -------- 复制对话框 strings --------
info "注入对话框 / 提示文本..."
for s in iTerm.strings MainMenu.strings; do
  [ -e "$RES/strings/$s" ] && cp "$RES/strings/$s" "$RES_DIR/$s" 2>/dev/null
done
ok "对话框文本已注入"

# -------- 右键菜单（可选，需版本精确匹配 + 提供本地化二进制）--------
if [ -f "$RES/iTerm2-bin" ] && [ "$VER" = "$TARGET_VERSION" ]; then
  info "注入右键菜单汉化（替换主程序）..."
  cp "$APP/Contents/MacOS/iTerm2" "$BK/iTerm2-bin.orig" 2>/dev/null
  if cp "$RES/iTerm2-bin" "$APP/Contents/MacOS/iTerm2" 2>/dev/null; then
    chmod +x "$APP/Contents/MacOS/iTerm2"
    ok "右键菜单已汉化"
  else
    warn "右键菜单注入失败，已跳过（其余汉化不受影响）"
  fi
else
  warn "右键菜单保持英文（需版本匹配 $TARGET_VERSION 且补丁包含本地化二进制）"
fi

# -------- 重新签名 + 解除隔离 --------
info "重新签名（ad-hoc）并解除隔离属性..."
find "$APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null | while read -r f; do
  codesign --force --sign - "$f" >/dev/null 2>&1
done
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
ok "签名与隔离处理完成"

echo ""
echo "================================================="
ok "汉化完成！"
echo "  应用：$APP"
echo "  版本：$VER"
echo "  备份：$BK"
echo ""
echo "  提示：iTerm2 更新后会恢复英文，重新双击本脚本即可再次汉化。"
echo "  卸载汉化：双击同目录的 uninstall-mac.command"
echo "================================================="
echo ""
read -r -p "按回车键退出，并启动 iTerm2..." _
open "$APP"
