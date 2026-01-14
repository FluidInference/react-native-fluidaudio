#pragma once

#include <memory>
#include <string>

#ifdef __APPLE__
#include <TargetConditionals.h>
#if TARGET_OS_IOS
#define FLUIDAUDIO_IOS 1
#endif
#endif

namespace facebook::react {
class CallInvoker;
}

namespace fluidaudio {

// Forward declaration for platform-specific implementation
class FluidAudioHostObject;

/**
 * FluidAudioModule - JSI module for zero-copy audio processing
 *
 * This module provides direct memory access to audio buffers,
 * eliminating the base64 serialization overhead of the legacy bridge.
 */
class FluidAudioModule {
public:
    FluidAudioModule(
        std::shared_ptr<facebook::react::CallInvoker> jsInvoker
    );
    ~FluidAudioModule();

    // Install the JSI bindings into the JS runtime
    static void install(
        jsi::Runtime& runtime,
        std::shared_ptr<facebook::react::CallInvoker> jsInvoker
    );

private:
    std::shared_ptr<facebook::react::CallInvoker> jsInvoker_;
};

} // namespace fluidaudio
