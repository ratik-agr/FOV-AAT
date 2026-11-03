# AGENTS.md

SPICE design project: Static CMOS 2-to-4 Line Decoder with Enable (36 transistors).
Deliverables: `decoder_healthy.sp` (healthy) and `decoder_dft_sa0.sp` (SA0 fault on N3), both at repo root. Both are complete and verified — read them before editing.

## Environment

- Ngspice 42 at `/usr/bin/ngspice`. Run: `ngspice -b <file>.sp` (`.meas` results print to stdout; grep for them, e.g. `ngspice -b x.sp 2>&1 | grep -E "tpd|p_avg|v_il"`).
- **No PTM / model library exists on this system.** Every `.sp` must embed its own `.model` cards.
- Implemented choice: inline **level-1** models `NN`/`NP` (VTO ±0.45, KP 120U/40U, TOX=2N, LAMBDA 0.05/0.06).
  - `NFS` is **not** a level-1 parameter — ngspice prints `unrecognized parameter (nfs) - ignored`. Don't add it.
  - Don't duplicate a parameter across continuation lines (`CJ=...` twice warns).

## Technology & sizing (exact — do not deviate)

- $V_{DD} = 1.0V$, $L = 45nm$ everywhere, minimum $W_n = 90nm$.

| Cell | Devices | Sizing |
|---|---|---|
| inverter `inv` | 2 | $W_p = 180nm$, $W_n = 90nm$ |
| 3-input NAND `nand3` | 6 | 3 PMOS parallel $W_p = 180nm$; 3 NMOS series $W_n = 270nm$ (sized up for stack resistance) |

Count check: 6 `inv` (12) + 4 `nand3` (24) = 36 transistors.

## Decoder structure (`decoder2x4`)

Inputs `EN, A1, A0` → outputs `Y3..Y0`. The `N` node index matches the `Y` index it drives.

1. Two `inv`: `A1 → A1_bar`, `A0 → A0_bar`.
2. Four `nand3` → `N0..N3` — input assignment is the easy thing to get backwards:
   - `N0`: `EN, A1_bar, A0_bar`   - `N2`: `EN, A1, A0_bar`
   - `N1`: `EN, A1_bar, A0`       - `N3`: `EN, A1, A0`
3. Four `inv`: `N3→Y3, N2→Y2, N1→Y1, N0→Y0`. Hence `Y3=EN.A1.A0`, `Y2=EN.A1.A0'`, `Y1=EN.A1'.A0`, `Y0=EN.A1'.A0'`.

## Stimulus (implemented, verified)

PULSE sources, 20 ns per pattern, one full 8-pattern cycle = 160 ns, two cycles = 320 ns (`tran 2p 320n`).
- `EN`  PULSE(0 1 0 0.1n 0.1n 80n 160n) → **HIGH in the first half** [0,80) i.e. slots 0–3; A0 rises every 40 ns; A1 every 80 ns.
- Enabled slots: 0=`111`→Y3, 1=`110`→Y2, 2=`101`→Y1, 3=`100`→Y0; slots 4–7 have EN=0 (all outputs 0).
- `t_pd` therefore uses A0 `rise=2` (t≈40.05 ns, EN=1) → Y1. Measured ≈ **176 ps**.
- Truth table is proven with compact `meas tran tt_yX find v(YX) at=<slot mid>` spot checks — **do not add `wrdata` on the transient** (writes a 35 MB file).

## Measurements & gotchas (hard-earned)

- **Power:** source is named exactly `V_DD`. `meas tran I_avg avg i(V_DD) from=160n to=320n` is negative (SPICE current flows into the source's + terminal), so flip sign: `let P_avg = -I_avg * 1.0`. Measured ≈ **62 pW** (outputs unloaded).
- **Derivative noise-margin trap:** ngspice cannot evaluate `deriv()` inline in a `.meas WHEN`. Materialise it first: `let dv = deriv(v(Y1))` then `meas dc V_IL find v(A0) when dv=-1 cross=1`.
- **But `deriv(Y1) = -1` does not exist for the specified bias.** With `EN=1, A1=0` the A0→Y1 path is a **buffer** (`Y1 = A0`), so its slope is never negative. The two spec-literal `v_il`/`v_ih` lines in `decoder_healthy.sp` are kept to document this and report "no crossing". The valid numbers come from the *inverting* transfers of the same input: `v(Y0)` (`Y0=A0'`, V_IL/V_IH ≈ 480/510 mV) and subckt node `v(xdec.n1)` (`=A0'`, ≈ 464/500 mV).
- **Subcircuit nodes:** internal nodes must be addressed as `xdec.<node>` (e.g. `v(xdec.n1)`), never bare `v(N1)`.

## DFT file (`decoder_dft_sa0.sp`)

- Fault: N3 stuck-at-0, injected cleanly by (a) renaming the faulted NAND's output to `N3_floating` (inert) and (b) clamping N3 with `V_SA0 N3 0 dc 0`. No driver contention, no extra transistor.
- **`N3` is exposed as a test-access port** of `decoder2x4` in this file so the top-level clamp lands on the node the Y3 inverter actually sees. (A top-level `V_SA0` on `N3` while the subckt kept `xdec.n3` internal leaves the real node floating — that bug produced plausible-but-wrong numbers.)
- `N3_floating` holds the **fault-free** gate output, giving a self-contained proof: sensitizing vector `EN=1,A1=0,A0=0` → `N3_floating=1` (healthy Y3=0) vs faulty Y3=1 → **DETECTED**; masking vector `EN=1,A1=1,A0=1` → `N3_floating=0` (healthy Y3=1) vs faulty Y3=1 → **MASKED**. The masking vector must not be presented as a test.
- Stimulus sources carry both `dc` levels (for the DC fault test, switched by `alter V_xx dc=`) and the same PULSE waveform as the healthy file.

## Conventions

- Write real SPICE code only — no placeholders.
- Keep both netlists in sync: the DFT file is the healthy netlist plus the N3 fault/test vector. Changes to one must be mirrored.
