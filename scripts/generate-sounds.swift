#!/usr/bin/env swift

import Foundation

private let sampleRate = 48_000
private let outputDirectory = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath
).appendingPathComponent("Resources/Sounds", isDirectory: true)

private struct Tone {
    let start: Double
    let duration: Double
    let startFrequency: Double
    let endFrequency: Double
    let amplitude: Double
    let warmth: Double
}

private struct SoundSpec {
    let filename: String
    let duration: Double
    let targetPeak: Double
    let tones: [Tone]
    let airAmount: Double
}

private let sounds = [
    SoundSpec(
        filename: "OpenTypeReady.wav",
        duration: 0.135,
        targetPeak: 0.21,
        tones: [
            Tone(
                start: 0.000,
                duration: 0.118,
                startFrequency: 720,
                endFrequency: 865,
                amplitude: 1.00,
                warmth: 0.16
            ),
            Tone(
                start: 0.042,
                duration: 0.083,
                startFrequency: 1_080,
                endFrequency: 1_130,
                amplitude: 0.34,
                warmth: 0.08
            )
        ],
        airAmount: 0.055
    ),
    SoundSpec(
        filename: "OpenTypeRelease.wav",
        duration: 0.155,
        targetPeak: 0.19,
        tones: [
            Tone(
                start: 0.000,
                duration: 0.140,
                startFrequency: 820,
                endFrequency: 610,
                amplitude: 1.00,
                warmth: 0.18
            ),
            Tone(
                start: 0.020,
                duration: 0.110,
                startFrequency: 1_150,
                endFrequency: 940,
                amplitude: 0.22,
                warmth: 0.06
            )
        ],
        airAmount: 0.030
    ),
    SoundSpec(
        filename: "OpenTypeDone.wav",
        duration: 0.245,
        targetPeak: 0.20,
        tones: [
            Tone(
                start: 0.000,
                duration: 0.145,
                startFrequency: 640,
                endFrequency: 675,
                amplitude: 0.78,
                warmth: 0.20
            ),
            Tone(
                start: 0.072,
                duration: 0.160,
                startFrequency: 900,
                endFrequency: 980,
                amplitude: 1.00,
                warmth: 0.14
            )
        ],
        airAmount: 0.012
    ),
    SoundSpec(
        filename: "OpenTypeIssue.wav",
        duration: 0.245,
        targetPeak: 0.18,
        tones: [
            Tone(
                start: 0.000,
                duration: 0.150,
                startFrequency: 420,
                endFrequency: 355,
                amplitude: 0.86,
                warmth: 0.24
            ),
            Tone(
                start: 0.075,
                duration: 0.155,
                startFrequency: 325,
                endFrequency: 270,
                amplitude: 1.00,
                warmth: 0.28
            )
        ],
        airAmount: 0.000
    )
]

private func smoothstep(_ value: Double) -> Double {
    let x = min(max(value, 0), 1)
    return x * x * (3 - 2 * x)
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

private func sample(for tone: Tone, at time: Double) -> Double {
    let localTime = time - tone.start
    guard localTime >= 0, localTime <= tone.duration else { return 0 }

    let progress = localTime / tone.duration
    let attack = smoothstep(localTime / min(0.009, tone.duration * 0.18))
    let releaseStart = tone.duration * 0.32
    let release = 1 - smoothstep(
        (localTime - releaseStart) / (tone.duration - releaseStart)
    )
    let envelope = attack * release
    let frequencyDelta = tone.endFrequency - tone.startFrequency
    let phase = 2 * Double.pi * (
        tone.startFrequency * localTime
            + 0.5 * frequencyDelta / tone.duration * localTime * localTime
    )
    let fundamental = sin(phase)
    let secondHarmonic = sin(phase * 2) * tone.warmth * (1 - progress)
    return (fundamental + secondHarmonic) * envelope * tone.amplitude
}

private func writeWAV(_ values: [Double], to outputURL: URL) throws {
    let samples = values.map {
        Int16(min(max($0, -1), 1) * Double(Int16.max))
    }
    let bytesPerSample = 2
    let dataSize = UInt32(samples.count * bytesPerSample)
    var wav = Data()
    wav.append("RIFF".data(using: .ascii)!)
    appendUInt32(36 + dataSize, to: &wav)
    wav.append("WAVE".data(using: .ascii)!)
    wav.append("fmt ".data(using: .ascii)!)
    appendUInt32(16, to: &wav)
    appendUInt16(1, to: &wav)
    appendUInt16(1, to: &wav)
    appendUInt32(UInt32(sampleRate), to: &wav)
    appendUInt32(UInt32(sampleRate * bytesPerSample), to: &wav)
    appendUInt16(UInt16(bytesPerSample), to: &wav)
    appendUInt16(16, to: &wav)
    wav.append("data".data(using: .ascii)!)
    appendUInt32(dataSize, to: &wav)

    for sample in samples {
        appendUInt16(UInt16(bitPattern: sample), to: &wav)
    }

    try wav.write(to: outputURL, options: .atomic)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for (soundIndex, sound) in sounds.enumerated() {
    let sampleCount = Int(Double(sampleRate) * sound.duration)
    var values = [Double]()
    values.reserveCapacity(sampleCount)
    var randomState = UInt32(0x4F_54_59_50 + soundIndex)
    var previousNoise = 0.0

    for index in 0..<sampleCount {
        let time = Double(index) / Double(sampleRate)
        var value = sound.tones.reduce(0.0) {
            $0 + sample(for: $1, at: time)
        }

        if sound.airAmount > 0 {
            randomState = 1_664_525 &* randomState &+ 1_013_904_223
            let noise = Double(Int32(bitPattern: randomState))
                / Double(Int32.max)
            let highPassedNoise = noise - previousNoise * 0.92
            previousNoise = noise
            let airEnvelope = smoothstep(time / 0.008)
                * (1 - smoothstep(
                    (time - sound.duration * 0.44) / (sound.duration * 0.56)
                ))
            value += highPassedNoise * sound.airAmount * airEnvelope
        }

        values.append(value)
    }

    let rawPeak = max(values.map(abs).max() ?? 1, 0.000_001)
    let scaled = values.map { $0 / rawPeak * sound.targetPeak }
    let outputURL = outputDirectory.appendingPathComponent(sound.filename)
    try writeWAV(scaled, to: outputURL)
    print(outputURL.path)
}
