# Behringer FLOW 8 MIDI Implementation Chart (complete and tested)

The complete MIDI implementation of the **Behringer FLOW 8** digital mixer: every MIDI channel, every Control Change (CC), Program Change and note, with value ranges, conversion formulas and the FX preset names. Every message was checked against the mixer's own SysEx state dump. The chart also lists what the official Behringer MIDI documentation leaves out, for example **EQ frequency and Q over MIDI**, **balance for the monitor and FX buses** and **FX parameter 3**. It also corrects the **FX MIDI channels** (14 / 15, not 13 / 14).

This chart is part of [FLOW 8 Web Remote](../README.md), an unofficial browser remote for the FLOW 8. It is not affiliated with or endorsed by Behringer or Music Tribe. For the SysEx state dump, the Bluetooth (BLE) protocol and all byte offsets see the [technical manual](MANUAL.md). A machine-readable table is in [`flow8-midi-sysex-ble-tabelle.csv`](flow8-midi-sysex-ble-tabelle.csv) (German column headers).

**Status of each fact**

| Status | Meaning |
|---|---|
| **confirmed** | tested on a real FLOW 8 |
| **per docs** | from Behringer's MIDI documentation, consistent with all tests so far |
| **dump** | the value changes in the mixer's state dump; audible effect not checked |

---

## Contents

1. [Quick reference: MIDI channels](#1-quick-reference-midi-channels)
2. [Input channels (MIDI channel 1–7)](#2-input-channels-midi-channel-17)
3. [Output buses (MIDI channel 8–12)](#3-output-buses-midi-channel-812)
4. [FX slots (MIDI channel 14 and 15)](#4-fx-slots-midi-channel-14-and-15)
5. [Global (MIDI channel 16)](#5-global-midi-channel-16)
6. [Value conversions](#6-value-conversions)
7. [FX preset names](#7-fx-preset-names)
8. [What MIDI cannot do](#8-what-midi-cannot-do)
9. [SysEx](#9-sysex)
10. [How this chart was tested](#10-how-this-chart-was-tested)
11. [FAQ](#11-faq)

---

## 1 Quick reference: MIDI channels

The FLOW 8 receives MIDI over **USB**. The channel numbers below are the usual 1–16 (status byte low nibble = channel − 1).

| MIDI channel | Target | Status |
|---|---|---|
| 1 | Ch 1 (mic) | confirmed |
| 2 | Ch 2 (mic) | confirmed |
| 3 | Ch 3 (mic/line) | confirmed |
| 4 | Ch 4 (mic/line) | confirmed |
| 5 | Ch 5/6 (stereo) | confirmed |
| 6 | Ch 7/8 (stereo) | confirmed |
| 7 | USB/BT (playback from computer or phone) | confirmed |
| 8 | MAIN | confirmed |
| 9 | MON 1 | confirmed |
| 10 | MON 2 | confirmed |
| 11 | FX 1 bus (return) | confirmed |
| 12 | FX 2 bus (return) | confirmed |
| 13 | **unused**: no message on this channel has any effect | confirmed |
| **14** | **FX 1 slot**: preset and parameters | confirmed |
| **15** | **FX 2 slot**: preset and parameters | confirmed |
| 16 | global: snapshots, FX mute, tap tempo | confirmed |

> **Note:** the official Behringer MIDI documentation gives the FX slots as channel 13 and 14. On the mixer they are **channel 14 (FX 1) and 15 (FX 2)**. Channel 13 does nothing.

## 2 Input channels (MIDI channel 1–7)

| CC | Function | Value | Status |
|---|---|---|---|
| 1 | EQ low (band 1) gain | 64 = 0 dB, ±15 dB | per docs |
| 2 | EQ low-mid (band 2) gain | 64 = 0 dB, ±15 dB | per docs |
| 3 | EQ hi-mid (band 3) gain | 64 = 0 dB, ±15 dB | per docs |
| 4 | EQ high (band 4) gain | 64 = 0 dB, ±15 dB | per docs |
| 5 | mute | 127 on, 0 off | per docs |
| 6 | solo | 127 on, 0 off | per docs |
| 7 | channel level into MAIN | level curve, −∞…+10 dB | confirmed |
| 8 | gain (preamp) | −20…+60 dB | confirmed |
| 9 | low cut frequency | 20–600 Hz in 128 steps; ch 1–4, 5/6, 7/8 (USB/BT has no low cut) | confirmed, all 128 values measured |
| 10 | pan | 0 = left, 64 = center, 127 = right | confirmed |
| 11 | compressor | 0–100 % | confirmed |
| 12 | 48V phantom power | 127 on, 0 off; **ch 1 and 2 only** | per docs |
| 14 | send to MON 1 | level curve | per docs |
| 15 | send to MON 2 | level curve | per docs |
| 16 | send to FX 1 | level curve | per docs |
| 17 | send to FX 2 | level curve | per docs |
| 21 | EQ band 1 frequency | 20 Hz…20 kHz, logarithmic | confirmed, all inputs |
| 22 | EQ band 2 frequency | 20 Hz…20 kHz, logarithmic | confirmed, all inputs |
| 23 | EQ band 3 frequency | 20 Hz…20 kHz, logarithmic | confirmed, all inputs |
| 24 | EQ band 4 frequency | 20 Hz…20 kHz, logarithmic | confirmed, all inputs |
| 31 | EQ band 1 Q | 0…19.7, linear; **0 = low shelf** | confirmed, all inputs |
| 32 | EQ band 2 Q | 0…19.7, linear | confirmed, all inputs |
| 33 | EQ band 3 Q | 0…19.7, linear | confirmed, all inputs |
| 34 | EQ band 4 Q | 0…19.7, linear; **0 = high shelf** | confirmed, all inputs |

CC 21–24 and 31–34 are **not in the Behringer documentation**.

## 3 Output buses (MIDI channel 8–12)

| CC | Function | Applies to | Value | Status |
|---|---|---|---|---|
| 7 | master fader | all buses | level curve, −∞…+10 dB | confirmed |
| 8 | limiter threshold | MAIN, MON 1, MON 2 | −30…0 dB | per docs |
| 10 | balance | MAIN, MON 1, MON 2, FX 1, FX 2 | 0 = left, 64 = center, 127 = right | MAIN per docs, FX buses confirmed, MON dump |
| 11–19 | 9-band graphic EQ gain, band 1–9 | MAIN, MON 1, MON 2 | 64 = 0 dB, ±15 dB | per docs |
| 21–29 | 9-band EQ frequency, band 1–9 | MAIN, MON 1, MON 2 | 20 Hz…20 kHz, logarithmic | confirmed |
| 31–39 | 9-band EQ Q, band 1–9 | MAIN, MON 1, MON 2 | 0…19.7, linear | confirmed |

- Balance on MON 1/2 and the FX buses, and CC 21–29 / 31–39, are **not in the Behringer documentation**.
- **Mute and solo of the buses cannot be set over MIDI**: CC 5 / CC 6 on channels 8–12 have no effect (tested).
- The FX buses (channels 11/12) have **no limiter** (CC 8 does nothing).
- On the FX buses, CC 11–19, 21–29 and 31–39 change values in the state dump, but there is **no audible EQ** on the FX returns.
- With the monitor **stereo link** on, MIDI channel 9 and 10 each change the EQ of both monitors.

## 4 FX slots (MIDI channel 14 and 15)

| Message | Function | Value | Status |
|---|---|---|---|
| Program Change | FX preset | Program Change *n* = preset *n*, 1–16 | confirmed |
| CC 1 | parameter 1 (e.g. Decay, Feedback) | 0–100 % | confirmed |
| CC 2 | parameter 2 (variant, e.g. Instrument / Vocal) | 0 = value A, 127 = value B | confirmed |
| CC 3 | parameter 3 | 0–100 (values above 100 are limited to 100) | dump; meaning unknown, not offered in the FLOW app |

- FX 1 = **channel 14** (status bytes `BD` for CC, `CD` for Program Change).
- FX 2 = **channel 15** (status bytes `BE` / `CE`).
- Program Change values above 16 seem to select preset 16 (not verified).

## 5 Global (MIDI channel 16)

| Message | Function | Status |
|---|---|---|
| CC 1 | FX mute: 127 on, 0 off | per docs |
| Program Change value 1–15 | load snapshot 1–15 | per docs |
| Program Change value 16 | snapshot 16 = **reset** (never send this by accident) | per docs |
| Note On, note 0, velocity 100 (`9F 00 64`) | tap tempo | confirmed |

Tap tempo only affects **FX 2 presets 1–12** (delay and echo). FX 1 and FX 2 presets 13–16 do not use a tempo.

## 6 Value conversions

*v* is the 7-bit MIDI value 0–127.

| Parameter | value → setting | setting → value | Status |
|---|---|---|---|
| Level (CC 7, sends CC 14–17, master) | v = 0: −∞; otherwise dB = (v−1)/126·80 − 70 | 0 if ≤ −143 dB, otherwise round((dB+70)/80·126) + 1 | confirmed |
| Gain (CC 8) | dB = v/127·80 − 20 | round((dB+20)/80·127) | confirmed |
| EQ gain (CC 1–4, 11–19) | dB = (v−64)·15/63 | round(64 + dB·63/15), limited to 1–127 | per docs |
| Limiter (CC 8 on a bus) | dB = v/127·30 − 30 | round((dB+30)/30·127) | per docs |
| Pan / balance (CC 10) | pan = (v−64)/63, limited to −1…+1 | round(64 + pan·63) | confirmed |
| Compressor (CC 11) | v = percent, 0–100 | | confirmed |
| EQ frequency (CC 21–29) | Hz = 20·1000^(v/127), mostly rounded down (±1 Hz) | round(127·log(Hz/20)/log(1000)) | confirmed |
| EQ Q (CC 31–39) | Q = v·19.7/127 | round(Q·127/19.7) | confirmed |
| Low cut (CC 9) | Hz = floor(20·30^(v/127)); one exception: v = 92 gives 234 Hz | the CC whose Hz is nearest | confirmed, all 128 values |

Examples: EQ frequency v = 0 → 20 Hz, v = 64 → 649 Hz, v = 127 → 20 kHz. EQ Q v = 64 → 9.93. Low cut v = 64 → 111 Hz. The complete measured low cut table is in [`flow8-lowcut-mapping.csv`](flow8-lowcut-mapping.csv).

## 7 FX preset names

The preset names are not in the state dump. These are the names shown by the FLOW app: preset name, parameter 1 name, then the two values of parameter 2 (A / B).

| Preset | FX 1 (channel 14) | FX 2 (channel 15) |
|---|---|---|
| 1 | AMBIENCE: DECAY, INSTRUMENT / VOCAL | DELAY 1/1: FEEDBACK, DULL / BRIGHT |
| 2 | PERC-REV1: DECAY, DULL / BRIGHT | DELAY 1/2: FEEDBACK, DULL / BRIGHT |
| 3 | PERC-REV2: DECAY, DULL / BRIGHT | DELAY 1/3: FEEDBACK, DULL / BRIGHT |
| 4 | GUIT-REV1: DECAY, LESS BASS / MORE BASS | DELAY 2/1: FEEDBACK, DULL / BRIGHT |
| 5 | GUIT-REV2: DECAY, LESS BASS / MORE BASS | ECHO 1/1: FILTER, SOFT / STRONG |
| 6 | CHAMBER: DECAY, PRE-D OFF / PRE-D ON | ECHO 1/2: FILTER, SOFT / STRONG |
| 7 | ROOM: DECAY, INSTRUMENT / VOCAL | ECHO 1/3: FILTER, SOFT / STRONG |
| 8 | CONCERT: DECAY, INSTRUMENT / VOCAL | ECHO 2/1: FILTER, SOFT / STRONG |
| 9 | CHURCH: DECAY, INSTRUMENT / VOCAL | WIDE ECHO: FILTER, WIDE / NARROW |
| 10 | CATHEDRAL: DECAY, SMALL / LARGE | PING PONG: FILTER, WIDE / NARROW |
| 11 | TEMPLE: DECAY, PRE-D OFF / PRE-D ON | PING P 1/3: FILTER, WIDE / NARROW |
| 12 | STADIUM: DECAY, PRE-D OFF / PRE-D ON | PING P R>L: FILTER, WIDE / NARROW |
| 13 | FLANGER: MOD SPEED, MONO / STEREO | FLANGER: MOD SPEED, MONO / STEREO |
| 14 | SOFT CHOR: DENSITY, TREM OFF / TREM ON | SOFT CHOR: DENSITY, TREM OFF / TREM ON |
| 15 | WARM CHOR: DENSITY, TREM OFF / TREM ON | WARM CHOR: DENSITY, TREM OFF / TREM ON |
| 16 | DEEP CHOR: DENSITY, TREM OFF / TREM ON | DEEP CHOR: DENSITY, TREM OFF / TREM ON |

## 8 What MIDI cannot do

These functions have no MIDI message (tested with a search over all channels). They only work over **Bluetooth** (FLOW app or [FLOW 8 Web Remote](../README.md)):

- phase invert
- low cut on/off
- 48V on channels 3 and 4
- delay of MAIN and the monitors
- FX routing (to Main / Mon 1 / Mon 2) and FX tempo in BPM
- mute and solo of the output buses
- all global settings (USB routing, monitor source, pads, tap point, headphone source)
- saving and deleting snapshots

## 9 SysEx

- The FLOW 8 sends its complete state as a **SysEx dump** of 3068 bytes (`F0 00 20 32 21 … F7`). You get it with *MIDI dump* in the FLOW app, or with the Bluetooth command `4B 01 4C`; the dump then arrives over **USB MIDI**.
- The FLOW 8 answers **no SysEx request over MIDI**. Tested without any reply: the universal identity request (`F0 7E 7F 06 01 F7`, also with device ID 00 and 01), and `F0 00 20 32 21 xx F7`, `F0 00 20 32 7F 21 xx F7`, `F0 00 20 32 00 21 xx F7` for every xx from 0 to 127.
- There is therefore no known way to read the mixer state over MIDI alone.
- The layout of the dump (levels, mute, solo, pan, names, EQ, low cut, gain, compressor, limiter, delay, FX, settings) is documented byte by byte in the [technical manual, chapter 4](MANUAL.md#4-sysex-state-dump).

## 10 How this chart was tested

1. A test page sent every Control Change (values 127 and 0), Program Change, note on/off, poly aftertouch, pitch bend and channel pressure on **all 16 MIDI channels**, plus MIDI clock, start/stop, song position and song select.
2. After each step it read the mixer's SysEx state dump and compared it with the previous one.
3. Every message that changed the dump was then repeated on its own to find which message caused the change.
4. The value ranges were measured by sending CC 0, 4, 8 … 124, 127 to every control at once and reading the dump after each step.
5. Messages that were already known were skipped. 48V (CC 12) and the snapshot Program Changes on channel 16 were never sent by the search.

Limits: effects that do not appear in the dump (e.g. tap tempo) cannot be found this way, and only the values 127 and 0 were tried in the search.

## 11 FAQ

**Behringer FLOW 8: FX preset or FX parameter does not change over MIDI. Why?**
Use MIDI channel **14 for FX 1 and 15 for FX 2**. The official documentation says 13 and 14; channel 13 does nothing.

**Can I change the EQ frequency and Q of the FLOW 8 over MIDI?**
Yes, although Behringer does not document it. Use CC 21–24 (frequency) and CC 31–34 (Q) on the input channels, and CC 21–29 / CC 31–39 on MAIN, MON 1 and MON 2. See [chapter 6](#6-value-conversions) for the formulas.

**How do I get a shelf EQ over MIDI?**
Set the Q of band 1 (low) or band 4 (high) to 0: CC 31 or CC 34 with value 0.

**Can I mute MAIN or a monitor output over MIDI?**
No. Mute and solo exist over MIDI only for the input channels (CC 5 / CC 6 on channel 1–7). The output buses need Bluetooth.

**Can I set the balance of the monitors or the FX returns over MIDI?**
Yes: CC 10 on channel 9 (MON 1), 10 (MON 2), 11 (FX 1) and 12 (FX 2).

**Can I request the mixer state over MIDI?**
No. The FLOW 8 sends its state dump over USB MIDI, but only when it is asked over Bluetooth or in the FLOW app.

**Does USB/BT have a low cut?**
No. CC 9 on channel 7 has no effect.

**Can I load and save snapshots over MIDI?**
Loading: yes, Program Change 1–15 on channel 16. Program Change 16 loads the reset snapshot. Saving and deleting: no.

---

Found something that is missing or wrong? Please open an issue. Licence: GPL-3.0 (see [LICENSE](../LICENSE)). Behringer and FLOW 8 are trademarks of their owners and are used here only to describe compatibility.
