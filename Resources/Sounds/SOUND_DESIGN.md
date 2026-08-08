# OpenType Air sound system

OpenType Air is an original, deterministic four-cue UI sound family generated
locally by `scripts/generate-sounds.swift`. No competitor or third-party audio
asset is copied into OpenType.

## Cues

- `OpenTypeReady.wav` (135 ms): a short rising air-and-glass cue. It plays only
  after the microphone is ready, so speech can begin immediately after it.
- `OpenTypeRelease.wav` (155 ms): a soft falling counterpart that confirms the
  recorder has stopped and processing has begun.
- `OpenTypeDone.wav` (245 ms): two restrained rising notes for a completed
  insertion or clipboard result.
- `OpenTypeIssue.wav` (245 ms): two rounded falling notes. It is distinct but
  deliberately avoids the alarm-like character of the macOS Basso sound.

All files are 48 kHz, mono, 16-bit PCM WAV. Peaks remain between roughly -13 dB
and -15 dB before the app's per-cue playback gain. Mode changes remain silent
because the visual status overlay already supplies sufficient feedback.

## Research inputs

- Apple Dictation treats the sound as a microphone-ready signal.
- Apple's feedback guidance recommends matching interruption level to the
  importance of the state and avoiding routine success noise when it adds no
  information.
- Typeless documents an interaction sound as the point at which users can begin
  dictating.
- Local inspection of Wispr Flow shows separate start, stop, paste, and error
  assets. Its current start cue is approximately 150 ms, reinforcing the need
  for very short sounds in a high-frequency voice workflow.

These observations informed the state model and duration envelope only. The
actual tones, synthesis code, and audio files are original to OpenType.

## Regeneration

From the project root:

```bash
swift scripts/generate-sounds.swift
```
