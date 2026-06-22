# monami app (Flutter voice client, Phase 2)

Thin macOS-desktop voice client: captures mic as 16 kHz mono PCM, streams it to
the local backend over WebSocket, plays back the 24 kHz PCM reply, and shows the
conversation as a chat. One tap opens the mic (continuous streaming, server VAD
splits turns); a second tap stops.

Built/validated on **macOS desktop first**; iPad/phone/web are later phases.

## Prerequisites

- Flutter SDK (stable) with macOS desktop enabled: `flutter config --enable-macos-desktop`.
- Xcode + CocoaPods (for the macOS plugin build).
- The **backend running** — see `../backend/README.md`. The app connects to
  `ws://127.0.0.1:8000/ws/voice` by default.
- A **microphone**. The Mac mini has none built in — pair AirPods or any USB/BT
  mic and select it in System Settings → Sound → Input.

## Run

```bash
cd app
flutter pub get
flutter run -d macos
```

Tap **"Chạm để nói"** → speak (mic streams continuously) → hear the reply →
keep talking for more turns → tap again to stop.

## Audio plugins (chosen after a spike)

| Concern | Plugin | Notes |
|---------|--------|-------|
| Mic capture | `record` 7.1.0 | `startStream` + `AudioEncoder.pcm16bits` @ 16 kHz mono. Spike confirmed it returns real PCM16 on macOS (not the f32 of upstream issue #397). |
| Playback | `flutter_pcm_sound` 3.3.3 | Feed-callback model; plays raw 24 kHz PCM with low latency. |
| Transport | `web_socket_channel` 3.x | Binary frames = PCM; JSON text frames = control/transcripts. |

No Swift platform channel was needed.

## Wire protocol (must match `../backend`)

- **app → backend:** binary = 16 kHz PCM chunk; `{"type":"end_utterance"}` on stop.
- **backend → app:** binary = 24 kHz PCM; `{"type":"in_transcript"|"out_transcript","text":…}`;
  `{"type":"turn_complete"}`; `{"type":"error","message":…}`.

## Layout

| File | Role |
|------|------|
| `lib/audio_capture.dart` | mic → 16 kHz mono PCM16 stream |
| `lib/audio_playback.dart` | feed 24 kHz PCM → speaker (queue + drain signal) |
| `lib/voice_socket.dart` | WebSocket connect, send audio, decode frames |
| `lib/voice_controller.dart` | state machine + conversation history (tap-to-toggle) |
| `lib/main.dart` | UI: status banner, chat transcript, talk button |

## macOS permissions

`macos/Runner/*.entitlements` grant `com.apple.security.device.audio-input` +
`com.apple.security.network.client`; `Info.plist` carries `NSMicrophoneUsageDescription`.
First launch prompts for mic access.

## Notes / known limits

- **AirPods (Bluetooth HFP) mic** degrades the *input transcript label* (it may
  mis-detect the language), but the model still understands and replies correctly
  in Vietnamese. A real device mic transcribes cleanly. Transcripts are dev-only.
- Latency anchor in dev needs tightening before Phase 4's decision-grade numbers.
- Web/mobile builds are a later phase (web raw-PCM capture needs AudioWorklet).
