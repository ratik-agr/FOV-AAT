# FOV-AAT — Static CMOS 2-to-4 Line Decoder with Enable

A hierarchical Ngspice design of an active-high **2-to-4 line decoder with enable** in a 45 nm
rule set (V_DD = 1.0 V, 36 transistors), together with a **DFT version** carrying an injected
**stuck-at-0 (SA0)** fault on the internal node `N3`.

## Files

| File | Description |
|---|---|
| `decoder_healthy.sp` | Golden/reference netlist: decoder + transient, delay, power and noise-margin measurements |
| `decoder_dft_sa0.sp` | Same decoder with `N3` stuck at 0, plus DC test vectors proving the fault is observable |
| `report.md` | Engineering report: design, methodology, and measured results |
| `AGENTS.md` | Notes for AI coding agents working in this repo (getchas, exact commands) |
| `dc_healthy.txt` | Generated DC-sweep evidence (A0 sweep, V(Y1), V(Y0), V(N1), derivatives) |

Both `.sp` netlists are **self-contained**: the 45 nm-level MOSFET model cards are embedded, so no
external model library is required.

## Running

```bash
ngspice -b decoder_healthy.sp
ngspice -b decoder_dft_sa0.sp
```

Filter the meaningful results (Ngspice prints them to stdout):

```bash
ngspice -b decoder_healthy.sp 2>&1 | grep -E "tt_|tpd|p_avg|v_il|v_ih"
ngspice -b decoder_dft_sa0.sp 2>&1 | grep -E "y3_|n3_|n3float"
```

## Design at a glance

- **Inputs:** `EN`, `A1`, `A0`  •  **Outputs:** `Y3`, `Y2`, `Y1`, `Y0` (active high)
- **Logic:** `Y3 = EN·A1·A0`, `Y2 = EN·A1·A0'`, `Y1 = EN·A1'·A0`, `Y0 = EN·A1'·A0'`
- **Structure:** 2 inverters (address pre-drive) + 4 × 3-input NAND + 4 output inverters
- **Sizing:** `L = 45 nm`; inverter `Wp/Wn = 180/90 nm`; NAND3 `Wp = 180 nm` (×3 parallel),
  `Wn = 270 nm` (×3 series, up-sized for stack resistance)

## Verified results (Ngspice 42)

| Metric | Value |
|---|---|
| Propagation delay `t_pd` (A0 ↑ → Y1 ↑) | **176 ps** |
| Average power (one 160 ns cycle) | **62 pW** (healthy), 55 pW (faulty), unloaded outputs |
| V_IL / V_IH (A0 input) | **480 / 510 mV** (via `Y0 = A0'`) |
| Truth table | all 4 enabled outputs correct; all zero when `EN = 0` |
| SA0 on `N3` | **detected** by vector `EN=1,A1=0,A0=0`; **masked** by `EN=1,A1=1,A0=1` |

See `report.md` for the full discussion.
