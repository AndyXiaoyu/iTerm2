#!/usr/bin/env bash
# ============================================================
# iTerm2 nib 中文注入工具
# 把 Interfaces/localization/zh-Hans/*.strings 的中文翻译
# 注入到已编译 app 包内对应的 .nib，使界面（菜单栏/偏好设置/各窗口）显示中文。
#
# 用法: ./scripts/inject_localization.sh <iTerm2.app 路径>
# 示例: ./scripts/inject_localization.sh build/Build/Products/Deployment/iTerm2.app
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✔]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[✘]${NC}    $*"; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
L10N_DIR="$REPO_ROOT/Interfaces/localization/zh-Hans"
MAP="$L10N_DIR/_xib_paths.map"

APP_PATH="${1:-}"
[[ -z "$APP_PATH" ]] && error "用法: $0 <iTerm2.app 路径>"
[[ -d "$APP_PATH" ]] || error "找不到 app: $APP_PATH"
[[ -f "$MAP" ]] || error "找不到映射表: $MAP（需先运行导出）"

RES_DIR="$APP_PATH/Contents/Resources"
[[ -d "$RES_DIR" ]] || error "找不到 Resources 目录: $RES_DIR"

command -v ibtool >/dev/null || error "未找到 ibtool（需安装 Xcode）"

info "开始注入中文本地化到 nib..."
ok=0; skip=0; fail=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

while IFS='|' read -r base xib_rel; do
  [[ -z "$base" ]] && continue
  strings_file="$L10N_DIR/$base.strings"
  src_xib="$REPO_ROOT/$xib_rel"
  dst_nib="$RES_DIR/$base.nib"

  # 翻译文件缺失则跳过
  if [[ ! -f "$strings_file" ]]; then skip=$((skip+1)); continue; fi
  # 目标 nib 缺失则跳过
  if [[ ! -e "$dst_nib" ]]; then warn "  跳过 $base（app 内无 $base.nib）"; skip=$((skip+1)); continue; fi
  # 源 xib 缺失则跳过
  if [[ ! -f "$src_xib" ]]; then warn "  跳过 $base（无源 xib）"; skip=$((skip+1)); continue; fi

  # ibtool 要求 strings 为 UTF-16 或带正确编码；翻译文件是 UTF-8，转成 UTF-16LE 临时文件
  tmp_strings="$TMP_DIR/$base.strings"
  if file "$strings_file" | grep -q "UTF-16"; then
    cp "$strings_file" "$tmp_strings"
  else
    iconv -f UTF-8 -t UTF-16LE "$strings_file" > "$tmp_strings" 2>/dev/null || cp "$strings_file" "$tmp_strings"
  fi

  # 用源 xib + 中文 strings 重新编译出中文 nib，覆盖 app 内的 nib
  if ibtool --import-strings-file "$tmp_strings" --compile "$dst_nib" "$src_xib" 2>"$TMP_DIR/err.log"; then
    ok=$((ok+1))
  else
    warn "  注入失败 $base: $(head -1 "$TMP_DIR/err.log" 2>/dev/null)"
    fail=$((fail+1))
  fi
done < "$MAP"

echo ""
success "注入完成：成功 ${ok}，跳过 ${skip}，失败 ${fail}"
[[ "$fail" -gt 0 ]] && warn "有 ${fail} 个 nib 注入失败，请检查上面日志"
exit 0
