#!/bin/bash

# GetClawHub 一键发版脚本
# 用法: ./release.sh <版本号>
# 示例: ./release.sh 1.0.3

set -e

# ===== 参数检查 =====
if [ -z "$1" ]; then
    echo "用法: ./release.sh <版本号>"
    echo "示例: ./release.sh 1.0.3"
    exit 1
fi

NEW_VERSION="$1"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$PROJECT_DIR/OpenClawInstaller/Info.plist"
PBXPROJ="$PROJECT_DIR/OpenClawInstaller.xcodeproj/project.pbxproj"

# ===== 前置检查 =====
echo "🔍 前置检查..."

# 检查 gh 是否安装且已登录
if ! command -v gh &>/dev/null; then
    echo "❌ gh (GitHub CLI) 未安装。请先运行: brew install gh && gh auth login"
    exit 1
fi
if ! gh auth status &>/dev/null; then
    echo "❌ gh 未登录。请先运行: gh auth login"
    exit 1
fi

# 检查签名证书
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    echo "❌ 未找到 Developer ID 签名证书。请导入 .p12 证书到 Keychain。"
    exit 1
fi

# 检查公证凭据
if ! xcrun notarytool history --keychain-profile "notary-profile" &>/dev/null; then
    echo "❌ 未配置公证凭据。请先运行:"
    echo "   xcrun notarytool store-credentials \"notary-profile\" --apple-id <你的AppleID> --team-id LJQJ5BHW7G --password <App专用密码>"
    exit 1
fi

# 检查 Sparkle EdDSA 密钥
if ! security find-generic-password -a "ed25519" -s "https://sparkle-project.org" &>/dev/null; then
    echo "❌ 未找到 Sparkle EdDSA 签名密钥。请从另一台电脑导出密钥:"
    echo "   旧电脑: security find-generic-password -a \"ed25519\" -s \"https://sparkle-project.org\" -w"
    echo "   新电脑: security add-generic-password -a \"ed25519\" -s \"https://sparkle-project.org\" -w \"<密钥>\""
    exit 1
fi

echo "✅ 前置检查通过"

# 读取当前版本
OLD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
OLD_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEW_BUILD=$((OLD_BUILD + 1))

echo "====================================="
echo "  GetClawHub 发版"
echo "  $OLD_VERSION (Build $OLD_BUILD) → $NEW_VERSION (Build $NEW_BUILD)"
echo "====================================="
echo ""

# ===== 确认 =====
read -p "确认发版? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# ===== 1. 更新版本号 =====
echo ""
echo "📋 [1/7] 更新版本号..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"
OLD_VERSION_ESCAPED=$(echo "$OLD_VERSION" | sed 's/\./\\./g')
sed -i '' "s/MARKETING_VERSION = ${OLD_VERSION_ESCAPED};/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = $OLD_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"
echo "✅ 版本号已更新: $NEW_VERSION (Build $NEW_BUILD)"

# ===== 2. 输入更新说明 =====
echo ""
echo "📝 [2/7] 请输入更新说明 (直接回车使用默认):"
read -r RELEASE_NOTES
if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="版本 $NEW_VERSION 更新"
fi

# ===== 3. 构建 DMG =====
echo ""
echo "📦 [3/7] 构建 DMG..."
export RELEASE_NOTES
bash "$PROJECT_DIR/build_dmg.sh"

DMG_PATH="$PROJECT_DIR/GetClawHub.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG 构建失败"
    exit 1
fi

# ===== 4. Apple 公证 =====
echo ""
echo "🍎 [4/7] 提交 Apple 公证..."
bash "$PROJECT_DIR/notarize_dmg.sh" "$DMG_PATH"

if [ $? -ne 0 ]; then
    echo "❌ 公证失败，中止发版"
    exit 1
fi

# ===== 5. 重新 EdDSA 签名 (公证 staple 会修改 DMG，必须重签) =====
echo ""
echo "🔏 [5/7] 重新 EdDSA 签名..."
BUILD_DIR="$PROJECT_DIR/build"
SIGN_UPDATE=$(find "$BUILD_DIR" -path "*/artifacts/sparkle/Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)
if [ -z "$SIGN_UPDATE" ] && [ -x "/usr/local/bin/sign_update" ]; then
    SIGN_UPDATE="/usr/local/bin/sign_update"
fi

if [ -n "$SIGN_UPDATE" ]; then
    EDDSA_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1)
    EDDSA_SIGNATURE=$(echo "$EDDSA_OUTPUT" | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')
    if [ -z "$EDDSA_SIGNATURE" ]; then
        EDDSA_SIGNATURE=$(echo "$EDDSA_OUTPUT" | tail -1)
    fi
    echo "✅ EdDSA 签名: ${EDDSA_SIGNATURE:0:20}..."

    # 更新 appcast.xml
    DMG_SIZE=$(stat -f%z "$DMG_PATH")
    DOCS_DIR="$PROJECT_DIR/docs"
    GITHUB_REPO="firewolf189/GetClowhub"
    DMG_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$NEW_VERSION/GetClawHub.dmg"

    cat > "$DOCS_DIR/appcast.xml" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>OpenClaw Helper Updates</title>
    <link>https://firewolf189.github.io/GetClowhub/appcast.xml</link>
    <description>OpenClaw Helper 版本更新</description>
    <language>zh-cn</language>
    <item>
      <title>Version $NEW_VERSION</title>
      <sparkle:version>$NEW_BUILD</sparkle:version>
      <sparkle:shortVersionString>$NEW_VERSION</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>OpenClaw Helper $NEW_VERSION</h2>
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
    echo "✅ appcast.xml 已更新 (签名 + 文件大小)"
else
    echo "❌ 未找到 sign_update 工具，无法签名"
    exit 1
fi

# ===== 6. 提交并推送 (先于 GitHub Release，确保 appcast.xml 更新) =====
echo ""
echo "📤 [6/7] 提交并推送..."
cd "$PROJECT_DIR"
git add docs/appcast.xml \
    OpenClawInstaller/Info.plist \
    OpenClawInstaller.xcodeproj/project.pbxproj
git commit -m "release v$NEW_VERSION: $RELEASE_NOTES"
git push
echo "✅ appcast.xml 已推送，用户可收到更新通知"

# ===== 7. 创建 GitHub Release (失败不阻塞) =====
echo ""
echo "🚀 [7/7] 创建 GitHub Release..."
set +e

# 先创建 release（快）
gh release create "v$NEW_VERSION" \
    --title "v$NEW_VERSION" \
    --notes "$RELEASE_NOTES"
CREATE_OK=$?

if [ $CREATE_OK -eq 0 ]; then
    echo "✅ Release 已创建，开始上传 DMG..."
    # 上传 DMG（慢，带重试）
    for i in 1 2 3; do
        if gh release upload "v$NEW_VERSION" "$DMG_PATH" --clobber; then
            echo "✅ DMG 上传成功"
            break
        fi
        echo "⚠️  DMG 上传失败，重试 ($i/3)..."
        sleep 5
    done
else
    echo "⚠️  GitHub Release 创建失败（网络问题），请手动执行:"
    echo "   gh release create \"v$NEW_VERSION\" GetClawHub.dmg --title \"v$NEW_VERSION\" --notes \"$RELEASE_NOTES\""
fi

set -e

# ===== 清理构建产物，避免 LaunchServices 把 build/ 里的 .app 注册进 Spotlight =====
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
if [ -x "$LSREGISTER" ] && [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -name "GetClawHub.app" -type d -maxdepth 6 2>/dev/null | while read -r app; do
        "$LSREGISTER" -u "$app" 2>/dev/null || true
    done
fi
rm -rf "$BUILD_DIR"

echo ""
echo "====================================="
echo "  🎉 v$NEW_VERSION 发版完成!"
echo ""
echo "  Release: https://github.com/firewolf189/GetClowhub/releases/tag/v$NEW_VERSION"
echo "  appcast: https://firewolf189.github.io/GetClowhub/appcast.xml"
echo "====================================="
