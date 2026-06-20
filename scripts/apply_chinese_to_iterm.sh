#!/usr/bin/env bash
# ============================================================
# 给官方 iTerm.app 注入中文界面（菜单栏/偏好设置/各窗口）。
#
# 为什么不就地改：/Applications 下的官方 app 有防篡改保护(com.apple.macl)，
# ibtool 会「删旧 nib 成功、写新 nib 被拒」，把 app 改坏。所以本脚本改为：
#   拷到临时目录 → 注入 → 重签 → 备份原版 → 整体替换整个 .app
#
# 右键终端的上下文菜单标题硬编码在源码二进制里，注入方式无法汉化，保持英文。
#
# 官方自动更新后界面会变回英文，重跑本脚本即可恢复中文。
#
# 用法: ./scripts/apply_chinese_to_iterm.sh [iTerm.app 路径]
#       默认 /Applications/iTerm.app
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✔]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[✘]${NC}    $*"; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-/Applications/iTerm.app}"
ZH_MARK="$(printf '\xe7\xaa\x97\xe5\x8f\xa3')"   # 「窗口」UTF-8，用于校验注入
# 注：检测 nib 二进制里的中文必须用 LC_ALL=C 做字节级匹配；
# 在 UTF-8 locale 下 grep 会对二进制误判导致漏匹配。
zhcount() { LC_ALL=C grep -ac "$ZH_MARK" "$1" 2>/dev/null || true; }

[[ -d "$APP" ]] || error "找不到 app：$APP"
command -v ibtool   >/dev/null || error "缺少 ibtool（需安装 Xcode 命令行工具）"
command -v codesign >/dev/null || error "缺少 codesign"
command -v ditto    >/dev/null || error "缺少 ditto"

if pgrep -f "$APP/Contents/MacOS/" >/dev/null 2>&1; then
  error "$APP 正在运行，请先完全退出再执行（整体替换需要移动 app）"
fi

WORK_DIR="$(mktemp -d)"
WORK="$WORK_DIR/$(basename "$APP")"
ENT="$WORK_DIR/entitlements.plist"
trap 'rm -rf "$WORK_DIR"' EXIT

info "1/6 拷贝到临时目录..."
ditto "$APP" "$WORK"
# 清除防篡改属性，让临时副本可被 ibtool 写入
xattr -cr "$WORK" 2>/dev/null || true

info "2/6 导出原 entitlements（保留摄像头/麦克风/自动化等权限）..."
if codesign -d --entitlements ":$ENT" "$APP" 2>/dev/null && [[ -s "$ENT" ]]; then
  success "已导出 entitlements"
else
  warn "未能导出 entitlements，将不带 entitlements 重签"
  : > "$ENT"
fi

info "3/6 注入中文 nib 到临时副本..."
"$REPO_ROOT/scripts/inject_localization.sh" "$WORK"

info "4/6 ad-hoc 重新签名（保留 entitlements）..."
if [[ -s "$ENT" ]]; then
  codesign --force --deep --sign - --entitlements "$ENT" "$WORK"
else
  codesign --force --deep --sign - "$WORK"
fi
codesign --verify --deep "$WORK" 2>/dev/null \
  && success "临时副本签名验证通过" \
  || error "临时副本签名验证失败，已中止，未改动原 app"
zh_cnt="$(zhcount "$WORK/Contents/Resources/MainMenu.nib")"
[[ "${zh_cnt:-0}" -gt 0 ]] || error "临时副本未检出中文，已中止，未改动原 app"
success "临时副本已汉化（菜单 nib 中文命中 ${zh_cnt}）"

info "5/6 备份原版并整体替换..."
BK_DIR="$HOME/.iterm-zh/backup"; mkdir -p "$BK_DIR"
BK="$BK_DIR/$(basename "$APP").bak"
if [[ ! -e "$BK" ]]; then
  ditto "$APP" "$BK" || error "备份失败，已中止，未改动原 app"
  success "原版已备份: $BK"
else
  info "已有备份，跳过: $BK"
fi
ROLLBACK="$WORK_DIR/rollback"
if ! mv "$APP" "$ROLLBACK" 2>/dev/null; then
  error "无法移走旧 app（权限不足或被占用），未改动原 app"
fi
if ditto "$WORK" "$APP" 2>/dev/null; then
  rm -rf "$ROLLBACK"
  success "已整体替换为中文版"
else
  mv "$ROLLBACK" "$APP"   # 回滚
  error "替换失败，已回滚到原版"
fi

info "6/6 最终验证..."
codesign --verify --deep "$APP" 2>/dev/null && success "签名验证通过" || warn "签名验证未通过（本地手动打开通常仍可运行）"
final_cnt="$(zhcount "$APP/Contents/Resources/MainMenu.nib")"
[[ "${final_cnt:-0}" -gt 0 ]] && success "菜单 nib 已是中文（命中 ${final_cnt}）" || warn "未检出中文"

echo ""
success "完成：$APP 菜单栏/偏好设置/各窗口已汉化"
warn   "右键菜单受源码限制仍为英文"
info   "原版备份在 $BK；官方更新后重跑本脚本即可恢复中文。"
