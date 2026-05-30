#!/usr/bin/env bash
set -euo pipefail

render_gitignore_global() {
  cat > "${WSK_DIR}/stow/.gitignore_global" <<'EOF'
# macOS
.DS_Store
.AppleDouble
.LSOverride
Icon
._*
.Spotlight-V100
.Trashes
.fseventsd
.VolumeIcon.icns
.com.apple.timemachine.donotpresent

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnp
.pnp.js
.yarn/install-state.gz

# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
*.g.dart
*.freezed.dart

# Android
*.apk
*.ap_
*.aab
local.properties
.gradle/
captures/
.externalNativeBuild/
.cxx/

# iOS
*.ipa
*.dSYM.zip
*.dSYM
Pods/
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
DerivedData/
*.moved-aside

# Expo
.expo/
dist/
web-build/

# Secrets
.env
.env.*
!.env.example
*.pem
*.key
*.p12
*.p8
*.mobileprovision

# Editors
.vscode/
.idea/
*.swp
*.swo
*~

# Claude
.claude/cache/
.claude/telemetry/
.claude/sessions/
EOF
}
