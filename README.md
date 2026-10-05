# ios-meeting

iOS meeting transcription demo: a **Broadcast Upload Extension** captures mic + system audio (video discarded), writes stereo 16 kHz PCM chunks to an App Group, and the host app streams them to **Deepgram** with `multichannel=true` for an Us / Them chat UI.

```
Broadcast Extension                    Host App
─────────────────                      ────────
ReplayKit samples                      ChunkWatcher (App Group FSEvents)
  ├─ video → discard                   DeepgramClient (WS, multichannel)
  ├─ audioMic → 16 kHz mono Int16 ─┐   TranscriptStore
  └─ audioApp → 16 kHz mono Int16 ─┤   Chat bubbles (Us = L, Them = R)
                                   │
                         StereoAligner (L=mic, R=system)
                                   │
                         ChunkWriter → 512-frame .pcm files
                                   │
                         App Group: group.com.granola.ios-meeting
```

## Audio format

| Property | Value |
|----------|--------|
| Sample rate | 16 000 Hz |
| Sample type | signed Int16 little-endian |
| Layout | interleaved stereo |
| Left | microphone (“Us”) |
| Right | system / app audio (“Them”) |
| Chunk size | 512 frames = 2048 bytes (32 ms) |

## Setup

1. **Generate the Xcode project**
   ```bash
   brew install xcodegen   # if needed
   cd ios-meeting
   xcodegen generate
   open MeetingApp.xcodeproj
   ```

2. **Signing**
   - Select your Development Team on both `MeetingApp` and `BroadcastExtension`.
   - In the Apple Developer portal (or Xcode’s Signing & Capabilities), create an **App Group** named exactly:
     `group.com.granola.ios-meeting`
   - Enable that App Group on **both** targets.

3. **Deepgram**
   - Create an API key at https://console.deepgram.com
   - Run the app → tap the key icon → paste the key.

4. **Run on a real device** (broadcast extensions are unreliable / limited on Simulator).

## Usage

1. Tap the **broadcast picker** (screen icon) → choose **Meeting** / BroadcastExtension → start broadcast (enable microphone).
2. Join a call / play audio so system audio is present.
3. Tap **Listen** in the app — chunks stream to Deepgram; Us / Them bubbles appear.

## Project layout

```
ios-meeting/
├── project.yml
├── Shared/
│   ├── AudioConstants.swift
│   └── AppGroup.swift
├── BroadcastExtension/
│   ├── SampleHandler.swift      # RPBroadcastSampleHandler
│   ├── AudioResampler.swift     # → mono Int16 @ 16 kHz
│   ├── StereoAligner.swift      # L/R align + skew pad
│   ├── ChunkWriter.swift        # 512-frame .pcm files
│   ├── Info.plist
│   └── BroadcastExtension.entitlements
└── MeetingApp/
    ├── MeetingAppApp.swift
    ├── ContentView.swift        # chat UI + broadcast picker
    ├── ChatBubbleView.swift
    ├── ChunkWatcher.swift
    ├── DeepgramClient.swift
    ├── TranscriptStore.swift
    ├── Info.plist
    └── MeetingApp.entitlements
```

## Deepgram query params

```
encoding=linear16
sample_rate=16000
channels=2
multichannel=true
interim_results=true
model=nova-2
```

Channel `0` → Us · Channel `1` → Them.

## Notes / limitations

- App Groups require a paid Apple Developer account for device installs.
- System audio (`audioApp`) is whatever ReplayKit delivers for the broadcast — typically device audio mixed for the screen recording session.
- Mic and system clocks can skew; the aligner zero-pads when one side leads by >100 ms.
- Bundle IDs default to `com.granola.iosmeeting` / `com.granola.iosmeeting.BroadcastExtension` — change them in `project.yml` if needed, and keep the App Group ID in sync with `AudioConstants.appGroupID`.
