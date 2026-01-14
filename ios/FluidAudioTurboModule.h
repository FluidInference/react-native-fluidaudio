#pragma once

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <ReactCommon/RCTTurboModule.h>
#import <FluidAudioSpec/FluidAudioSpec.h>
#endif

NS_ASSUME_NONNULL_BEGIN

#ifdef RCT_NEW_ARCH_ENABLED
@interface FluidAudioTurboModule : RCTEventEmitter <RCTBridgeModule, RCTTurboModule, NativeFluidAudioSpec>
#else
@interface FluidAudioTurboModule : RCTEventEmitter <RCTBridgeModule>
#endif

@end

NS_ASSUME_NONNULL_END
