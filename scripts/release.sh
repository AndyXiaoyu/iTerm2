#!/usr/bin/env bash
# ============================================================
# iTerm2 中文版 一键 Release 脚本
# 用法: ./scripts/release.sh [版本号]
# 示例: ./scripts/release.sh v3.6.11-zh-CN
# ============================================================
set -euo pipefail

# -------- 颜色输出 --------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✔]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[✘]${NC}    $*"; exit 1; }

# -------- 配置 --------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/iTerm2.xcodeproj"
SCHEME="iTerm2"
CONFIGURATION="Deployment"
BUILD_DIR="$REPO_ROOT/build"
APP_PATH="$BUILD_DIR/Build/Products/Deployment/iTerm2.app"
SCRIPTS_DIR="$REPO_ROOT/scripts"
DMG_STAGING="$BUILD_DIR/dmg_staging"
FIX_TOOL_SRC="$SCRIPTS_DIR/修复工具.command"

# -------- 版本号 --------
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  # 自动从 git log 生成版本号
  UPSTREAM_TAG=$(git describe --tags --match "v[0-9]*" --abbrev=0 2>/dev/null || echo "v0.0.0")
  VERSION="${UPSTREAM_TAG}-zh-CN"
  warn "未指定版本号，自动使用: $VERSION"
fi
DMG_NAME="iTerm2-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo ""
echo "================================================="
echo "   iTerm2 中文版 Release 构建"
echo "   版本: $VERSION"
echo "================================================="
echo ""

# -------- Step 0: 检查依赖工具 --------
info "检查依赖工具..."
command -v xcodebuild >/dev/null || error "未找到 xcodebuild，请安装 Xcode"
command -v hdiutil    >/dev/null || error "未找到 hdiutil"
command -v gh         >/dev/null || error "未找到 GitHub CLI (gh)，请运行: brew install gh"
success "工具检查通过"

# -------- Step 1: 同步 Xcode 版本文件 --------
info "同步 Xcode 版本..."
CURRENT_XCODE=$(xcodebuild -version)
LAST_XCODE=$(cat "$REPO_ROOT/last-xcode-version" 2>/dev/null || echo "")
if [[ "$CURRENT_XCODE" != "$LAST_XCODE" ]]; then
  warn "Xcode 版本已变更，更新 last-xcode-version..."
  echo "$CURRENT_XCODE" > "$REPO_ROOT/last-xcode-version"
fi
success "Xcode 版本: $(xcodebuild -version | head -1)"

# -------- Step 2: 初始化/更新关键子模块 --------
info "检查子模块..."
for sub in submodules/SwiftyMarkdown submodules/Highlightr; do
  if [[ ! -f "$REPO_ROOT/$sub"/*.xcodeproj/project.pbxproj ]] 2>/dev/null && \
     [[ -z "$(ls -A "$REPO_ROOT/$sub" 2>/dev/null)" ]]; then
    info "  初始化子模块: $sub"
    git -C "$REPO_ROOT" submodule update --init "$sub"
  fi
done
# iTerm2-shell-integration 子模块 (提供 conductor.sh 等资源)
if [[ ! -f "$REPO_ROOT/submodules/iTerm2-shell-integration/ssh-helpers/conductor.sh" ]]; then
  info "  初始化子模块: iTerm2-shell-integration"
  git -C "$REPO_ROOT" submodule update --init submodules/iTerm2-shell-integration 2>/dev/null || \
    git clone --depth 1 https://github.com/gnachman/iTerm2-shell-integration.git "$REPO_ROOT/submodules/iTerm2-shell-integration" 2>/dev/null || true
fi
success "子模块就绪"

# -------- Step 3: 重建不兼容的预编译框架 --------
rebuild_if_needed() {
  local name="$1"
  local submodule="$REPO_ROOT/$2"
  local framework_dst="$REPO_ROOT/ThirdParty/${name}.framework"

  info "检查 ${name}.framework 兼容性..."

  # 用 swiftc 验证模块是否可用
  local needs_rebuild=false
  if ! swiftc -typecheck /dev/null -F "$framework_dst/.." -sdk "$(xcrun --show-sdk-path)" 2>/dev/null; then
    needs_rebuild=true
  fi
  if [[ ! -d "$framework_dst" ]]; then
    needs_rebuild=true
  fi

  if [[ "$needs_rebuild" == "false" ]]; then
    success "  ${name}.framework 已兼容，跳过重建"
    return 0
  fi

  warn "  ${name}.framework 需要重建"
  git -C "$REPO_ROOT" submodule update --init "$(basename "$submodule")" 2>/dev/null || true

  local out_dir="$submodule/build/Release"
  mkdir -p "$out_dir"

  info "  编译 ${name}..."
  if [[ "$name" == "SwiftyMarkdown" ]]; then
    xcodebuild \
      -project "$submodule/SwiftyMarkdown.xcodeproj" \
      -configuration Release \
      CONFIGURATION_BUILD_DIR="$out_dir" \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
      build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | tail -3
  elif [[ "$name" == "Highlightr" ]]; then
    xcodebuild \
      -project "$submodule/Highlightr.xcodeproj" \
      -target Highlightr-macOS \
      -configuration Release \
      CONFIGURATION_BUILD_DIR="$out_dir" \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
      build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | tail -3
  fi

  if [[ ! -d "$out_dir/${name}.framework" ]]; then
    error "  ${name}.framework 编译失败"
  fi
  rm -rf "$framework_dst"
  cp -r "$out_dir/${name}.framework" "$framework_dst"
  success "  ${name}.framework 重建完成"
}

rebuild_if_needed "SwiftyMarkdown" "submodules/SwiftyMarkdown"
rebuild_if_needed "Highlightr"     "submodules/Highlightr"

# -------- Step 4: 下载缺失的 Xcode 组件 --------
info "检查 Metal Toolchain..."
if ! xcrun -find metal &>/dev/null; then
  warn "Metal Toolchain 缺失，正在下载..."
  xcodebuild -downloadComponent MetalToolchain 2>&1 | tail -2
fi
success "Metal Toolchain 就绪"

# -------- Step 4.5: 修复 .strings 文件格式 --------
info "检查 .strings 文件格式..."
python3 - "$REPO_ROOT/Interfaces" << 'PYEOF'
import sys, re, subprocess, os
interfaces_dir = sys.argv[1]
fixed_total = 0
for fname in ['iTerm.strings', 'MainMenu.strings']:
    fpath = os.path.join(interfaces_dir, fname)
    if not os.path.exists(fpath):
        continue
    with open(fpath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    fixed = []
    for line in lines:
        s = line.strip()
        if not s or s.startswith('/*') or s.startswith('*/'):
            continue
        # Fix missing spaces around =: "key"="value";
        m = re.match(r'^"([^"]*)"="([^"]*)"\s*;\s*$', s)
        if m:
            fixed.append(f'"{m.group(1)}" = "{m.group(2)}";\n')
            fixed_total += 1
            continue
        # Fix missing close quote on key: "key = "value";
        m = re.match(r'^"(.+?)\s+=\s+"(.*?)"\s*;\s*$', s)
        if m and not re.match(r'^"[^"]*"\s*=\s*"[^"]*"\s*;\s*$', s):
            fixed.append(f'"{m.group(1)}" = "{m.group(2)}";\n')
            fixed_total += 1
            continue
        # Valid or unfixable - check if it passes plutil
        if re.match(r'^"[^"]*"\s*=\s*"[^"]*"\s*;\s*$', s):
            fixed.append(line)
        else:
            # Skip broken lines (e.g. embedded unescaped quotes)
            fixed_total += 1
            continue
    with open(fpath, 'w', encoding='utf-8') as f:
        f.writelines(fixed)
if fixed_total > 0:
    print(f'  Fixed {fixed_total} format issues')
PYEOF
success ".strings 文件格式检查完成"

# -------- Step 5: 编译主项目 --------
info "编译 iTerm2 (配置: $CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | grep -E "^(error:|warning:.*error|Build succeeded|BUILD FAILED|CompileSwift|Ld )" | tail -20

if [[ ! -d "$APP_PATH" ]]; then
  error "编译失败，未找到 $APP_PATH"
fi
success "编译完成: $APP_PATH"

# -------- Step 5.5: 注入中文本地化到 nib --------
# iTerm2 的菜单栏/偏好设置/各窗口由 nib 渲染，平铺 .strings 不会自动生效，
# 必须用 ibtool 把 Interfaces/localization/zh-Hans/ 的翻译注入对应 nib。
# 注意：必须在签名之前注入，因为修改 nib 会使签名失效。
info "注入中文本地化到 nib..."
if [[ -f "$SCRIPTS_DIR/inject_localization.sh" && -d "$REPO_ROOT/Interfaces/localization/zh-Hans" ]]; then
  bash "$SCRIPTS_DIR/inject_localization.sh" "$APP_PATH"
else
  warn "未找到注入脚本或本地化目录，跳过 nib 注入（界面可能仍为英文）"
fi

# -------- Step 6: Ad-hoc 签名 --------
info "Ad-hoc 签名..."
codesign --force --deep --sign - "$APP_PATH" 2>&1 || true
success "签名完成"

# -------- Step 7: 打包 DMG --------
info "打包 DMG..."
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"

# 复制 app
cp -r "$APP_PATH" "$DMG_STAGING/"

# 添加 Applications 快捷方式
ln -s /Applications "$DMG_STAGING/Applications"

# 复制修复工具
if [[ -f "$FIX_TOOL_SRC" ]]; then
  cp "$FIX_TOOL_SRC" "$DMG_STAGING/修复工具（首次打开必读）.command"
  chmod +x "$DMG_STAGING/修复工具（首次打开必读）.command"
fi

hdiutil create \
  -volname "iTerm2 ${VERSION}" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

success "DMG 创建完成: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# -------- Step 8: 创建 GitHub Tag 和 Release --------
info "发布到 GitHub..."

# 检查 tag 是否已存在
if git tag --list | grep -q "^${VERSION}$"; then
  warn "Tag $VERSION 已存在，跳过创建"
else
  git tag -a "$VERSION" -m "iTerm2 ${VERSION} 中文汉化版"
  git push origin "$VERSION"
  success "Tag $VERSION 已推送"
fi

# 生成 Release Notes
RELEASE_NOTES="## iTerm2 ${VERSION} 中文汉化版

### 下载安装
1. 下载 \`${DMG_NAME}\` 并打开
2. 将 **iTerm2.app** 拖入 Applications 文件夹
3. 如遇 Gatekeeper 拦截，运行 DMG 内的「修复工具」脚本

### 关于汉化
基于官方 [iTerm2](https://iterm2.com) 最新版，完整汉化 UI 界面。

### 已知限制
- 使用 Ad-hoc 签名（非 Apple 开发者签名），首次打开需手动允许
- 运行「修复工具」可自动解决签名问题

> Built with Xcode $(xcodebuild -version | head -1)"

GITHUB_REPO=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')
GITHUB_TOKEN= gh release create "$VERSION" \
  --repo "$GITHUB_REPO" \
  --title "iTerm2 ${VERSION} 中文汉化版" \
  --notes "$RELEASE_NOTES" \
  "$DMG_PATH"

echo ""
echo "================================================="
success "发布完成！"
echo "  版本: $VERSION"
echo "  DMG:  $DMG_PATH"
echo "  URL:  $(gh release view "$VERSION" --json url -q .url 2>/dev/null || echo '见 GitHub Releases 页面')"
echo "================================================="
