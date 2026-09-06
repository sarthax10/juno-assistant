# Jarvis

*(Internally still "juno" — the paths, the CLI, the systemd unit and the
plugin id keep that name. Renaming them buys nothing and breaks the shell
plugin. `jarvis` is a symlink to `juno`.)*


A wake-word voice assistant for Omarchy. Say **“Juno”** and Claude answers
out loud, with a live view of everything it does.

```
pw-record ──► 20ms frames ──► energy VAD ──► utterance
                   │                             │
              level events                 whisper-server
             (the orb's ring)              (model stays hot)
                                                 │
                                        ┌────────┴────────┐
                                   idle: wake match   listening: the command
                                                 │             │
                                                 └──► claude -p ──► piper ──► pw-play
```

Two processes, one socket:

| Piece | What it is | Where |
|---|---|---|
| `juno-daemon` | Owns the mic, whisper, Claude, the voice | `~/.local/share/juno/juno-daemon` |
| `juno.assistant` | The Quickshell overlay and bar widget | `~/.config/omarchy/plugins/juno.assistant/` |
| `juno` | CLI, and the transport the overlay speaks | `~/.local/bin/juno` |

The overlay is a pure subscriber. Close it mid-answer and the answer still
finishes; the wake word keeps working with no UI open at all.

## Using it

| | |
|---|---|
| Say “Juno” | Wake her, then speak the request |
| Say “Juno, what’s my disk usage” | One breath — no need to wait for the chime |
| `Super + Alt + J` | Open the overlay |
| `Super + Alt + Space` | Start listening without speaking the name |
| Click the bar glyph | Open the overlay · right-click wakes her |
| `Esc` | Dismiss |
| `Ctrl + L` | Clear the conversation |

After an answer, Juno holds the floor for 12 seconds, so a follow-up needs no
wake word.

## CLI

```bash
juno ask "what changed in my dotfiles today"   # text in, no microphone
juno say "the build finished"                  # speak a line in her voice
juno wake                                      # start listening now
juno mute / unmute                             # microphone
juno quiet / speak                             # her voice
juno clear                                     # forget the conversation
juno status                                    # health check
juno logs                                      # follow the daemon
juno restart
```

## Training it on your voice

```bash
jarvis enroll
```

The shipped wake models are trained on other people. Measured here, the same
phrase spoken by this user scored **0.045** on one attempt and **0.410** on
the next — usable on a good day, invisible on a bad one, and no threshold
setting fixes that spread. (Accent is not the cause: Hindi-accented synthetic
voices score 0.976 and 0.981 on the shipped model.)

Enrolling records a dozen takes of you saying the phrase, twenty seconds of
your room in silence, thirty seconds of you saying anything *but* the phrase,
then fits a classifier on the same speech embeddings the shipped model uses.
Your takes are augmented — louder, quieter, time-shifted, mixed with your own
room noise — so a dozen recordings is enough. It reports a held-out ROC AUC
so you can see whether it generalised, and picks its operating point from the
weakest of your own takes.

Takes about three minutes, runs entirely on the CPU. The personal model votes
*alongside* the shipped one, so enrolling can only add detections, never
remove them. Delete `personal-wake.npz` to go back.

Fine-tuning whisper itself on your voice is a different matter — that needs
hours of your labelled speech and a GPU, and is not on offer here.

## Commands use a bigger model than the wake word

Nothing transcribes while Juno waits for her name. Once woken, the command
goes to `sttModelAccurate` (`small`) rather than the fast model, because in
a real room the fast one invents things. The same sentence, recorded through
this user's room:

| model | transcript |
|---|---|
| `base` | "We need certain amount of time to get here." |
| `small` | **"Can you set an alarm at 10.00?"** |

The cost is about 8 seconds instead of 3. Being understood is worth more than
being fast, and the idle path — which runs constantly — never pays it.

## The wake word

**Say "Hey Jarvis."** A dedicated wake-word model (openWakeWord) listens
continuously, ahead of the VAD and the transcriber.

The earlier design matched the name inside a whisper transcript. That is the
wrong tool: whisper is asked to write down everything anyone in the room
said, and the name then has to survive that. Measured in this room, playing
the wake phrase through the speakers:

| | whisper transcript matching | wake model |
|---|---|---|
| Wake phrase, 3 attempts | **0/3** — one came back "I know your post is amazing" | **3/3 at 0.94-0.99** |
| 90s of room noise, nobody speaking | 45 transcriptions, all discarded | **0 false wakes, 0 transcriptions** |
| Cost | a 3-13s transcription of every noise burst | ~10-15% of one core, constant |
| Latency | seconds behind | immediate |

Because the detector handles waking, **whisper no longer runs at all while
idle**. That is where the forty-five wasted transcriptions went.

Only four wake phrases exist as pretrained models: `hey_jarvis`, `alexa`,
`hey_mycroft`, `hey_marvin`. Change `wakeModel` to switch. Training a custom
phrase needs GPU hours and large negative datasets, which is why the
assistant is called Jarvis and not Juno.

`transcriptWakeFallback: true` restores the old spoken-name matching
alongside the detector, at the cost of transcribing every noise burst again.

## The old wake word, and why it needed measuring

Whisper is a language model, not a phoneme matcher. Handed an unfamiliar
proper noun it rewrites it into whatever English is most probable. Spoken
into this microphone, "Juno" came back as:

| You say | Whisper wrote | Wakes? |
|---|---|---|
| "Juno" | `You know.` / `Do you know` | via head-only aliases |
| **"Hey Juno"** | **`Hey Juneau`** | **reliably** |
| "Okay Juno" | `Okay, Juneau` | reliably |

Two things fix this, and both are in place:

**Priming.** `whisperPrompt` is handed to the decoder as context. Once whisper
has seen the word "Juno" it stops rewriting it — after priming, all five test
phrases transcribed the name correctly.

**Two tiers of alias.** `wakeAliases` are distinctive enough to count anywhere
in a sentence, because a room with a television produces long segments where
the wake word lands mid-sentence. `wakeAliasesHead` are ordinary English
("you know", "do you know") and only count when the utterance opens with them.

**Say "Hey Juno" rather than "Juno".** The "hey" anchors the parse and is
measurably more reliable.

## Configuration

`~/.config/juno/config.json` — the daemon reads it at start.

| Key | Default | Notes |
|---|---|---|
| `wakeWord` | `juno` | Display name |
| `wakeAliases` | juno, hey juno, juneau, you know, … | Whisper mangles short names predictably; the mangles are listed on purpose |
| `wakeFuzz` | `0.82` | Lower = easier to wake, more false triggers |
| `autoMode` | `scoped` | `scoped` · `full` · `ask` |
| `workspace` | `~/Juno` | Where Claude runs |
| `followUpSeconds` | `12` | How long she keeps the floor after answering |
| `sessionIdleSeconds` | `900` | Conversation memory resets after this |
| `autoHideSeconds` | `25` | `0` keeps the overlay up |
| `vadStartRatio` | `1.95` | Multiple of the noise floor that counts as speech |
| `vadSilenceMs` | `700` | Silence that ends an utterance |
| `speak` / `chime` | `true` | Voice and the wake/done tones |
| `voiceEngine` | `auto` | `kokoro` · `piper` · `espeak` |
| `kokoroVoice` | `af_heart` | See the voice list below |
| `kokoroSpeed` | `1.0` | `0.9` is slower and warmer |
| `whisperPrompt` | "Juno. जूनो…" | Decoding context — stops whisper rewriting the name |
| `sttModel` | `base` | `tiny` · `base` · `small` — bigger is slower |
| `sttCompute` | `int8` | `int8_float32` and `float32` are slower, marginally better |
| `whisperLanguage` | `auto` | Pin to `en` or `hi` to skip detection |
| `kokoroVoiceHindi` | `hf_alpha` | `hf_beta`, `hm_omega`, `hm_psi` |
| `vadEndPeakRatio` | `0.5` | Fraction of your own peak that counts as stopping |
| `vadMaxWakeMs` | `4500` | Segment cap while waiting for the wake word |

## Hindi

**Juno understands Hindi and answers in English.** Speak Hindi, Hinglish or
English at her; the reply always comes back in English, spoken in the English
voice.

That is deliberate. Kokoro's Hindi voices are slow and indistinct enough to
be unusable, and translating an answer back into Hindi bought nothing when
the person asking reads English. `hindiVoice: true` turns the Hindi voice
back on if you want it.

The Hindi is deliberately spoken, not literary. Technical words stay in
English because that is how people actually talk:

> **आपके laptop में 8 CPU cores हैं, Shreyansh।**

not `आपके संगणक में आठ संसाधन-केंद्र हैं`, which no one has ever said out loud.

**Say "हे जूनो" or "जूनो".** Whisper writes the name in Devanagari once
`whisperPrompt` has told it the name exists — without that priming it lands
on Urdu script or transliterates into Latin.

The reply is spoken by a Hindi voice (`hf_alpha`), chosen per sentence from
the script it is written in — so a Hindi answer containing an English file
name switches voices mid-reply rather than reading Devanagari with an
American accent.

The overlay renders Devanagari in Noto Sans Devanagari, switched per message,
because the theme's monospace font has no Devanagari glyphs and would show
empty boxes.

### Why not just translate?

Whisper can translate speech straight to English in one pass, which would be
simpler and faster. It is not usable here: translation **drops the wake
word**. "जूनो, मेरे device की specifications बता सकते हो" translates to
"which can also be explained in the specifications of my device" — the name
is gone, so nothing ever wakes. Juno transcribes instead, matches the wake
word in whichever script it arrives in, and lets Claude answer in English.

### Two models, routed by language

Neither available model is good at both languages, measured on this machine:

| | English | Hindi |
|---|---|---|
| `base` (multilingual) | perfect, ~3s | garbled — "कम्पिय।र में कितनी डम" |
| `collabora/faster-whisper-small-hindi` | ruined — transliterates English into Devanagari | perfect, ~7-13s |

So each utterance goes to the one that suits it — and only when it is worth
it. **While Juno is merely waiting for her name, only the fast model runs.**
It renders "Juno"/"Juneau" legibly even in Hindi speech, and that is the only
word that matters at that point. The accurate Hindi model costs thirteen
seconds a go, and escalating for every passing song was spending a core
transcribing lyrics nobody would ever read. Escalation now happens only after
a wake has matched, or while she is taking a command. The fast model runs first
and is a reliable language detector even when its Hindi transcript is poor,
so it doubles as the router: it answers English itself and hands Hindi to the
specialist. The Hindi model loads on the first Hindi utterance and stays
resident.

Set `sttModelHindi` to `""` to use one model for everything.

### No initial prompt, on purpose

`whisperPrompt` is empty. An initial prompt is *prior context*, not a hint,
and it hurt twice over:

- Whisper hallucinated the prompt's own words onto music. The phrase
  "आप कैसे हैं" appeared in eight transcripts of a song purely because it was
  sitting in that string — which is where a large share of the false wakes
  came from.
- It treated the wake word as already said and skipped it. "Hey Juno, how
  many CPU cores" came back as "How many CPU cores", so the wake never
  matched.

### Hindi is slower, and here is why

Recognition takes about five seconds for a short Hindi phrase, against under
two for English. Two reasons compound:

1. Devanagari tokenizes into far more tokens than Latin, and whisper decodes
   one token at a time.
2. **This CPU runs at 1200 MHz** — see the hardware note at the end.

whisper.cpp needed 30–100 seconds for the same clips, which is why the engine
is now `faster-whisper` (CTranslate2, int8) in `juno-stt`. `sttModel: "small"`
is more accurate and several times slower; `"tiny"` translates Hindi into
English instead of transcribing it, so it is not an option.

## The voice

Kokoro (82M parameters, ONNX, on the CPU) — a neural voice rather than a
concatenative one. Piper stays installed as a fallback and espeak as a last
resort; `voiceEngine: "auto"` picks the best one present.

Change `kokoroVoice` in the config and restart. Some worth trying:

| Voice | Character |
|---|---|
| `af_heart` | Warm American female — the default |
| `af_nova` | Brighter, closer to what ChatGPT sounds like |
| `af_bella` | Lower, slower, more deliberate |
| `bf_emma` · `bf_isabella` | British female |
| `am_michael` · `am_onyx` | American male, onyx being the deeper |
| `bm_george` · `bm_fable` | British male |
| `hf_alpha` · `hf_beta` | Hindi female — `hf_alpha` is the default |
| `hm_omega` · `hm_psi` | Hindi male |

```bash
juno say "the build finished"     # audition a voice without waiting for a reply
```

Kokoro runs at roughly real time on this CPU, so replies are synthesized one
sentence at a time and playback starts on the first one. If it ever falls
behind, the gap lands on a sentence boundary and reads as a breath.

### Tuning the wake word

Too many false wakes: raise `wakeFuzz` toward `0.9`, or trim `wakeAliases`
down to `["juno", "hey juno"]`.

She misses you: lower `wakeFuzz` to `0.75`, lower `vadStartRatio` to `1.6`,
and add whatever whisper actually heard. To find out what that is:

```bash
juno logs        # every transcript passes through here
```

## What Juno is allowed to do

`autoMode: "scoped"` runs Claude with permissions bypassed — she edits files
and runs commands without asking — inside `~/Juno`. A `PreToolUse` hook
(`juno-guard`) stands between her and the commands you cannot take back:
recursive deletes, anything needing root, force pushes, hard resets, device
writes, pipe-to-shell installs, package removal, power state changes.

A blocked command surfaces in the overlay with **Run it anyway**, which
replays that turn with the guard off.

`full` removes the guard. `ask` makes her read-only.

The guard is a denylist, and a denylist is never complete. It is there to
catch a misheard sentence, not a determined one.

## Known local issue

This machine's `whisper-cpp` and `ffmpeg` are linked against `libbluray.so.4`
while the installed `libbluray` provides soname `3`. `ffmpeg` is currently
broken system-wide as a result. The fix is a full upgrade:

```bash
sudo pacman -Syu
```

Until then Juno passes a private shim directory on `LD_LIBRARY_PATH` to its
own whisper processes only — nothing is written to `/usr/lib`, and the shim
is ignored the moment a real `libbluray.so.4` exists. Whisper never calls
into libbluray; it arrives as a transitive ffmpeg dependency for Blu-ray
demuxing, which a WAV file never touches.

## Setup on another machine

```bash
~/.local/share/juno/juno-setup
```

Installs `whisper-cpp` + `ggml-cpu`, sets up piper in a private venv, fetches
both models, and starts the service. Safe to re-run.

## Troubleshooting

**She hears her own voice and answers it.** Playback end used to be
estimated from when synthesis *started*. On this machine synthesis routinely
runs slower than real time — 13.7 seconds to produce 6.4 seconds of speech —
so the estimate concluded playback was long over, reopened the microphone
into Juno's own sentence, transcribed it, and treated it as a command. It
showed up in the logs as her own replies coming back: "you'll get a
notification about it", "only 6% used".

Playback end is now measured from the first byte actually handed to the
speaker, plus the length of the audio, plus `ttsDrainSeconds` for whatever
the sink still holds. The microphone then stays shut a further
`micReopenDelay` (1.4s) because the room keeps ringing after the speaker
stops and a laptop microphone hears that too.

**She stops responding in a loud room.** Transcription is slower than a
television generates speech-shaped audio, so the work queue grew without
bound and everything arrived tens of seconds late — including push-to-talk,
which was sitting behind a backlog of song lyrics. The queue now keeps only
`maxPendingSegments` (2) and discards anything older than
`maxSegmentAgeSeconds` (8), because answering a question you asked fifteen
seconds ago is worse than not answering it. `juno wake` is handled inline and
never queues: push-to-talk exists for exactly the moments when the room is
too loud, which is exactly when the queue is deepest.

**She mishears a whole sentence.** The idle segment cap used to be 4.5s.
"Juno, can you tell me the specifications of my device" takes 3.2s to say, so
if music opened the segment a second before you started, the cap fired
mid-sentence and whisper was handed half a request. The cap is now 9s and
junk is rejected by the confidence gate instead. That sentence now
transcribes verbatim in 2.7s.

**She never wakes — check these two first.**

```bash
juno status
```

It leads with the two settings that make Juno useless while looking fine:
a muted microphone and a disabled voice. Both persist across restarts, and a
muted microphone still shows levels in the panel — the level meter is read
before the mute gate — so it can look alive while hearing nothing. The panel
now shows a red banner when muted; click it to unmute, or run `juno unmute`.

**PipeWire left the microphone suspended.** Seen on this machine: the source
sat `SUSPENDED` with Juno's capture stream still attached, so the read never
returned and the daemon reported "capture started" while hearing nothing for
twenty minutes. `pactl list short sources` shows the state; direct ALSA
capture (`arecord -D hw:0,6`) still working while `pw-record` returns zero
bytes confirms PipeWire rather than the driver. The fix:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Juno now watches for this itself: `micStallSeconds` (12 by default) restarts
the capture if no audio arrives, so it recovers without being told.

**She still never wakes.** `juno status` — check `whisper: true`. Then `juno logs`
and speak: every transcript is printed. If nothing appears at all, the VAD
never fired; lower `vadStartRatio`.

**She activates when nobody said anything.** Three separate causes, all now
handled. Whisper hallucinating the initial prompt onto music (the prompt is
gone). The follow-up window re-arming after every answer, so one wake turned
into an endless chain — `followUpMaxTurns` caps it, and `followUpSeconds: 0`
disables free-listening entirely, which is the right setting in a room with a
speaker in it. And no confidence check on transcripts: whisper reports
`no_speech_prob` and `avg_logprob`, and on this machine real speech scores
0.001 / -0.55 while music transcribed as Hindi scored 0.54 / -1.24, so
`maxNoSpeech` and `minLogProb` throw the latter away before it can become a
command.

**Is it actually listening to me?** While Juno is listening, a pulsing accent
border is drawn around the whole screen, thickening with your voice. It is a
click-through overlay on its own layer, so it shows over anything. If that
border is not there, she is not listening. The panel also says whether the
current window still lets you skip the wake word, and counts it down.

**She keeps listening after you stop.** Endpointing is relative to your own
voice, not to the room: the segment ends when the level falls below
`vadEndPeakRatio` of that utterance's loudest moment. A gate based only on
the noise floor cannot close while music is playing — the floor sits under
the music, the music sits over the gate, and the utterance runs to the length
cap. If she still cuts off late, raise `vadEndPeakRatio` toward `0.6`; if she
cuts you off mid-sentence, lower it toward `0.4`.

**She wakes at everything, or answers your television.** After replying, Juno
holds the floor for `followUpSeconds` and treats anything the microphone
catches as addressed to her — including dialogue from a speaker. In a room
with audio playing, set `followUpSeconds` to `0` so every turn needs the wake
word, and raise `vadStartRatio`.

**Echo cancellation (optional).** `juno-echo-cancel on` subtracts the
speaker output from the microphone using WebRTC AEC. It works, but it routes
every application's audio through a virtual sink, because cancellation needs
the playback as a reference. `juno-echo-cancel off` reverts it. Headphones
achieve the same result with nothing to configure.

**Audio playing through speakers is heard as speech.** The laptop's
microphone picks up its own output, so whatever is playing gets transcribed
continuously — which also costs CPU, since every segment runs through
whisper. Headphones eliminate this entirely. It is the single biggest
improvement available in a noisy room.

**Silent replies.** `juno say "test"`. If that is silent, piper is missing —
re-run `juno-setup`.

**The overlay is stale after an edit.** Quickshell caches compiled QML:

```bash
rm -rf ~/.cache/quickshell/qmlcache && omarchy restart shell
```


## A hardware note

This laptop's CPU is running at **1200 MHz on every core under full load** —
half its 2.4 GHz base clock, and 28% of its 4.2 GHz turbo. Measured with all
eight cores busy.

It is not a software setting. The governor is `powersave` (correct for
`intel_pstate`), the energy preference is `performance`, the platform profile
is `performance`, `max_perf_pct` is 100, turbo is enabled, and the machine is
on a 65 W USB-C PD charger at 64 °C — comfortably under the 100 °C limit.
And yet:

```
package_throttle_count:         12627
package_throttle_total_time_ms: 50751
```

Something below the operating system is clamping the package. On this class
of laptop that is usually BD PROCHOT asserted by another component, or an EC
firmware quirk — a BIOS/EC update is the usual fix, and `throttled`-style
tools can confirm it.

Everything in Juno is two to three times slower than it should be because of
this. Every latency number above was measured on the throttled clock, so they
are a floor, not a ceiling.
