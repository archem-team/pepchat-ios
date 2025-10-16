#!/bin/sh



# allow using macros
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Install CocoaPods using Homebrew.
brew install cocoapods

# Install dependencies you manage with CocoaPods.
SKIP_PRE_INSTALL=1 pod install

# resolve packages
cd ..
xcodebuild -resolvePackageDependencies
cd ci_scripts
