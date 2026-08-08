# HermesVoice

iOS client for the [voice-agent](../../Shared/Agents/Voice-Agent) HTTP bridge. Hold the
button, talk, and hermes answers out loud. Speech-to-text, the model, and
text-to-speech all run on the PC; the phone records, uploads, and plays.

Bundle ID `com.grizzly.hermes-voice`. Target iOS 17, iPhone only, portrait.

## How a turn works

```
tap  →  AVAudioRecorder → .m4a
        POST /converse (multipart: audio, session_id, target)
        ← JSON { transcript, reply, audio_b64, tts_ok, notice, ... }
        base64 → s16le PCM → 44-byte RIFF header → AVAudioPlayer
```

The bridge returns raw signed 16-bit PCM, not a container format, so
[WavData.swift](HermesVoice/WavData.swift) prepends a WAV header rather than
pulling in `AVAudioEngine` to play it.

`tts_ok == false` is a **success with a degraded leg**: the bridge still returns
the text. The app shows the reply and the accompanying `notice` instead of
reporting a failed turn.

## Setup

The app ships with no address and no token — a tailnet address belongs to one
machine, and this repository is cloned by a build service.

1. Settings → **Bridge address**: `http://<your-tailnet-ip>:8751`
2. Settings → **Token**: the value of `VOICE_BRIDGE_TOKEN` from `.env.bridge` on
   the PC
3. **Test connection** hits `GET /health`, which needs no token. That separates
   "the machine is unreachable" from "the token is wrong" — the two failures
   that otherwise look identical.

The token goes into the **Keychain**
([KeychainStore.swift](HermesVoice/KeychainStore.swift)), as
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it is not in a backup and
not in `UserDefaults`. It is read straight into an `Authorization` header and is
never logged, never put in a URL, and never included in an error message.

## The states, and why they look different

[TurnState.swift](HermesVoice/TurnState.swift) is where a phase decides what it
looks like, so a new state cannot be added without deciding that.

| State | Colour | Means |
|---|---|---|
| Ready / Listening / Thinking / Speaking | accent / red / purple / green | normal turn |
| **Can't reach the bridge** | **orange**, `wifi.slash` | nothing answered — Tailscale off, PC asleep, wrong address. Nothing was sent. |
| Token rejected | yellow | the bridge answered and turned the token down |
| **hermes couldn't answer** | **red**, warning triangle | the bridge is fine; the thing behind it is not |
| Didn't catch that | grey | too quiet, too short, busy — just try again |

Orange versus red is the distinction that matters: orange means something is
switched off, red means something is broken. Confusing them sends you debugging
the wrong machine.

With Tailscale off the app says so and stops. `URLSessionConfiguration` sets
`waitsForConnectivity = false`, because the default behaviour is to wait —
which is exactly the hang this must not do.

## Limits the app respects

- Recording stops itself at **110 s**. The bridge rejects clips over 120 s, so
  a forgotten recording ends in an answer rather than a guaranteed rejection.
- Turn timeout **120 s**. A warm turn measures ~7 s; a cold one, with the STT
  model loading, measured ~42 s.
- Health probe timeout **5 s**.

## Deploying

```bash
cd /path/to/ios-deploy-engine && ./deploy.sh <this-repo-url> --ref main
```

The engine clones with plain `git clone --depth 1`, with no credentials, so the
remote has to be public or the Mac has to hold credentials for it. It needs the
committed `.xcodeproj` and the **shared** scheme under
`xcshareddata/xcschemes/` — both are in this repo for that reason. Bundle IDs
must be literal in `project.pbxproj`, never `$(VAR)`.

**`--dry-run` cannot pass on the first deploy.** The dry-run branch in the
engine's `Fastfile` calls `BuildNumberResolver.next` and returns *before* the
`Spaceship::ConnectAPI` block that creates the App Store Connect app record, and
the resolver raises `App Store Connect app not found` when no record exists. So
a dry-run against a bundle ID that has never been to ASC validates project
detection, secrets, and ASC auth — and then fails on the missing record, by
design. The record gets created on the first real run.

## Info.plist is hand-written on purpose

`GENERATE_INFOPLIST_FILE = NO`. The bridge is plain HTTP on a Tailscale address,
which needs `NSAppTransportSecurity`, and that key has no `INFOPLIST_KEY_`
equivalent. `NSAllowsLocalNetworking` does not cover it either: Tailscale
addresses live in `100.64.0.0/10`, which is CGNAT space, not a private range.

Because the plist is manual, `CFBundleVersion` must stay
`$(CURRENT_PROJECT_VERSION)` — fastlane passes the bumped build number on the
`xcodebuild` line, and a literal there would ship the same build number twice.

## What has not been verified

This scaffold was written on Windows. There is no Swift compiler and no Xcode on
that machine, so **nothing here has been compiled** and no acceptance box that
requires running the app can be ticked yet.

Checked mechanically instead:

- `project.pbxproj` — balanced delimiters, every object ID both defined and
  referenced, every file reference resolving to a file that exists, every Swift
  file on disk present in the Sources phase, bundle ID literal, and the shared
  scheme's `BlueprintIdentifier` matching the native target
- `Info.plist` parses, and carries the keys listed above
- every `Contents.json` parses; the icon is 1024×1024 RGB with no alpha

The first Mac build is therefore where compile errors will appear. Two places to
look first: `SWIFT_STRICT_CONCURRENCY = minimal` with `SWIFT_VERSION = 5.0` means
actor-isolation problems arrive as warnings rather than errors, and the
`AVAudioApplication` permission API is iOS 17-only, matching
`IPHONEOS_DEPLOYMENT_TARGET`.
