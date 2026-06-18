#!/usr/bin/env bash
# ============================================================
# iTerm2 中文版 修复工具
# 双击此文件运行，自动修复 Gatekeeper 拦截问题
# ============================================================

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

clear
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     iTerm2 中文版 - 修复工具              ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "此工具将解决 macOS Gatekeeper 拦截问题。"
echo "（因本版本使用 Ad-hoc 签名，非 App Store 分发）"
echo ""

# -------- 自动定位 iTerm2.app --------
locate_app() {
  local candidates=(
    "/Applications/iTerm.app"
    "/Applications/iTerm2.app"
    "$HOME/Applications/iTerm.app"
    "$HOME/Applications/iTerm2.app"
  )
  for c in "${candidates[@]}"; do
    [[ -d "$c" ]] && echo "$c" && return 0
  done
  return 1
}

APP_PATH=$(locate_app || true)

if [[ -z "$APP_PATH" ]]; then
  echo -e "${YELLOW}未在 Applications 中找到 iTerm2.app${NC}"
  echo ""
  echo "请先将 iTerm2.app 拖入 Applications 文件夹，然后重新运行此工具。"
  echo ""
  echo "按任意键退出..."
  read -r -n 1
  exit 1
fi

echo -e "找到应用: ${GREEN}$APP_PATH${NC}"
echo ""
echo "即将执行以下操作（需要管理员权限）："
echo "  1. 移除隔离标记 (xattr -cr)"
echo "  2. 重新 Ad-hoc 签名 (codesign --force --deep)"
echo ""
echo -n "继续？[Y/n] "
read -r answer
answer="${answer:-Y}"
if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
  echo "已取消。"
  exit 0
fi

echo ""
echo -e "${BLUE}[1/2]${NC} 移除隔离标记..."
if xattr -cr "$APP_PATH" 2>/dev/null; then
  echo -e "      ${GREEN}✔ 完成${NC}"
else
  echo -e "      ${YELLOW}⚠ 需要管理员权限，请输入密码：${NC}"
  sudo xattr -cr "$APP_PATH"
  echo -e "      ${GREEN}✔ 完成${NC}"
fi

echo ""
echo -e "${BLUE}[2/2]${NC} 重新签名..."
if codesign --force --deep --sign - "$APP_PATH" 2>/dev/null; then
  echo -e "      ${GREEN}✔ 完成${NC}"
else
  echo -e "      ${YELLOW}⚠ 需要管理员权限，请输入密码：${NC}"
  sudo codesign --force --deep --sign - "$APP_PATH"
  echo -e "      ${GREEN}✔ 完成${NC}"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo -e "║  ${GREEN}修复完成！现在可以正常打开 iTerm2 了。${NC}  ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "如仍有问题，请在系统设置 → 隐私与安全 → 允许 中手动放行。"
echo ""

# 询问是否直接打开
echo -n "是否立即打开 iTerm2？[Y/n] "
read -r open_answer
open_answer="${open_answer:-Y}"
if [[ "$open_answer" == "Y" || "$open_answer" == "y" ]]; then
  open "$APP_PATH"
fi

echo ""
echo "按任意键关闭此窗口..."
read -r -n 1
