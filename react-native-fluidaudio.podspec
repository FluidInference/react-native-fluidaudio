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

  # React Native bridge
  s.dependency "React-Core"

  # FluidAudio dependency (fetched from GitHub)
  s.dependency "FluidAudio", "~> 0.7"

  # React Native bridge source files only
  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.ios.frameworks = "CoreML", "AVFoundation", "Accelerate", "UIKit"

  # Compiler flags
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'ARCHS[sdk=iphoneos*]' => 'arm64'
  }
end
