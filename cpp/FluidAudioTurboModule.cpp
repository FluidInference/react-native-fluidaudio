#include "FluidAudioTurboModule.h"
#include <cstdint>
#include <algorithm>
#include <cmath>

namespace facebook::react {

std::vector<float> AudioBufferUtils::arrayBufferToFloatSamples(
    jsi::Runtime& runtime,
    const jsi::ArrayBuffer& buffer
) {
    size_t byteLength = buffer.size(runtime);
    const uint8_t* data = buffer.data(runtime);

    // Assume 16-bit PCM audio (2 bytes per sample)
    return pcm16ToFloat(data, byteLength);
}

jsi::ArrayBuffer AudioBufferUtils::floatSamplesToArrayBuffer(
    jsi::Runtime& runtime,
    const std::vector<float>& samples
) {
    std::vector<uint8_t> pcmData = floatToPcm16(samples);

    // Create ArrayBuffer
    jsi::Function arrayBufferCtor = runtime
        .global()
        .getPropertyAsFunction(runtime, "ArrayBuffer");

    jsi::Object arrayBuffer = arrayBufferCtor
        .callAsConstructor(runtime, static_cast<int>(pcmData.size()))
        .asObject(runtime);

    jsi::ArrayBuffer buffer = arrayBuffer.getArrayBuffer(runtime);

    // Copy data into the ArrayBuffer
    uint8_t* dest = buffer.data(runtime);
    std::memcpy(dest, pcmData.data(), pcmData.size());

    return buffer;
}

std::vector<float> AudioBufferUtils::pcm16ToFloat(const uint8_t* data, size_t byteLength) {
    size_t sampleCount = byteLength / 2;
    std::vector<float> samples(sampleCount);

    const int16_t* pcmData = reinterpret_cast<const int16_t*>(data);

    for (size_t i = 0; i < sampleCount; ++i) {
        // Normalize to -1.0 to 1.0 range
        samples[i] = static_cast<float>(pcmData[i]) / 32768.0f;
    }

    return samples;
}

std::vector<uint8_t> AudioBufferUtils::floatToPcm16(const std::vector<float>& samples) {
    std::vector<uint8_t> pcmData(samples.size() * 2);
    int16_t* dest = reinterpret_cast<int16_t*>(pcmData.data());

    for (size_t i = 0; i < samples.size(); ++i) {
        // Clamp to valid range and convert
        float clamped = std::max(-1.0f, std::min(1.0f, samples[i]));
        dest[i] = static_cast<int16_t>(clamped * 32767.0f);
    }

    return pcmData;
}

} // namespace facebook::react
