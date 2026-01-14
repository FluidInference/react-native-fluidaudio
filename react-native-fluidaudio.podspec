require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

# Check if New Architecture is enabled
folly_compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -Wno-comma -Wno-shorten-64-to-32'

Pod::Spec.new do |s|
  s.name         = "react-native-fluidaudio"
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = package['homepage']
  s.license      = package['license']
  s.authors      = package['author']

  s.platforms    = { :ios => "17.0" }
  s.source       = { :git => package['repository']['url'], :tag => "#{s.version}" }

  s.swift_version = "5.10"

  # React Native dependencies
  s.dependency "React-Core"

  # FluidAudio dependency (fetched from GitHub)
  s.dependency "FluidAudio", "~> 0.7"

  # Source files - supports both Old and New Architecture
  s.source_files = [
    "ios/**/*.{h,m,mm,swift}",
    "cpp/**/*.{h,hpp,cpp}"
  ]

  s.ios.frameworks = "CoreML", "AVFoundation", "Accelerate", "UIKit"

  # Compiler flags for both architectures
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'ARCHS[sdk=iphoneos*]' => 'arm64'
  }

  # New Architecture (TurboModules + Codegen)
  if ENV['RCT_NEW_ARCH_ENABLED'] == '1'
    s.compiler_flags = folly_compiler_flags + " -DRCT_NEW_ARCH_ENABLED=1"
    s.pod_target_xcconfig['HEADER_SEARCH_PATHS'] = '"$(PODS_ROOT)/boost" "$(PODS_ROOT)/RCT-Folly" "$(PODS_ROOT)/Headers/Private/React-Core"'
    s.pod_target_xcconfig['OTHER_CPLUSPLUSFLAGS'] = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1'

    s.dependency "React-Codegen"
    s.dependency "RCT-Folly"
    s.dependency "RCTRequired"
    s.dependency "RCTTypeSafety"
    s.dependency "ReactCommon/turbomodule/core"
  end
end
