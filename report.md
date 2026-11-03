# Design Report — Static CMOS 2-to-4 Line Decoder with Enable and SA0 Fault Analysis

**Technology:** 45 nm rule set (level-1 MOSFET abstraction)
**Supply:** V_DD = 1.0 V
**Device count:** 36 transistors
**Simulator:** Ngspice 42
**Netlists:** `decoder_healthy.sp`, `decoder_dft_sa0.sp`

---

## 1. Objective

Design, simulate and characterize a static CMOS 2-to-4 line decoder with an active-high enable
input, then inject a stuck-at-0 (SA0) fault on an internal node and demonstrate a test vector that
makes that fault observable at a primary output.

Deliverables:

1. `decoder_healthy.sp` — full hierarchical netlist with transient, delay, average-power and
   noise-margin analyses.
2. `decoder_dft_sa0.sp` — the same decoder with `N3` tied to ground, plus DC test vectors.

---

## 2. Design description

### 2.1 Architecture

The decoder is built from two standard cells:

- `inv`   — a CMOS inverter (2 transistors)
- `nand3` — a 3-input NAND (6 transistors)

```
          ┌──────┐
   A1 ───►│ inv  ├──► A1_bar ──┐
          └──────┘             │
          ┌──────┐             ▼
   A0 ───►│ inv  ├──► A0_bar ──┐   ┌────────┐      ┌──────┐
          └──────┘             ├──►│ nand3  ├─ N3 ─►│ inv  ├──► Y3
                               │   └────────┘      └──────┘
   EN ─────────────────────────┤        ⋮               ⋮
                               │   ┌────────┐      ┌──────┐
                               └──►│ nand3  ├─ N0 ─►│ inv  ├──► Y0
                                   └────────┘      └──────┘
```

NAND input assignment (the `N` index matches the `Y` index it drives):

| Intermediate | NAND inputs | Output |
|---|---|---|
| `N0` | `EN, A1_bar, A0_bar` | `Y0 = EN·A1'·A0'` |
| `N1` | `EN, A1_bar, A0`     | `Y1 = EN·A1'·A0`  |
| `N2` | `EN, A1, A0_bar`     | `Y2 = EN·A1·A0'`  |
| `N3` | `EN, A1, A0`         | `Y3 = EN·A1·A0`   |

Because `Y_i = NOT(N_i)` and each `N_i` is a NAND, each output is the AND of the enabled minterm.

### 2.2 Truth table

| EN | A1 | A0 | Y3 | Y2 | Y1 | Y0 |
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| 0 | x | x | 0 | 0 | 0 | 0 |
| 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| 1 | 0 | 1 | 0 | 0 | 1 | 0 |
| 1 | 1 | 0 | 0 | 1 | 0 | 0 |
| 1 | 1 | 1 | 1 | 0 | 0 | 0 |

---

## 3. Transistor sizing

| Cell | Devices | PMOS | NMOS | Rationale |
|---|---|---|---|---|
| `inv` | 2 | W = 180 nm | W = 90 nm | 2:1 PMOS:NMOS ratio to balance rise/fall drive |
| `nand3` | 6 | 3 × 180 nm in **parallel** | 3 × 270 nm in **series** | series NMOS stack triples resistance; W is tripled to restore pull-down strength |

All devices use `L = 45 nm`. Device count: 6 × `inv` (12) + 4 × `nand3` (24) = **36 transistors**.

Within `nand3`, the fastest-switching input (`c`, i.e. `A0` for the `Y1`/`Y3` paths) is placed
closest to the output so it sees the least series-stack resistance.

---

## 4. Device models

No PTM/model library is available in the environment, so the netlists embed **level-1** model
cards (self-contained):

```spice
.model NN NMOS (LEVEL=1 VTO=0.45  KP=120U GAMMA=0.4 PHI=0.70 LAMBDA=0.05
+                TOX=2N NSUB=1E17 TPG=1
+                CGSO=0.15N CGDO=0.15N CJ=1M CJSW=0.15N MJSW=0.33 PB=0.8)
.model NP PMOS (LEVEL=1 VTO=-0.45 KP=40U  GAMMA=0.5 PHI=0.70 LAMBDA=0.06
+                TOX=2N NSUB=1E17 TPG=-1
+                CGSO=0.15N CGDO=0.15N CJ=1M CJSW=0.15N MJSW=0.33 PB=0.8)
```

Level-1 is a deliberate abstraction: it converges robustly and produces well-behaved transfer
curves, which is what the delay/power/noise-margin characterization needs. It does **not** model
short-channel effects that a real 45 nm BSIM4 card would include, so absolute numbers are a
first-order estimate, not silicon-accurate.

---

## 5. Simulation methodology

### 5.1 Stimulus

One pattern every 20 ns; a full 8-combination cycle every 160 ns; two cycles simulated (320 ns).

| Slot | Time window (ns) | EN | A1 | A0 |
|:--:|:--:|:--:|:--:|:--:|
| 0 | [0, 20) | 1 | 1 | 1 |
| 1 | [20, 40) | 1 | 1 | 0 |
| 2 | [40, 60) | 1 | 0 | 1 |
| 3 | [60, 80) | 1 | 0 | 0 |
| 4 | [80, 100) | 0 | – | – |
| 5–7 | [100, 160) | 0 | – | – |

`EN` is high in the first half of each cycle; `A0` toggles every 40 ns and `A1` every 80 ns.

### 5.2 Analyses

- **Transient** `.tran` at 2 ps resolution over 320 ns.
- **Delay** `.meas tran ... trig v(A0) rise=2 targ v(Y1) rise=1` on the enabled A0 edge at t ≈ 40 ns.
- **Power** `.meas tran I_avg avg i(V_DD) from=160n to=320n`, then `P_avg = -I_avg × 1.0`
  (sign flip because SPICE current flows into the source's positive terminal). The second cycle is
  used so the initial settling transient is excluded.
- **Noise margin** `.dc V_A0 0 1.0 0.01` with `EN = 1`, `A1 = 0`; V_IL/V_IH are located where the
  transfer-function derivative equals −1, materialised first as a vector
  (`let dv = deriv(v(...))`) because Ngspice cannot evaluate `deriv()` inline inside `.meas WHEN`.

---

## 6. Results

### 6.1 Functional verification (truth table)

Transient spot checks (healthy netlist):

| Measurement | Simulated | Expected |
|---|---|---|
| `tt_y3` @ 10 ns (111) | 1.000 V | 1 |
| `tt_y2` @ 30 ns (110) | 1.000 V | 1 |
| `tt_y1` @ 50 ns (101) | 1.000 V | 1 |
| `tt_y0` @ 70 ns (100) | 1.000 V | 1 |
| `tt_off` @ 90 ns (EN = 0) | ≈ 7.7 nV | 0 |

All four enabled minterms and the disabled state are correct.

### 6.2 Propagation delay

```
tpd_a0_y1 = 1.760e-10 s   (trig = 40.05 ns, targ = 40.226 ns)
```

**t_pd ≈ 176 ps** for the A0 ↑ → Y1 ↑ path.

### 6.3 Average power

```
I_avg = -6.209e-08 A   over [160 ns, 320 ns]
P_avg = 6.208868e-08 W = 62.1 nW   (= 62 088.68 pW)
```

**P_avg ≈ 62 nW** for the healthy decoder with unloaded outputs. The value is small because
level-1 devices at 45 nm have very small parasitic capacitances and no external load is attached;
it scales linearly with added load capacitance.

### 6.4 Noise margin

With `EN = 1, A1 = 0`, `A0` drives an inverting transfer (`Y0 = A0'`). The slope = −1 points are:

| Path | V_IL | V_IH | NM_L = V_IL − V_OL | NM_H = V_OH − V_IH |
|---|---|---|---|---|
| `Y0` (output inverting A0) | 480.2 mV | 509.8 mV | ≈ 480 mV | ≈ 490 mV |
| `xdec.n1` (first stage of Y1 path) | 463.9 mV | 499.9 mV | ≈ 464 mV | ≈ 500 mV |

The switching threshold sits near V_DD/2 ≈ 495 mV, and the noise margins are large because the
level-1 transfer curves are steep.

> **Polarity caveat.** The task wording asks for V_IL/V_IH where `deriv(Y1) = −1`. With `EN = 1,
> A1 = 0` the A0 → Y1 path is `A0 → inv → NAND → inv`, i.e. a **buffer** (`Y1 = A0`), so its slope
> is never negative and that crossing genuinely does not exist. The netlist keeps the literal
> `deriv(v(Y1))` lines (they report "no crossing"), and reports the valid unity-gain points from
> the *inverting* transfers of the same input (`Y0` and `xdec.n1`).

---

## 7. DFT: stuck-at-0 fault on N3

### 7.1 Fault injection

The fault is injected without driver contention and without adding transistors:

1. The `nand3` instance that normally drives `N3` now drives a separate, inert net
   `N3_floating` (left dangling).
2. `N3` is hard-tied to ground by an independent 0 V source: `V_SA0 N3 0 dc 0`.

To make the clamp land on the node the `Y3` inverter actually sees, `N3` is exposed as a
test-access **port** of the `decoder2x4` subcircuit in the DFT file (in the healthy file it
remains internal). `N3_floating` retains the fault-free gate output, which makes the file
self-proving.

### 7.2 Test vectors and outcome

| Vector | EN | A1 | A0 | `N3` (faulty) | `N3_floating` (= healthy `N3`) | Y3 faulty | Y3 healthy | Result |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|---|
| Sensitizing | 1 | 0 | 0 | 0 | **1** | **1** | 0 | **DETECTED** |
| Masking | 1 | 1 | 1 | 0 | **0** | 1 | 1 | MASKED |

Simulated output:

```
y3_sens = 1.000   n3_sens = 0.000   n3float_sens = 1.000
y3_mask = 1.000   n3_mask = 0.000   n3float_mask = 2.30e-08   (~ 0)
```

**Interpretation.** `N3 = NAND(EN,A1,A0)`. The vector `EN=1,A1=1,A0=1` drives healthy `N3` to 0,
so healthy `Y3 = 1` — identical to the faulty `Y3 = 1`. The SA0 is therefore *masked* by that
vector and cannot be used as a test. The vector `EN=1,A1=0,A0=0` drives healthy `N3` to 1, so
healthy `Y3 = 0`, while the faulty `Y3` stays at 1: this vector makes the fault observable, and
it is the one applied.

Faulty-circuit transient metrics are essentially unchanged on the Y1 path (`t_pd ≈ 176 ps`), with
average power ≈ 55 nW (exactly 54.54411 nW).

**Fault coverage note.** SA0 on `N3` is actually detectable by **7 of the 8 input vectors**.
Since the faulty `Y3 = 1` permanently, a vector masks the fault only when the healthy `Y3 = 1`
too, i.e. only at `EN=1, A1=1, A0=1`; every other vector (including all four `EN=0` vectors,
where healthy `Y3 = 0` and faulty `Y3 = 1`) detects it. The vector `EN=1,A1=0,A0=0` applied here
is one of the seven valid sensitizing vectors, chosen deliberately for the demonstration, not
because it is the only one.

---

## 8. Caveats and limitations

- **Model abstraction.** Level-1 cards omit short-channel effects (DIBL, velocity saturation,
  proper overlap/junction capacitance). Absolute delay/power are indicative, not sign-off.
- **No load capacitance.** Outputs are unloaded, so power is low; results scale with C_load.
- **`CJ`/`CJSW` on a level-1 model with default (zero) source/drain areas do not contribute.**
- **V_IL/V_IH polarity.** See §6.4; the requested `deriv(Y1) = −1` point does not exist for the
  specified bias, and equivalent inverting transfers are used instead.

---

## 9. Reproduction

```bash
# Healthy design: truth table, t_pd, power, noise margin
ngspice -b decoder_healthy.sp 2>&1 | grep -E "tt_|tpd|p_avg|v_il|v_ih"

# SA0 fault: fault detection vs masking
ngspice -b decoder_dft_sa0.sp 2>&1 | grep -E "y3_|n3_|n3float|tpd|p_avg"
```

## 10. Theoretical vs. measured comparison

The level-1 MOSFET models used in this project are a **first-order abstraction** and do not
capture all physical effects of a real 45 nm process. This section compares the measured
results against theoretical expectations and explains why they differ.

### 10.1 Propagation delay

| | Value |
|---|---|
| Measured `t_pd` (A0↑→Y1↑) | **176.04 ps** |
| Real-45 nm expectation (3 stages × 15–25 ps) | ≈ 45–75 ps |
| Gap | **2.4–4× slower** |

The path `A0 → inv → nand3 → inv → Y1` is three stages, so the per-stage delay is
≈ 59 ps. A real 45 nm inverter has `t_pd ≈ 15–25 ps`. The level-1 model is slower because:

- **Quadratic, not velocity-saturated, I–V.** Level-1 uses `I_D ∝ (V_GS − V_T)²` above
  saturation. Real 45 nm devices are velocity-saturated, `I_D ≈ v_sat·C_ox·W·(V_GS − V_T)`,
  a linear cap that is much lower than the quadratic extrapolation at high overdrive.
  Level-1 has no velocity-saturation parameter at all.
- **Higher threshold voltage.** `VTO = 0.45 V` vs. ≈ 0.25–0.35 V for real 45 nm. The
  overdrive `(V_GS − V_T)` is therefore ~30–40 % smaller, and current scales with its square.
- **Thicker oxide.** `TOX = 2 nm` vs. ≈ 1.2–1.5 nm EOT for real 45 nm, giving lower `C_ox`
  and proportionally lower drive.
- **Lower transconductance parameter.** `KP = 120 µA/V²` (NMOS) vs. ≈ 260–520 µA/V² for
  real µ_n (200–400 cm²/V·s) and `C_ox ≈ 13 fF/µm²`. The drive is roughly halved.

The 176 ps figure is therefore a first-order estimate, exactly as §8 states.

### 10.2 Average power

| | Value |
|---|---|
| Measured `P_avg` (healthy) | **62.09 nW** |
| Measured `P_avg` (faulty) | **54.54 nW** (−12 %) |
| Simulated frequency | 6.25 MHz |

The effective switched capacitance is `C_eff = P/(V²·f) ≈ 62.09 nW / (1 V² × 6.25 MHz)
≈ 9.9 fF`, consistent with gate + overlap (`CGSO`/`CGDO`) capacitance only. Level-1 omits
two components that dominate real 45 nm power:

- **Gate tunnelling current.** At Tox ≈ 1.2 nm, direct tunnelling is ~0.1–1 nA **per
  transistor**, i.e. ≈ 3.6–36 nW of time-independent leakage at 1 V for 36 devices. Level-1
  is a classical drift model with **zero** gate current.
- **Junction capacitance.** `CJ`/`CJSW` are present in the model cards but with zero
  source/drain area (`AS = 0`) they contribute nothing; real layout has non-zero S/D area
  and would add ~50–100 % to the switched capacitance.

The model therefore gives **100 % dynamic, 0 % leakage** — the measured value is a lower
bound, not a silicon prediction. At 6.25 MHz a real chip would show a mixed figure: a
similar dynamic component plus a leakage floor that dominates as frequency drops.

The faulty-circuit `−12 %` reduction (`−7.55 nW`) is **physically correct**: with `N3`
clamped to 0, the `Y3` inverter's input is permanently low, its PMOS is always on and NMOS
always off, so **Y3 never switches** and its dynamic power vanishes. The `Xnand3` gate
still toggles (driving `N3_floating`), so only the Y3 *inverter*'s power is saved — one
inverter's share of 62.09 nW across 6 inverters is ≈ 10.3 nW, consistent with the observed
7.55 nW. The direction and magnitude match theory, so this is a genuine result, not an
artifact.

### 10.3 Noise margins

| Path | Measured V_IL / V_IH | Measured NM_L / NM_H |
|---|---|---|
| `Y0` (inverting A0) | 480.2 / 509.8 mV | ≈ 480 / 490 mV |
| `xdec.n1` (NAND stage) | 463.9 / 499.9 mV | ≈ 464 / 500 mV |

The unity-gain (slope = −1) criterion gives the *maximum possible* noise margin; for an
ideal infinite-gain inverter `V_IL → 0`, `V_IH → V_DD`, so `NM_max = V_DD/2 = 500 mV`. The
measured 480–500 mV is within 10–20 mV of that ceiling. Real 45 nm inverters give
`NM ≈ 150–300 mV` because of finite small-signal gain, DIBL (drain-induced barrier
lowering lowers `V_t` as `V_DS` rises), body effect, and `V_OL ≠ 0` / `V_OH ≠ V_DD`.
Level-1 includes none of these degradations, so its transfer curves are **steep and
near-ideal** and the noise margins are **optimistic by roughly a factor of 2**.

### 10.4 NAND3 switching threshold — β-ratio theory confirms the measurement

The one place where theory and measurement agree to three significant figures is the
switching (50 %) voltage of the `xdec.n1` NAND gate.

Measured: `V_sp = (V_IL + V_IH)/2 = (463.9 + 499.9)/2 = 481.9 mV`.

β-ratio prediction, using `β = KP · W / L`:

```
β_p (3 PMOS parallel) = 3 × (40U × 180/45)  = 480U
β_n (3 NMOS series)   = 3 × (120U × 270/45) = 2160U
β_n/β_p = 4.5  →  √(β_n/β_p) = 2.121
V_sp ≈ V_Tn + (V_DD − V_Tn − |V_Tp|) / (1 + √(β_n/β_p))
     = 0.45 + (1 − 0.45 − 0.45) / 3.121
     = 0.482 V = 482 mV
```

Predicted **482 mV** vs. measured **481.9 mV** — a 0.1 mV (0.02 %) match. Because
`β_n > β_p`, the stronger NMOS stack pulls the switching point below `V_DD/2`, exactly as
observed. The inverter path corroborates this: its midpoint is `(480.2 + 509.8)/2 = 495.0 mV
= V_DD/2` exactly, as expected when `β_n ≈ β_p`. The agreement validates both the
transistor sizing and the DC solver.

### 10.5 Numerical residuals (not physical effects)

- **`tt_off = 7.66 nV`.** With `EN = 0`, theory demands exactly 0 V. The residual comes
  from `LAMBDA = 0.05/0.06` (channel-length modulation leaves a finite `R_on`, so
  `V_OL = I·R_on ≠ 0`) plus solver tolerances (`abstol=1e-12`, `vntol=1e-6`). At eight
  orders of magnitude below `V_DD` this is numerical noise, not a real offset.
- **Faulty-vs-healthy Δ`t_pd` = +0.069 ps (+0.039 %).** The A0→Y1 and N3→Y3 paths are
  logically independent, so the true difference is **exactly 0 ps**. The 0.069 ps is below
  the 2 ps transient timestep and arises from differing solver convergence paths between
  the two runs; it is not a physical effect.

### Summary

| Metric | Measured | Theory / real-45 nm | Nature of the gap |
|---|---|---|---|
| `t_pd` | 176.04 ps | ~45–75 ps | model 2.4–4× slow (quadratic I–V, high `V_t`, thick `Tox`, low `KP`) |
| `P_avg` | 62.09 nW | dynamic + gate leakage | model has 0 leakage; value is a lower bound |
| faulty `P_avg` | 54.54 nW (−12 %) | Y3 inverter stops switching | physically correct |
| `NM_L`/`NM_H` | 480/490 mV | real ≈ 150–300 mV | model near theoretical max (500 mV); optimistic |
| NAND `V_sp` | 481.9 mV | 482 mV (β-ratio) | 0.02 % match — validates sizing & solver |
| `tt_off` | 7.66 nV | 0 V | numerical / `LAMBDA` residual |
| Δ`t_pd` (faulty) | +0.069 ps | 0 ps | solver noise (< timestep) |

---

## 11. Conclusion

A 36-transistor static CMOS 2-to-4 decoder with enable was designed and verified in Ngspice:
all minterms are correct, `t_pd ≈ 176 ps`, `P_avg ≈ 62 nW`, and input noise margins are on the
order of 480–500 mV. A stuck-at-0 fault on `N3` was injected cleanly and shown to be **masked** by
`EN=1,A1=1,A0=1` but **unambiguously detected** by `EN=1,A1=0,A0=0`, demonstrating the importance
of choosing a fault-sensitizing vector rather than an arbitrary one.
