#!/bin/sh
# Generate the iOS Xcode project from project.yml and build it for the Simulator.
# macOS is unaffected (SPM: swift build / swift test / build-app.sh). Needs `xcodegen`.
set -e
xcodegen generate
xcodebuild \
  -project MustardMobile.xcodeproj \
  -scheme MustardMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build "$@"
