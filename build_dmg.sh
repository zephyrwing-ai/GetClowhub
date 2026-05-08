#!/bin/bash

# GetClawHub DMG 构建脚本
# 构建、签名、打包 DMG（不含公证，公证请用 notarize_dmg.sh）

set -e

# 默认需要登录，始终构建 universal (arm64 + x86_64)
LOGIN_MODE="REQUIRE_LOGIN"
SKIP_SIGN=""
for arg in "$@"; do
    case "$arg" in
        --no-login)  LOGIN_MODE="" ;;
        --debug)     SKIP_SIGN="1" ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="OpenClawInstaller"
APP_NAME="GetClawHub.app"
BUILD_DIR="$PROJECT_DIR/build"
DMG_NAME="GetClawHub.dmg"
GITHUB_REPO="firewolf189/GetClowhub"
DOCS_DIR="$PROJECT_DIR/docs"

# ===== Developer ID 签名配置 =====
SIGN_IDENTITY="Developer ID Application: Zhejiang Hecheng Smart Electric Co., Ltd. (LJQJ5BHW7G)"
TEAM_ID="LJQJ5BHW7G"

echo "🚀 开始构建 GetClawHub (universal: arm64 + x86_64)..."

# 清理旧的构建
if [ -d "$BUILD_DIR" ]; then
    echo "🧹 清理旧的构建文件..."
    rm -rf "$BUILD_DIR"
fi

# 构建项目
echo "🔨 构建项目..."
EXTRA_FLAGS=""
if [ -n "$LOGIN_MODE" ]; then
    echo "   登录版构建（需要登录）"
else
    EXTRA_FLAGS='SWIFT_ACTIVE_COMPILATION_CONDITIONS='
    echo "   免登录版构建（--no-login）"
fi

xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -sdk macosx \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    $EXTRA_FLAGS \
    clean build

# 查找生成的 .app 文件
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 错误: 找不到构建的 .app 文件"
    exit 1
fi

echo "✅ 应用构建成功: $APP_PATH"

# 将 Node.js 资源复制到 app bundle 中
echo "📦 添加 Node.js 资源到应用包..."
RESOURCES_SRC="$PROJECT_DIR/OpenClawInstaller/Resources"
RESOURCES_DEST="$APP_PATH/Contents/Resources"

# ===== Preflight: 必需的 bundled 资源 =====
# 这些 .tar.gz 被 .gitignore 屏蔽 (因 GitHub 100MB 单文件限制)，必须手动放置。
# 缺失时 OpenClawInstaller.swift 会抛 bundleNotFound，用户安装直接卡死，
# 所以这里 fail-fast，绝不静默打出空壳 DMG (参见 v1.1.38 事故)。
REQUIRED_BUNDLES=(
    "openclaw-bundle.tar.gz"
    "node-v24.14.0-darwin-arm64.tar.gz"
    "node-v24.14.0-darwin-x64.tar.gz"
)
echo "🔍 校验必需的 bundled 资源..."
MISSING=()
for f in "${REQUIRED_BUNDLES[@]}"; do
    p="$RESOURCES_SRC/$f"
    if [ ! -f "$p" ]; then
        MISSING+=("$f (缺失)")
    elif [ "$(stat -f%z "$p" 2>/dev/null || echo 0)" -lt 1048576 ]; then
        MISSING+=("$f (<1MB，疑似空文件)")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ 必需的 bundled 资源缺失或损坏:"
    for m in "${MISSING[@]}"; do echo "   - $m"; done
    echo ""
    echo "这些文件被 .gitignore 屏蔽，必须先放入 OpenClawInstaller/Resources/"
    echo "openclaw-bundle.tar.gz 重建方式 (从已全局安装的 openclaw npm 包):"
    echo "   cd ~/.npm-global && tar -czf openclaw-bundle.tar.gz bin/openclaw lib/node_modules/openclaw"
    echo "Node.js tarball 下载:"
    echo "   https://registry.npmmirror.com/-/binary/node/v24.14.0/"
    exit 1
fi
echo "✅ Preflight 通过 (${#REQUIRED_BUNDLES[@]} 个必需 bundle 就位)"

if [ -d "$RESOURCES_SRC" ]; then
    cp -R "$RESOURCES_SRC/"* "$RESOURCES_DEST/"
    echo "   Universal 构建，保留全部 Node.js 包"

    echo "✅ Node.js 资源已添加"

    echo "📋 已添加的资源:"
    ls -lh "$RESOURCES_DEST"/*.tar.gz 2>/dev/null || echo "   (无 .tar.gz 文件)"

    # ===== 签名 tar.gz 内的原生二进制文件 =====
    if [ -n "$SKIP_SIGN" ]; then
        echo "⏩ --debug 模式，跳过 tar.gz 内二进制签名"
    else
    echo "🔏 开始签名 tar.gz 内的原生二进制文件..."
    echo "   资源目录: $RESOURCES_DEST"

    # Node.js / V8 可执行文件需要 JIT 权限，否则 Hardened Runtime 会阻止 V8 分配可执行内存
    NODE_ENTITLEMENTS="$PROJECT_DIR/node-entitlements.plist"
    if [ ! -f "$NODE_ENTITLEMENTS" ]; then
        echo "   ❌ 找不到 node-entitlements.plist: $NODE_ENTITLEMENTS"
        exit 1
    fi
    echo "   使用 entitlements: $NODE_ENTITLEMENTS"

    # 带重试的签名函数（Apple 时间戳服务器偶尔不可用）
    codesign_retry() {
        local max_retries=5
        local retry_delay=10
        for i in $(seq 1 $max_retries); do
            if codesign "$@" 2>/dev/null; then
                return 0
            fi
            if [ $i -lt $max_retries ]; then
                echo "   ⏳ 时间戳服务不可用，${retry_delay}秒后重试 ($i/$max_retries)..."
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))
            fi
        done
        return 1
    }

    TARGZ_LIST=$(find "$RESOURCES_DEST" -maxdepth 1 -name "*.tar.gz" -type f 2>/dev/null)
    if [ -z "$TARGZ_LIST" ]; then
        echo "   ⚠️ 未找到 tar.gz 文件"
    else
        # 使用 here-string 而非管道，避免子 shell 导致签名结果丢失
        while IFS= read -r TARGZ; do
            TARGZ_NAME=$(basename "$TARGZ")
            echo "   📦 处理 $TARGZ_NAME ..."

            # 解压到临时目录
            SIGN_TMP=$(mktemp -d "${TMPDIR}sign_natives.XXXXXX")
            tar xzf "$TARGZ" -C "$SIGN_TMP" || { echo "   ✗ 解压失败"; rm -rf "$SIGN_TMP"; continue; }

            # 使用 file 命令检测所有 Mach-O 二进制（比按扩展名匹配更可靠）
            SIGN_COUNT=0
            FAIL_COUNT=0
            while IFS= read -r bin; do
                [ -z "$bin" ] && continue
                FILE_INFO=$(file "$bin")
                if echo "$FILE_INFO" | grep -q "Mach-O"; then
                    # Mach-O 可执行文件需要 JIT entitlements（V8/Node.js 需要）
                    # 动态库和 bundle 不需要 entitlements（继承宿主进程的权限）
                    if echo "$FILE_INFO" | grep -q "executable"; then
                        if codesign_retry --force --options runtime --timestamp --entitlements "$NODE_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$bin"; then
                            echo "   ✓ $(basename "$bin") (executable + entitlements)"
                            SIGN_COUNT=$((SIGN_COUNT + 1))
                        else
                            echo "   ✗ $(basename "$bin") (签名失败)"
                            FAIL_COUNT=$((FAIL_COUNT + 1))
                        fi
                    else
                        if codesign_retry --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$bin"; then
                            echo "   ✓ $(basename "$bin")"
                            SIGN_COUNT=$((SIGN_COUNT + 1))
                        else
                            echo "   ✗ $(basename "$bin") (签名失败)"
                            FAIL_COUNT=$((FAIL_COUNT + 1))
                        fi
                    fi
                fi
            done < <(find "$SIGN_TMP" -type f)

            echo "   签名统计: 成功 $SIGN_COUNT, 失败 $FAIL_COUNT"

            if [ "$FAIL_COUNT" -gt 0 ]; then
                echo "   ❌ 存在签名失败的文件，终止构建"
                rm -rf "$SIGN_TMP"
                exit 1
            fi

            # 重新打包
            echo "   重新打包 $TARGZ_NAME..."
            (cd "$SIGN_TMP" && tar czf "$TARGZ" *)
            echo "   ✅ $TARGZ_NAME 完成"

            rm -rf "$SIGN_TMP"
        done <<< "$TARGZ_LIST"
    fi
    fi # SKIP_SIGN
else
    echo "⚠️  警告: Resources 目录不存在，跳过资源复制"
fi

# ===== Developer ID 签名 =====
if [ -n "$SKIP_SIGN" ]; then
    echo "⏩ --debug 模式，跳过 Developer ID 签名和验证"
else
echo "🔐 使用 Developer ID 证书签名..."

# 带重试的签名函数（Apple 时间戳服务器偶尔不可用）
codesign_with_retry() {
    local max_retries=5
    local retry_delay=10
    for i in $(seq 1 $max_retries); do
        if codesign "$@" 2>&1; then
            return 0
        fi
        if [ $i -lt $max_retries ]; then
            echo "   ⏳ 时间戳服务不可用，${retry_delay}秒后重试 ($i/$max_retries)..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        fi
    done
    echo "   ❌ 签名失败，已重试 $max_retries 次"
    return 1
}

# 签名所有 Frameworks 和动态库
while IFS= read -r fw; do
    codesign_with_retry --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$fw" || true
done < <(find "$APP_PATH/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null)

# 签名 Frameworks 目录下的子 bundle
while IFS= read -r fw; do
    codesign_with_retry --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$fw" || true
done < <(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null)

# 签名主 app (--deep 确保递归签名所有内容, --options runtime 启用 Hardened Runtime)
APP_ENTITLEMENTS="$PROJECT_DIR/app-entitlements.plist"
codesign_with_retry --force --deep --options runtime --timestamp --entitlements "$APP_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_PATH"
echo "✅ Developer ID 签名完成"

# 验证签名
echo "🔍 验证签名..."
codesign --verify --deep --strict "$APP_PATH" 2>&1
echo "✅ 签名验证通过"
fi # SKIP_SIGN

# 创建 DMG
echo "📦 创建 DMG 安装包..."

# 卸载可能已挂载的 DMG
echo "🔄 卸载已挂载的 DMG..."
hdiutil detach "/Volumes/$PROJECT_NAME" 2>/dev/null || true
for vol in /Volumes/*OpenClaw* /Volumes/GetClawHub*; do
    [ -d "$vol" ] && hdiutil detach "$vol" -force 2>/dev/null || true
done

# 删除旧的 DMG
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

# 使用用户私有临时目录
TMP_DMG_DIR=$(mktemp -d "${TMPDIR}openclaw_dmg.XXXXXX")

cleanup() { rm -rf "$TMP_DMG_DIR"; }
trap cleanup EXIT

# 复制 .app 到临时目录
cp -R "$APP_PATH" "$TMP_DMG_DIR/"

# ===== 确保 DesignSystems 目录被正确复制 =====
# 这是修复 awesome-design-system agent 招募时无法找到 DesignSystems 的关键步骤
echo "📚 确保 DesignSystems 目录被复制..."
DESIGN_SRC="$APP_PATH/Contents/Resources/DesignSystems"
DESIGN_DST="$TMP_DMG_DIR/GetClawHub.app/Contents/Resources/DesignSystems"

if [ -d "$DESIGN_SRC" ]; then
    # 删除可能不完整的副本
    rm -rf "$DESIGN_DST" 2>/dev/null || true
    # 强制复制以确保完整性
    cp -R "$DESIGN_SRC" "$DESIGN_DST" 2>&1
    if [ -d "$DESIGN_DST" ]; then
        DESIGN_COUNT=$(find "$DESIGN_DST" -maxdepth 1 -type d | wc -l)
        echo "✅ DesignSystems 已复制到 DMG ($((DESIGN_COUNT - 1)) 个设计系统)"
    else
        echo "⚠️  警告: DesignSystems 复制失败"
    fi
else
    echo "⚠️  警告: Release build 中找不到 DesignSystems，跳过复制"
fi

# 移除隔离属性
echo "🔓 移除隔离属性..."
xattr -cr "$TMP_DMG_DIR/GetClawHub.app" 2>/dev/null || true

# 复制 README
README_FILE="$PROJECT_DIR/README.md"
if [ -f "$README_FILE" ]; then
    cp "$README_FILE" "$TMP_DMG_DIR/"
    echo "📄 已添加 README.md"
fi

# 创建 Applications 符号链接
ln -s /Applications "$TMP_DMG_DIR/Applications"

# 禁止 Spotlight 索引
touch "$TMP_DMG_DIR/.metadata_never_index"
sleep 1

# 生成 DMG（带重试）
echo "📦 正在打包 DMG..."
TMP_DMG="${TMP_DMG_DIR}.dmg"
rm -f "$TMP_DMG"

# Volname 用 "GetClawHub Installer" 而非 "GetClawHub":
# 当用户机器上 /Applications/GetClawHub.app 已经存在时,macOS 会把新 DMG 卷里
# 同路径(/Volumes/GetClawHub/GetClawHub.app)的写入视为"应用伪造",触发 TCC
# Operation not permitted。换个卷名既能避开冲突,挂载时显示也更清晰。
for i in 1 2 3; do
    if hdiutil create -volname "GetClawHub Installer" \
        -srcfolder "$TMP_DMG_DIR" \
        -format UDZO \
        "$TMP_DMG"; then
        break
    fi
    echo "⏳ DMG 创建失败，等待重试 ($i/3)..."
    rm -f "$TMP_DMG"
    sleep 5
done

if [ ! -f "$TMP_DMG" ]; then
    echo "❌ DMG 创建失败"
    exit 1
fi

mv "$TMP_DMG" "$DMG_PATH"
echo "✨ DMG 创建成功: $DMG_PATH"

# ===== Sparkle 自动更新: EdDSA 签名 + appcast.xml 生成 =====

# 从 Xcode 项目读取版本号
MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/$PROJECT_NAME/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/$PROJECT_NAME/Info.plist")
echo "📋 版本: $MARKETING_VERSION (Build $BUILD_NUMBER)"

# 查找 Sparkle 的 sign_update 工具
SIGN_UPDATE=""
SPM_SIGN=$(find "$BUILD_DIR" -name "sign_update" -type f 2>/dev/null | head -1)
if [ -n "$SPM_SIGN" ] && [ -x "$SPM_SIGN" ]; then
    SIGN_UPDATE="$SPM_SIGN"
fi
if [ -z "$SIGN_UPDATE" ] && [ -x "/usr/local/bin/sign_update" ]; then
    SIGN_UPDATE="/usr/local/bin/sign_update"
fi

if [ -n "$SKIP_SIGN" ]; then
    echo "⏩ --debug 模式，跳过 EdDSA 签名"
    EDDSA_SIGNATURE="DEBUG_BUILD"
elif [ -n "$SIGN_UPDATE" ]; then
    echo "🔏 对 DMG 进行 EdDSA 签名..."
    EDDSA_SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1 | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')

    if [ -z "$EDDSA_SIGNATURE" ]; then
        EDDSA_SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1 | tail -1)
    fi
    echo "✅ EdDSA 签名完成"
else
    echo "⚠️  未找到 sign_update 工具，跳过 EdDSA 签名"
    EDDSA_SIGNATURE="SIGNATURE_PLACEHOLDER"
fi

# 获取 DMG 文件大小
DMG_SIZE=$(stat -f%z "$DMG_PATH")
DMG_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$MARKETING_VERSION/$DMG_NAME"

# 生成 appcast.xml
echo "📝 生成 appcast.xml..."
mkdir -p "$DOCS_DIR"

cat > "$DOCS_DIR/appcast.xml" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>OpenClaw Helper Updates</title>
    <link>https://firewolf189.github.io/GetClowhub/appcast.xml</link>
    <description>OpenClaw Helper 版本更新</description>
    <language>zh-cn</language>
    <item>
      <title>Version $MARKETING_VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>OpenClaw Helper $MARKETING_VERSION</h2>
        <ul>
          <li>${RELEASE_NOTES:-版本更新}</li>
        </ul>
      ]]></description>
      <pubDate>$(date -R)</pubDate>
      <enclosure url="$DMG_DOWNLOAD_URL"
                 length="$DMG_SIZE"
                 type="application/octet-stream"
                 sparkle:edSignature="$EDDSA_SIGNATURE" />
    </item>
  </channel>
</rss>
APPCAST_EOF

echo "✅ appcast.xml 已生成: $DOCS_DIR/appcast.xml"
echo ""
echo "🎉 构建完成！DMG 路径: $DMG_PATH"
echo ""
echo "===== 下一步 ====="
echo "1. 公证: bash notarize_dmg.sh"
echo "2. 发版: gh release create v$MARKETING_VERSION \"$DMG_PATH\" --title \"v$MARKETING_VERSION\" --notes \"版本更新\""
echo "3. 推送: git add docs/appcast.xml && git commit -m \"update appcast v$MARKETING_VERSION\" && git push"
echo "===================="
