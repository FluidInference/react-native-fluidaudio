#pragma once

#include <ReactCommon/TurboModule.h>
#include <react/bridging/Bridging.h>
#include <jsi/jsi.h>
#include <memory>
#include <vector>

namespace facebook::react {

/**
 * JSI Audio Buffer utilities for zero-copy audio processing
 */
class AudioBufferUtils {
public:
    /**
     * Extract raw float samples from a JavaScript ArrayBuffer
     * Zero-copy when possible, copies only when necessary
     */
    static std::vector<float> arrayBufferToFloatSamples(
        jsi::Runtime& runtime,
        const jsi::ArrayBuffer& buffer
    );

    /**
     * Create a JavaScript ArrayBuffer from float samples
     */
    static jsi::ArrayBuffer floatSamplesToArrayBuffer(
        jsi::Runtime& runtime,
        const std::vector<float>& samples
    );

    /**
     * Convert 16-bit PCM data to float samples
     */
    static std::vector<float> pcm16ToFloat(const uint8_t* data, size_t byteLength);

    /**
     * Convert float samples to 16-bit PCM data
     */
    static std::vector<uint8_t> floatToPcm16(const std::vector<float>& samples);
};

} // namespace facebook::react
