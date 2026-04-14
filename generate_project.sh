#!/bin/bash
# 生成 Xcode 项目
# 使用: swift package generate-xcodeproj 或直接用 Xcode 打开 Package.swift

# 需要创建一个 Info.plist 来隐藏 Dock 图标
cat > NLPlan/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>NL Plan</string>
    <key>CFBundleDisplayName</key>
    <string>NL Plan</string>
    <key>CFBundleIdentifier</key>
    <string>com.nlplan.mac</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

echo "Info.plist created. Open Package.swift in Xcode to build."
