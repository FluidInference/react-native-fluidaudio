require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

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

  # FluidAudio comes from GitHub through Swift Package Manager: CocoaPods trunk stops at
  # FluidAudio 0.7.8 and goes read-only on December 2, 2026. `spm_dependency` is React
  # Native's podspec helper (0.75+), defined once the Podfile loads react_native_pods.rb.
  unless defined?(spm_dependency)
    raise "react-native-fluidaudio needs React Native 0.75 or newer (for spm_dependency)."
  end
  spm_dependency(s,
    url: "https://github.com/FluidInference/FluidAudio.git",
    requirement: { kind: "upToNextMinorVersion", minimumVersion: "0.17.7" },
    products: ["FluidAudio"]
  )

  s.ios.frameworks = "CoreML", "AVFoundation", "Accelerate", "UIKit"

  # Source files - Legacy Bridge architecture only
  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'ARCHS[sdk=iphoneos*]' => 'arm64'
  }
end
