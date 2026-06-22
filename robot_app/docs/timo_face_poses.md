# Mikee Robot Face — Pose Table & Visual Constants (Beam / OLED style)

Design reference for the Flutter `CustomPainter` port. Documents the **Beam (OLED)**
style — the chosen production style. The prototype (`mikee_face_prototype.html`) still ships
both styles (Soft capsule + Beam) for visual comparison; only Beam is specified here.

The face is driven entirely by this parameter model (1:1 with the implementation state):

```
state       : idle | attentive | greeting | listening | thinking | speaking | sleepy
gazeX        : -1 .. 1      (left .. right)
gazeY        : -1 .. 1      (up .. down)
blink        :  0 .. 1      (0 = fully open, 1 = fully closed)
mouthOpen    :  0 .. 1
expression   : neutral | happy | curious | surprised   (additive modifier on top of state)
```

### Scale convention — everything is relative to screen size

All sizes below are given as a fraction of **`shortestSide`** (`min(width, height)`),
which keeps the face proportioned identically at any resolution / aspect ratio.

> The prototype uses an internal scale unit `S = shortestSide / 100`. Every constant here
> is `<prototype S-multiple> / 100`. e.g. eye width `19·S` → `0.19 · shortestSide`.
> Glow-blur values in the prototype were authored as **absolute px**; below they are
> re-expressed as `×S` (i.e. `·shortestSide/100`) so bloom scales with resolution too —
> recommended for the port.

The face group is centered horizontally; its vertical center sits slightly **above** the
screen midpoint and is offset by the live breathing bob (see timing).

---

## A. Visual constants (Beam)

### Colors
| Token | Value | Use |
|---|---|---|
| `bgColor` | `#0F0F0F` | screen background |
| `eyeColor` | `#FFE3CE` | eye fill, brows (warm off-white) |
| `accent` / `glowColor` | `#FF6B35` | iris, mouth, all bloom/glow |
| `pupilColor` | `#3A1604` | pupil core |
| `mouthOpenFill` | `#5A1E06` | inner mouth when open |
| `tongueColor` | `#FF6B35` @ ~0.55α | tongue hint inside open mouth |
| `catchlightColor` | `#FFFFFF` | fixed eye highlight |

Brightness is multiplied by a per-state **`dim`** factor (1.0 normal → 0.5 sleepy) applied
to every color and glow alpha.

### Eyes (capsule = rounded rect)
| Constant | Relative value | Notes |
|---|---|---|
| `eyeWidth` | `0.19 · shortestSide` | × `eyeScale` (per state) |
| `eyeHeight` | `0.24 · shortestSide` | × `eyeScale` × `(1 − squint·0.35)` × `min(open,1.25)` |
| `eyeCornerRadius` | `0.07 · shortestSide` | fixed radius (Beam look); Soft style uses `min(w,h)/2` |
| `eyeGapCenterToCenter` | `0.52 · shortestSide` | eyes at `±0.26·shortestSide` from face center X |
| `eyesCenterY` | `−0.08 · shortestSide` from face center | above midline; add breathing bob |
| `eyeGlowBlur` | `0.34 · shortestSide · (0.5 + glow)` | outer bloom (accent) |

### Iris / pupil / catchlight (clipped inside the eye)
| Constant | Relative value | Notes |
|---|---|---|
| `irisRadius` | `0.085 · shortestSide` | accent fill |
| `pupilRadius` | `0.52 · irisRadius` ≈ `0.044 · shortestSide` | dark core |
| `maxGazeTravelX` | `0.42 · eyeWidth` ≈ `0.080 · shortestSide` | pupil offset at gazeX = ±1 |
| `maxGazeTravelY` | `0.42 · eyeHeight` ≈ `0.101 · shortestSide` | pupil offset at gazeY = ±1 |
| `catchlight1.offset` | `(+0.40·iris, −0.50·iris)` from pupil center | top-right, follows gaze |
| `catchlight1.radius` | `0.32 · irisRadius` ≈ `0.027 · shortestSide` | |
| `catchlight2.offset` | `(−0.35·iris, +0.40·iris)` from pupil center | secondary, ~0.5α |
| `catchlight2.radius` | `0.16 · irisRadius` ≈ `0.014 · shortestSide` | |

### Brows (straight stroke)
| Constant | Relative value | Notes |
|---|---|---|
| `browThickness` | `0.055 · shortestSide` | round caps |
| `browLength` | `0.20 · shortestSide` | × `eyeScale` |
| `browNeutralY` | `0.22 · shortestSide` **above** eye center | raised/lowered by `browY` (units below = ×0.01·shortestSide) |
| `browGlowBlur` | `0.10 · shortestSide · (0.4 + glow)` | |
| brow tilt mapping | inner end `Δy = −side·(browTilt·0.5)·0.10·shortestSide`; outer end `Δy = +side·(browTilt·0.5)·0.06·shortestSide` | `+browTilt` = inner-up (raise), `−browTilt` = inner-down (furrow) |
| brow visibility | hidden when `eyeArc > 0.6` (i.e. greeting ^_^) | |

### Mouth
| Constant | Relative value | Notes |
|---|---|---|
| `mouthWidth` | `0.34 · shortestSide` | |
| `mouthCenterY` | `0.26 · shortestSide` **below** face center | ≈ `0.34·shortestSide` below eye center |
| `mouthOpenHeightMax` | `0.26 · shortestSide` | at `mouthOpen = 1` |
| `mouthCurveAmount` | `0.18 · shortestSide` | full deflection at `mouthCurve = ±1` |
| `lipStrokeWidth` | `0.065 · shortestSide` | Beam (Soft = `0.055`); round caps |
| `mouthGlowBlur` | `0.16 · shortestSide · (0.4 + glow)` | |
| mouth geometry | corners at `y = mouthCenterY − mouthCurve·0.09·shortestSide`; control point at `y = mouthCenterY + mouthCurve·0.18·shortestSide` (quadratic) | upper lip always drawn; lower lip drawn only when open |

### Beam-only overlay
- **Scanlines:** 2px-tall black bars at ~0.05α every 4px down the screen (OLED texture).

---

## B. Per-state pose table (Beam, expression = neutral)

`eyeScale` multiplies eye + brow size. `glow` scales every bloom. `dim` scales brightness.
`browY` is in scale units (×`0.01·shortestSide`); negative = raised, positive = lowered.

| State | Eye openness | Eye shape | browY (offset) | brow angle | Mouth shape | mouthOpen | Gaze behavior | eyeScale / glow / dim |
|---|---|---|---|---|---|---|---|---|
| **idle** | 1.0 | capsule | 0 (neutral) | flat | smile-line, curve `+0.25` | 0 | **drift / wander** | 1.00 / 0.35 / 1.0 |
| **attentive** | 1.0 | **wide** capsule | −7 (raised) | inner-up `+0.12` | faint smile `+0.12` | 0 | **track** (gaze / cursor) | 1.14 / 0.50 / 1.0 |
| **greeting** | — (eyes become arc) | **arc-up ^_^** (`eyeArc 1`) | −4 *(brows hidden)* | — | **big smile** `+0.95` | 0 | track / forward | 1.04 / 0.75 / 1.0 |
| **listening** | ~1.0 (`squint 0.12`) | capsule, slight squint | 0 | flat | smile `+0.20` | 0 | track | 1.05 / 0.65 / 1.0 |
| **thinking** | 1.0 | capsule | −2 | **furrow** `−0.50` (inner-down) | near-flat `−0.05` | 0 | **look up-aside** (gazeX `−0.55`, gazeY `−0.60`) + headTilt `+0.06` | 0.96 / 0.35 / 1.0 |
| **speaking** | 1.0 | capsule | −3 | flat | smile `+0.30` | **auto lip-sync** (see C) | track / forward | 1.00 / 0.50 / 1.0 |
| **sleepy** | **0.30** (half-lid) | capsule, `squint 0.50` | +5 (lowered) | flat | flat `−0.04` | 0 | fixed / settle to 0 | 1.00 / 0.12 / **0.5** |

### State-specific extras
- **idle** — gaze **wander**: retarget every `1.4–4.0 s` to a random point `gazeX ∈ ±0.40`, `gazeY ∈ ±0.28`; eased in (see gaze lerp). Breathing always on.
- **attentive / listening / speaking** — gaze **tracks** the live `gazeX/gazeY` target (or cursor in follow mode); wander disabled (decays to 0 at lerp 0.05/frame).
- **greeting** — **welcome bounce**: extra downward bob `max(0, sin(5·t)) · 0.10·shortestSide`, rate `5 rad/s` (~0.80 Hz), superimposed on breathing. Eyes render as upward ^_^ arc stroke (`width 6·S`, span `1.15·eyeWidth`), brows hidden.
- **listening** — **pulse ring** behind the face: radius `(44 + 4·sin(3.2·t))·S` = `(0.44 + 0.04·sin(3.2·t))·shortestSide`, centered `+0.06·shortestSide` below face center, stroke `0.025·shortestSide`, alpha `(0.18 + 0.12·sin(3.2·t)) · ring` (ring → 1 in this state).
- **thinking** — **"…" dots**: 3 accent dots near upper-right of right eye (anchor `eyeGap + 0.16·shortestSide` X, `eyeY − 0.30·shortestSide` Y), spacing `0.11·shortestSide`, radius `0.04·shortestSide`; staggered fade on cycle `phase = (1.6·t) mod 3`, per-dot alpha `clamp(1 − |phase − i|, 0.25, 1)`.
- **sleepy** — global `dim = 0.5` (dims all color + glow), breathing rate halved, blink disabled.
- **all states** — fixed eye **catchlight** (see A) and **breathing** (see C) keep the face alive.

> **Expression modifiers** (additive, optional) for reference:
> `happy` → mouthCurve +0.55, **squint +0.35** (a clean smiling squint — NOT a partial `eyeArc`, which would ghost a faint ^_^ over the open capsule; the full arc is greeting-only at `eyeArc 1`), browY −2 · `curious` → headTilt +0.12, browTilt +0.30 (asymmetric, raises one brow), browY −3, mouthCurve +0.10 · `surprised` → eyeScale +0.20, browY −9, mouthOpen +0.55, mouthCurve −0.15.

---

## C. Animation timing constants

| Behavior | Parameters |
|---|---|
| **Blink** | Interval: random **2.4 – 6.0 s** between blinks. Single blink duration **0.18 s** total, eased close-then-open as `sin(p·π)`, `p: 0→1` over the 0.18 s (fast symmetric close+open). ~0.25 s refractory guard before re-arming. **Disabled in `sleepy`.** A manual `blink` param (0..1) overrides and forces lids. |
| **Gaze smoothing** | Critically-damped exponential ease toward target each frame: `v += (target − v)·(1 − exp(−dt·k))`. `k_gaze = 9`. Eyelid open/close `k = 20`; mouthOpen `k = 22`; everything else `k = 9` (≈ 0.3 s settle). |
| **Gaze wander (idle)** | Retarget every **1.4 – 4.0 s**; amplitude `gazeX ±0.40`, `gazeY ±0.28`; decays to 0 at lerp `0.05`/frame when leaving idle. |
| **Breathing** | Vertical bob `sin(2π·t / period) · amplitude`. Period ≈ **5.7 s** (`2π / 1.1`); **doubles to ≈ 11.4 s** when `breath = 0.5` (sleepy). Amplitude **`0.05 · shortestSide`**. |
| **Expression / state transition** | No snapping — all pose values ease with `k = 9` (time constant ≈ 0.11 s, ~**0.3 s** to visually settle). |
| **Speaking lip-sync** | `mouthOpen = clamp( |0.5 + 0.32·sin(15·t) + 0.16·sin(8.3·t + 1)| · 0.7,  0.04,  1.0 )`. Primary osc **15 rad/s** (~2.39 Hz), secondary **8.3 rad/s** — layered for natural cadence. Effective open range ≈ **0.04 – 1.0**. Active in `speaking` state or when the Talking toggle is on. |
| **Greeting bounce** | `max(0, sin(5·t)) · 0.10·shortestSide` downward, rate **5 rad/s** (~0.80 Hz). |
| **Listening ring pulse** | radius `(0.44 + 0.04·sin(3.2·t))·shortestSide`; alpha `0.18 + 0.12·sin(3.2·t)`; **3.2 rad/s** (~0.51 Hz). |
| **Thinking "…" dots** | cycle `phase = (1.6·t) mod 3`; per-dot alpha `clamp(1 − |phase − i|, 0.25, 1)`, `i = 0,1,2`. |

`t` is elapsed seconds; `dt` is per-frame delta (clamped ≤ 0.05 s). All eases are
frame-rate independent via the `1 − exp(−dt·k)` form.
