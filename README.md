# bt-1O1

an acid bass line in the spirit of the TB-303, with a kick and a hihat.

![bt-1O1](bt-1O1.png)

demo video (screen and sound straight from the norns): [youtube.com/watch?v=wKS4IgnSViM](https://www.youtube.com/watch?v=wKS4IgnSViM)

bt-1O1 is a monophonic 303-style bass voice (saw or square, 4-pole resonant lowpass, accent, slide, drive) played by a 16-step sequencer, plus a kick and a hihat with their own 16-step pattern. it follows the norns clock, so it also syncs to external MIDI clock. the pattern and all settings are saved automatically and come back at the next start.

## requirements

- norns or a norns clone (tested on a shieldXL, Raspberry Pi 4, norns 2.9.4)
- optional: a MIDI clock source

## documentation

four pages, switched with K1 + E1: SOUND, SEQ, DRUM and MIX. bt-1O1 starts on SOUND. K3 starts and stops on every page.

### SOUND: the 303 knobs

| control | action |
|---|---|
| E2 | pick a knob: tune, cutoff, resonance, env mod, decay, accent, wave, drive |
| E3 | change it |
| K2 | drums on / off |

### SEQ: the bass line

| control | action |
|---|---|
| E1 | select step |
| E2 | note, chromatic over three octaves (C1 to C4) |
| K2 | accent |
| K1 + K2 | slide |
| K1 + K3 | note / rest |
| K1 + E3 | pattern length (1–16) |

a slide holds the note into the next step and glides to its pitch, without retriggering. while stopped, editing a step plays its note.

### DRUM: kick and hihat

| control | action |
|---|---|
| E1 | select drum step |
| E2 | pick a row: kick (BD), closed hat (HH), open hat (OH) |
| K2 | that sound on / off at the step |
| K1 + K2 | its accent on / off (louder by `drum accent`) |

the drums always loop 16 steps, so a shorter bass line drifts against them. an open hat rings until the next hat; a step has either a closed or an open hat, setting one clears the other.

### MIX: the levels

| control | action |
|---|---|
| E2 | pick a level: bass, kick (BD), closed hat (HH), open hat (OH) |
| E3 | change it |

the overall drums level is in PARAMS > DRUMS.

### sync

bt-1O1 plays sixteenths on the norns clock. with PARAMS > CLOCK > source = midi it follows external MIDI clock; MIDI start restarts at step 1, MIDI stop stops.

### default pattern

Josh Wink, "Higher State of Consciousness", after the transcription on [JonDent's famous 303 bassline patterns](https://djjondent.blogspot.com/2020/04/famous-303-bassline-patterns-page-1.html). kick on the beats, closed hat on the offbeats.

### params

- **SOUND**: tune (±12 semitones), cutoff, resonance, env mod, decay, accent, wave (saw / square), drive, bass level
- **SEQUENCER**: length
- **DRUMS**: drums on / off, drums level, drum accent, kick level / tune / decay, closed level, open level, closed decay, open decay

### files

- `dust/data/bt-1O1/pattern.lua`: the bass and drum patterns
- `dust/data/bt-1O1/last.pset`: the params, written on exit

## install

```
;install https://github.com/loopmasta/bt-1O1
```

or copy `bt-1O1.lua`, `lib/` and `preview.png` to `dust/code/bt-1O1/`.

`preview.png` is a background for the SELECT preview. stock norns doesn't show it: it needs a small patch to norns' preview menu (see [shieldxl-trixie](https://github.com/loopmasta/shieldxl-trixie)), so it's optional.

bt-1O1 brings its own SuperCollider engine (`lib/Engine_Bt1o1.sc`). after installing or updating, **restart norns once** (SYSTEM > RESTART), so SuperCollider picks it up.
