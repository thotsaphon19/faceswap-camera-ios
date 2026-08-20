#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FaceSwap Cam"
BUNDLE_ORG="com.example"
IOS_TARGET="15.0"

echo "==> Force CocoaPods mode for this CI build"
flutter config --no-enable-swift-package-manager || true

echo "==> Recreate a complete iOS Flutter scaffold"
rm -rf ios
flutter create --platforms=ios --org "$BUNDLE_ORG" --project-name faceswap_camera .

if [ ! -f ios/Podfile ]; then
  echo "==> ios/Podfile missing; creating CocoaPods Podfile"
  cat > ios/Podfile <<'PODFILE'
platform :ios, '15.0'

ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. Run flutter pub get first."
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}."
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_MICROPHONE=1',
        'PERMISSION_PHOTOS=1',
      ]
    end
  end
end
PODFILE
fi

python3 - <<'PY'
from pathlib import Path
import re
p = Path('ios/Podfile')
s = p.read_text()
if re.search(r"#?\s*platform :ios, ['\"]\d+(?:\.\d+)?['\"]", s):
    s = re.sub(r"#?\s*platform :ios, ['\"]\d+(?:\.\d+)?['\"]", "platform :ios, '15.0'", s, count=1)
else:
    s = "platform :ios, '15.0'\n" + s
p.write_text(s)
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$APP_NAME'" ios/Runner/Info.plist

/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string FaceSwap Cam uses the camera for real-time video and face swap." ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription FaceSwap Cam uses the camera for real-time video and face swap." ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string FaceSwap Cam uses the microphone for audio during video calls." ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription FaceSwap Cam uses the microphone for audio during video calls." ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string FaceSwap Cam uses your photo library so you can choose a source face image." ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Set :NSPhotoLibraryUsageDescription FaceSwap Cam uses your photo library so you can choose a source face image." ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string FaceSwap Cam may save generated images to your photo library when requested." ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Set :NSPhotoLibraryAddUsageDescription FaceSwap Cam may save generated images to your photo library when requested." ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string FaceSwap Cam uses the local network to connect to your FaceSwap server." ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Set :NSLocalNetworkUsageDescription FaceSwap Cam uses the local network to connect to your FaceSwap server." ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" ios/Runner/Info.plist || true
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" ios/Runner/Info.plist || \
/usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsArbitraryLoads true" ios/Runner/Info.plist

echo "==> Ensure permission_handler compile-time macros"
python3 - <<'PY'
from pathlib import Path
p = Path('ios/Podfile')
s = p.read_text()
if 'PERMISSION_CAMERA=1' not in s:
    needle = "    flutter_additional_ios_build_settings(target)"
    insert = """    flutter_additional_ios_build_settings(target)\n\n    target.build_configurations.each do |config|\n      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'\n      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [\n        '$(inherited)',\n        'PERMISSION_CAMERA=1',\n        'PERMISSION_MICROPHONE=1',\n        'PERMISSION_PHOTOS=1',\n      ]\n    end"""
    if needle not in s:
        raise SystemExit('Could not locate flutter_additional_ios_build_settings(target) in Podfile')
    s = s.replace(needle, insert, 1)
    p.write_text(s)
PY

python3 - <<'PY'
from pathlib import Path
import re
p = Path('ios/Runner.xcodeproj/project.pbxproj')
s = p.read_text()
s = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', s)
p.write_text(s)
PY

echo "==> iOS configuration prepared"
test -f ios/Podfile
/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Print :NSPhotoLibraryUsageDescription" ios/Runner/Info.plist
