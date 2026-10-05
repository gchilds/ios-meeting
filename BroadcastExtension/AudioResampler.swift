import AVFoundation
import CoreMedia

/// Converts ReplayKit audio CMSampleBuffers into mono Int16 @ 16 kHz.
final class AudioResampler {
    private let targetRate: Double
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var lastSampleRate: Double = 0
    private var lastChannels: AVAudioChannelCount = 0

    init(targetSampleRate: Double = AudioConstants.sampleRate) {
        self.targetRate = targetSampleRate
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Unable to create 16 kHz mono Int16 format")
        }
        self.outputFormat = fmt
    }

    func resample(_ sampleBuffer: CMSampleBuffer) -> [Int16]? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let inFormat = AVAudioFormat(cmAudioFormatDescription: formatDesc)

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0 else { return nil }

        if converter == nil
            || lastSampleRate != inFormat.sampleRate
            || lastChannels != inFormat.channelCount {
            converter = AVAudioConverter(from: inFormat, to: outputFormat)
            converter?.primeMethod = .none
            lastSampleRate = inFormat.sampleRate
            lastChannels = inFormat.channelCount
        }
        guard let converter else { return nil }

        guard let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { return nil }
        input.frameLength = frames

        guard fill(buffer: input, from: sampleBuffer) else { return nil }

        let ratio = targetRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(ceil(Double(frames) * ratio) + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }

        guard status != .error, error == nil, output.frameLength > 0,
              let data = output.int16ChannelData else {
            return nil
        }

        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }

    private func fill(buffer: AVAudioPCMBuffer, from sampleBuffer: CMSampleBuffer) -> Bool {
        var sizeNeeded = 0
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
        guard sizeNeeded > 0 else { return false }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: abl,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return false }
        defer { _ = blockBuffer }

        let src = UnsafeMutableAudioBufferListPointer(abl)
        let dst = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let count = min(src.count, dst.count)
        for i in 0..<count {
            guard let s = src[i].mData, let d = dst[i].mData else { continue }
            let bytes = min(Int(src[i].mDataByteSize), Int(dst[i].mDataByteSize))
            memcpy(d, s, bytes)
        }
        return true
    }
}
