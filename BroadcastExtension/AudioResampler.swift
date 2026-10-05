import AVFoundation
import Accelerate
import CoreMedia

/// Converts ReplayKit audio CMSampleBuffers into mono Int16 @ 16 kHz.
///
/// Strategy: pull the AudioBufferList → downmix to float mono at the source
/// rate → linear-interpolate to 16 kHz → clamp to Int16.
final class AudioResampler {
    private let targetRate: Double

    init(targetSampleRate: Double = AudioConstants.sampleRate) {
        self.targetRate = targetSampleRate
    }

    func resample(_ sampleBuffer: CMSampleBuffer) -> [Int16]? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPtr.pointee
        let sourceRate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, channels > 0, sourceRate > 0 else { return nil }

        guard let monoFloat = extractMonoFloat(from: sampleBuffer, asbd: asbd,
                                               frames: frameCount, channels: channels) else {
            return nil
        }

        let resampled: [Float]
        if abs(sourceRate - targetRate) < 0.5 {
            resampled = monoFloat
        } else {
            resampled = linearResample(monoFloat, from: sourceRate, to: targetRate)
        }

        return floatToInt16(resampled)
    }

    // MARK: - Extract

    private func extractMonoFloat(from sampleBuffer: CMSampleBuffer,
                                  asbd: AudioStreamBasicDescription,
                                  frames: Int,
                                  channels: Int) -> [Float]? {
        var sizeNeeded: Int = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard sizeNeeded > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let ablPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }
        // Keep blockBuffer alive across the read.
        defer { _ = blockBuffer }

        let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        let is16Bit = asbd.mBitsPerChannel == 16 && !isFloat

        var mono = [Float](repeating: 0, count: frames)

        if isFloat {
            if isInterleaved, let data = abl[0].mData {
                let src = data.assumingMemoryBound(to: Float.self)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels {
                        sum += src[f * channels + c]
                    }
                    mono[f] = sum / Float(channels)
                }
            } else {
                // Non-interleaved: one buffer per channel.
                for c in 0..<min(channels, abl.count) {
                    guard let data = abl[c].mData else { continue }
                    let src = data.assumingMemoryBound(to: Float.self)
                    for f in 0..<frames {
                        mono[f] += src[f]
                    }
                }
                if channels > 1 {
                    var scale = 1.0 / Float(channels)
                    vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(frames))
                }
            }
        } else if is16Bit {
            if isInterleaved, let data = abl[0].mData {
                let src = data.assumingMemoryBound(to: Int16.self)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels {
                        sum += Float(src[f * channels + c])
                    }
                    mono[f] = (sum / Float(channels)) / Float(Int16.max)
                }
            } else {
                for c in 0..<min(channels, abl.count) {
                    guard let data = abl[c].mData else { continue }
                    let src = data.assumingMemoryBound(to: Int16.self)
                    for f in 0..<frames {
                        mono[f] += Float(src[f]) / Float(Int16.max)
                    }
                }
                if channels > 1 {
                    var scale = 1.0 / Float(channels)
                    vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(frames))
                }
            }
        } else {
            return nil
        }

        return mono
    }

    // MARK: - Resample / convert

    private func linearResample(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        let outCount = max(1, Int(round(Double(input.count) * targetRate / sourceRate)))
        var output = [Float](repeating: 0, count: outCount)
        let step = Float(sourceRate / targetRate)
        for i in 0..<outCount {
            let srcIndex = Float(i) * step
            let left = Int(srcIndex)
            let frac = srcIndex - Float(left)
            if left + 1 < input.count {
                output[i] = input[left] * (1 - frac) + input[left + 1] * frac
            } else if left < input.count {
                output[i] = input[left]
            }
        }
        return output
    }

    private func floatToInt16(_ input: [Float]) -> [Int16] {
        var output = [Int16](repeating: 0, count: input.count)
        for i in 0..<input.count {
            let clipped = max(-1.0, min(1.0, input[i]))
            output[i] = Int16(clipped * Float(Int16.max))
        }
        return output
    }
}
