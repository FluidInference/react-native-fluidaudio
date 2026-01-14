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

  # C++ wrapper subspec (from FluidAudio)
  s.subspec "FastClusterWrapper" do |wrapper|
    wrapper.requires_arc = false
    wrapper.source_files = "FluidAudio/Sources/FastClusterWrapper/**/*.{cpp,h,hpp}"
    wrapper.public_header_files = "FluidAudio/Sources/FastClusterWrapper/include/FastClusterWrapper.h"
    wrapper.private_header_files = "FluidAudio/Sources/FastClusterWrapper/fastcluster_internal.hpp"
    wrapper.header_mappings_dir = "FluidAudio/Sources/FastClusterWrapper"
    wrapper.pod_target_xcconfig = {
      'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17'
    }
  end

  # Mach task wrapper subspec (from FluidAudio)
  s.subspec "MachTaskSelfWrapper" do |mach|
    mach.source_files = "FluidAudio/Sources/MachTaskSelfWrapper/**/*.{c,h}"
    mach.public_header_files = "FluidAudio/Sources/MachTaskSelfWrapper/include/MachTaskSelf.h"
    mach.header_mappings_dir = "FluidAudio/Sources/MachTaskSelfWrapper"
    mach.module_map = "FluidAudio/Sources/MachTaskSelfWrapper/include/module.modulemap"
  end

  # Core module (FluidAudio + React Native bridge)
  s.subspec "Core" do |core|
    core.dependency "#{s.name}/FastClusterWrapper"
    core.dependency "#{s.name}/MachTaskSelfWrapper"

    # FluidAudio Swift sources
    core.source_files = [
      "FluidAudio/Sources/FluidAudio/**/*.swift",
      "ios/**/*.{h,m,mm,swift}"
    ]

    core.ios.frameworks = "CoreML", "AVFoundation", "Accelerate", "UIKit"
  end

  s.default_subspecs = ["Core"]

  # Compiler flags
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'ARCHS[sdk=iphoneos*]' => 'arm64'
  }
end
