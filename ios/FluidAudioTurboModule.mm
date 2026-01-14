#import "FluidAudioTurboModule.h"
#import <React/RCTBridge+Private.h>
#import <React/RCTUtils.h>
#import <ReactCommon/RCTTurboModule.h>
#import <jsi/jsi.h>

#if __has_include(<react_native_fluidaudio/react_native_fluidaudio-Swift.h>)
#import <react_native_fluidaudio/react_native_fluidaudio-Swift.h>
#else
#import "react_native_fluidaudio-Swift.h"
#endif

#import "../cpp/FluidAudioTurboModule.h"

using namespace facebook;
using namespace facebook::react;

@implementation FluidAudioTurboModule {
    FluidAudioImpl *_impl;
}

RCT_EXPORT_MODULE(FluidAudio)

- (instancetype)init {
    if (self = [super init]) {
        _impl = [[FluidAudioImpl alloc] init];
    }
    return self;
}

- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params {
    return std::make_shared<NativeFluidAudioSpecJSI>(params);
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

#pragma mark - System Info

RCT_EXPORT_METHOD(getSystemInfo:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl getSystemInfoWithResolve:resolve reject:reject];
}

#pragma mark - ASR

RCT_EXPORT_METHOD(initializeAsr:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl initializeAsrWithConfig:config resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(transcribeFile:(NSString *)filePath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl transcribeFileWithFilePath:filePath resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(isAsrAvailable:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl isAsrAvailableWithResolve:resolve reject:reject];
}

#pragma mark - Streaming ASR

RCT_EXPORT_METHOD(startStreamingAsr:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl startStreamingAsrWithConfig:config resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(stopStreamingAsr:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl stopStreamingAsrWithResolve:resolve reject:reject];
}

#pragma mark - VAD

RCT_EXPORT_METHOD(initializeVad:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl initializeVadWithConfig:config resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(processVadFile:(NSString *)filePath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl processVadFileWithFilePath:filePath resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(isVadAvailable:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl isVadAvailableWithResolve:resolve reject:reject];
}

#pragma mark - Diarization

RCT_EXPORT_METHOD(initializeDiarization:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl initializeDiarizationWithConfig:config resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(performDiarizationFile:(NSString *)filePath
                  sampleRate:(double)sampleRate
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl performDiarizationFileWithFilePath:filePath sampleRate:sampleRate resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(initializeKnownSpeakers:(NSArray *)speakers
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl initializeKnownSpeakersWithSpeakers:speakers resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(isDiarizationAvailable:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl isDiarizationAvailableWithResolve:resolve reject:reject];
}

#pragma mark - TTS

RCT_EXPORT_METHOD(initializeTts:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl initializeTtsWithConfig:config resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(synthesizeToFile:(NSString *)text
                  voice:(NSString *)voice
                  outputPath:(NSString *)outputPath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl synthesizeToFileWithText:text voice:voice outputPath:outputPath resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(isTtsAvailable:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl isTtsAvailableWithResolve:resolve reject:reject];
}

#pragma mark - Cleanup

RCT_EXPORT_METHOD(cleanup:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [_impl cleanupWithResolve:resolve reject:reject];
}

#pragma mark - JSI Methods for Zero-Copy Audio

// These methods use JSI for direct ArrayBuffer access
- (void)installJSIBindingsWithRuntime:(jsi::Runtime &)runtime {
    auto transcribeAudioBuffer = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "transcribeAudioBuffer"),
        2, // arguments: audioBuffer, sampleRate
        [self](jsi::Runtime &rt, const jsi::Value &thisVal, const jsi::Value *args, size_t count) -> jsi::Value {
            if (count < 2 || !args[0].isObject()) {
                throw jsi::JSError(rt, "transcribeAudioBuffer requires (ArrayBuffer, sampleRate)");
            }

            jsi::ArrayBuffer buffer = args[0].asObject(rt).getArrayBuffer(rt);
            int sampleRate = static_cast<int>(args[1].asNumber());

            // Convert ArrayBuffer to float samples using zero-copy utilities
            std::vector<float> samples = AudioBufferUtils::arrayBufferToFloatSamples(rt, buffer);

            // Create promise and call Swift implementation
            return createPromiseAsJSIValue(rt, [self, samples = std::move(samples), sampleRate](
                jsi::Runtime &rt,
                std::shared_ptr<Promise> promise
            ) {
                NSData *audioData = [NSData dataWithBytes:samples.data()
                                                  length:samples.size() * sizeof(float)];

                [_impl transcribeAudioDataWithData:audioData
                                        sampleRate:sampleRate
                                          resolve:^(id result) {
                    promise->resolve(convertNSDictionaryToJSI(rt, result));
                }
                                           reject:^(NSString *code, NSString *message, NSError *error) {
                    promise->reject(std::string([message UTF8String]));
                }];
            });
        }
    );

    runtime.global().setProperty(runtime, "FluidAudio_transcribeAudioBuffer", std::move(transcribeAudioBuffer));

    auto feedStreamingAudioBuffer = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "feedStreamingAudioBuffer"),
        1, // arguments: audioBuffer
        [self](jsi::Runtime &rt, const jsi::Value &thisVal, const jsi::Value *args, size_t count) -> jsi::Value {
            if (count < 1 || !args[0].isObject()) {
                throw jsi::JSError(rt, "feedStreamingAudioBuffer requires (ArrayBuffer)");
            }

            jsi::ArrayBuffer buffer = args[0].asObject(rt).getArrayBuffer(rt);
            std::vector<float> samples = AudioBufferUtils::arrayBufferToFloatSamples(rt, buffer);

            NSData *audioData = [NSData dataWithBytes:samples.data()
                                              length:samples.size() * sizeof(float)];

            [_impl feedStreamingAudioWithData:audioData];

            return jsi::Value::undefined();
        }
    );

    runtime.global().setProperty(runtime, "FluidAudio_feedStreamingAudioBuffer", std::move(feedStreamingAudioBuffer));

    auto processVadBuffer = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "processVadBuffer"),
        1, // arguments: audioBuffer
        [self](jsi::Runtime &rt, const jsi::Value &thisVal, const jsi::Value *args, size_t count) -> jsi::Value {
            if (count < 1 || !args[0].isObject()) {
                throw jsi::JSError(rt, "processVadBuffer requires (ArrayBuffer)");
            }

            jsi::ArrayBuffer buffer = args[0].asObject(rt).getArrayBuffer(rt);
            std::vector<float> samples = AudioBufferUtils::arrayBufferToFloatSamples(rt, buffer);

            return createPromiseAsJSIValue(rt, [self, samples = std::move(samples)](
                jsi::Runtime &rt,
                std::shared_ptr<Promise> promise
            ) {
                NSData *audioData = [NSData dataWithBytes:samples.data()
                                                  length:samples.size() * sizeof(float)];

                [_impl processVadAudioDataWithData:audioData
                                          resolve:^(id result) {
                    promise->resolve(convertNSDictionaryToJSI(rt, result));
                }
                                           reject:^(NSString *code, NSString *message, NSError *error) {
                    promise->reject(std::string([message UTF8String]));
                }];
            });
        }
    );

    runtime.global().setProperty(runtime, "FluidAudio_processVadBuffer", std::move(processVadBuffer));

    auto performDiarizationBuffer = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "performDiarizationBuffer"),
        2, // arguments: audioBuffer, sampleRate
        [self](jsi::Runtime &rt, const jsi::Value &thisVal, const jsi::Value *args, size_t count) -> jsi::Value {
            if (count < 2 || !args[0].isObject()) {
                throw jsi::JSError(rt, "performDiarizationBuffer requires (ArrayBuffer, sampleRate)");
            }

            jsi::ArrayBuffer buffer = args[0].asObject(rt).getArrayBuffer(rt);
            int sampleRate = static_cast<int>(args[1].asNumber());
            std::vector<float> samples = AudioBufferUtils::arrayBufferToFloatSamples(rt, buffer);

            return createPromiseAsJSIValue(rt, [self, samples = std::move(samples), sampleRate](
                jsi::Runtime &rt,
                std::shared_ptr<Promise> promise
            ) {
                NSData *audioData = [NSData dataWithBytes:samples.data()
                                                  length:samples.size() * sizeof(float)];

                [_impl performDiarizationAudioDataWithData:audioData
                                                sampleRate:sampleRate
                                                  resolve:^(id result) {
                    promise->resolve(convertNSDictionaryToJSI(rt, result));
                }
                                                   reject:^(NSString *code, NSString *message, NSError *error) {
                    promise->reject(std::string([message UTF8String]));
                }];
            });
        }
    );

    runtime.global().setProperty(runtime, "FluidAudio_performDiarizationBuffer", std::move(performDiarizationBuffer));

    auto synthesize = jsi::Function::createFromHostFunction(
        runtime,
        jsi::PropNameID::forAscii(runtime, "synthesize"),
        2, // arguments: text, voice
        [self](jsi::Runtime &rt, const jsi::Value &thisVal, const jsi::Value *args, size_t count) -> jsi::Value {
            if (count < 1 || !args[0].isString()) {
                throw jsi::JSError(rt, "synthesize requires (text, voice?)");
            }

            std::string text = args[0].asString(rt).utf8(rt);
            NSString *voice = nil;
            if (count > 1 && args[1].isString()) {
                voice = [NSString stringWithUTF8String:args[1].asString(rt).utf8(rt).c_str()];
            }

            return createPromiseAsJSIValue(rt, [self, text, voice](
                jsi::Runtime &rt,
                std::shared_ptr<Promise> promise
            ) {
                [_impl synthesizeWithText:[NSString stringWithUTF8String:text.c_str()]
                                    voice:voice
                                  resolve:^(NSDictionary *result) {
                    // Convert audio samples to ArrayBuffer
                    NSData *audioData = result[@"audioData"];
                    if (audioData) {
                        size_t byteLength = audioData.length;
                        jsi::Function arrayBufferCtor = rt.global().getPropertyAsFunction(rt, "ArrayBuffer");
                        jsi::Object arrayBuffer = arrayBufferCtor.callAsConstructor(rt, static_cast<int>(byteLength)).asObject(rt);
                        jsi::ArrayBuffer buffer = arrayBuffer.getArrayBuffer(rt);
                        memcpy(buffer.data(rt), audioData.bytes, byteLength);

                        jsi::Object jsResult(rt);
                        jsResult.setProperty(rt, "audioBuffer", std::move(arrayBuffer));
                        jsResult.setProperty(rt, "duration", [result[@"duration"] doubleValue]);
                        jsResult.setProperty(rt, "sampleRate", [result[@"sampleRate"] intValue]);

                        promise->resolve(std::move(jsResult));
                    } else {
                        promise->reject("TTS synthesis returned no audio data");
                    }
                }
                                   reject:^(NSString *code, NSString *message, NSError *error) {
                    promise->reject(std::string([message UTF8String]));
                }];
            });
        }
    );

    runtime.global().setProperty(runtime, "FluidAudio_synthesize", std::move(synthesize));
}

#pragma mark - Helper Functions

static jsi::Value convertNSDictionaryToJSI(jsi::Runtime &rt, NSDictionary *dict) {
    jsi::Object obj(rt);
    for (NSString *key in dict) {
        id value = dict[key];
        if ([value isKindOfClass:[NSString class]]) {
            obj.setProperty(rt, [key UTF8String], jsi::String::createFromUtf8(rt, [value UTF8String]));
        } else if ([value isKindOfClass:[NSNumber class]]) {
            obj.setProperty(rt, [key UTF8String], [value doubleValue]);
        } else if ([value isKindOfClass:[NSArray class]]) {
            obj.setProperty(rt, [key UTF8String], convertNSArrayToJSI(rt, value));
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            obj.setProperty(rt, [key UTF8String], convertNSDictionaryToJSI(rt, value));
        }
    }
    return obj;
}

static jsi::Value convertNSArrayToJSI(jsi::Runtime &rt, NSArray *array) {
    jsi::Array arr(rt, array.count);
    for (NSUInteger i = 0; i < array.count; i++) {
        id value = array[i];
        if ([value isKindOfClass:[NSString class]]) {
            arr.setValueAtIndex(rt, i, jsi::String::createFromUtf8(rt, [value UTF8String]));
        } else if ([value isKindOfClass:[NSNumber class]]) {
            arr.setValueAtIndex(rt, i, [value doubleValue]);
        } else if ([value isKindOfClass:[NSArray class]]) {
            arr.setValueAtIndex(rt, i, convertNSArrayToJSI(rt, value));
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            arr.setValueAtIndex(rt, i, convertNSDictionaryToJSI(rt, value));
        }
    }
    return arr;
}

@end
