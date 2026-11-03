* =====================================================================
* decoder_dft_sa0.sp  --  Static CMOS 2-to-4 Line Decoder with Enable
* DFT version: Stuck-At-0 (SA0) fault injected on internal node N3
*              (N3 = output of the NAND gate driving the Y3 inverter)
*
* This file is a duplicate of decoder_healthy.sp with exactly two
* changes, marked "SA0" below:
*   1) the NAND3 driving N3 writes to a separate floating net
*      (N3_floating) instead of N3
*   2) N3 is hard-tied to GND by V_SA0 (N3 0 dc 0)  => permanent SA0
*
* Fault injection is clean: the faulted gate is left connected to its
* own inert node (no driver contention, no extra transistor), and the
* node the rest of the logic actually sees (N3) is clamped low by an
* independent 0 V source.
*
* Design specs (unchanged from healthy):
*   Inputs : EN, A1, A0      Outputs : Y3, Y2, Y1, Y0
*   VDD = 1.0 V, 45 nm rule set, 36 transistors, level-1 models inline
*   Y3 = EN.A1.A0   Y2 = EN.A1.A0'   Y1 = EN.A1'.A0   Y0 = EN.A1'.A0'
*
* Fault observability:
*   N3 = NAND(EN,A1,A0)
*   Sensitizing vector  EN=1, A1=0, A0=0:
*       healthy : N3 = 1 -> Y3 = 0
*       faulty  : N3 = 0 -> Y3 = 1      <-- fault DETECTED
*   Masking vector      EN=1, A1=1, A0=1:
*       healthy : N3 = NAND(1,1,1) = 0 -> Y3 = 1
*       faulty  : N3 = 0               -> Y3 = 1
*       both Y3 = 1                     <-- fault MASKED
*
* Run:  ngspice -b decoder_dft_sa0.sp
* =====================================================================

.title Static CMOS 2-to-4 Line Decoder with Enable - SA0 fault on N3

.options reltol=1e-4 vntol=1e-6 abstol=1e-12 chgtol=1e-14

* ---------------------------------------------------------------------
* Embedded 45 nm-style level-1 models (self-contained netlist)
* ---------------------------------------------------------------------
.model NN NMOS (LEVEL=1 VTO=0.45  KP=120U GAMMA=0.4 PHI=0.70 LAMBDA=0.05
+                TOX=2N   NSUB=1E17   TPG=1
+                CGSO=0.15N CGDO=0.15N CJ=1M CJSW=0.15N MJSW=0.33 PB=0.8)
.model NP PMOS (LEVEL=1 VTO=-0.45 KP=40U  GAMMA=0.5 PHI=0.70 LAMBDA=0.06
+                TOX=2N   NSUB=1E17   TPG=-1
+                CGSO=0.15N CGDO=0.15N CJ=1M CJSW=0.15N MJSW=0.33 PB=0.8)

* ---------------------------------------------------------------------
* Subcircuit: inverter
* ---------------------------------------------------------------------
.subckt inv in out vdd gnd
Mp1 out in vdd vdd NP W=180n L=45n
Mn1 out in gnd gnd NN W=90n  L=45n
.ends inv

* ---------------------------------------------------------------------
* Subcircuit: 3-input NAND
*   PMOS: 3 in parallel (W = 180 nm) ; NMOS: 3 in series (W = 270 nm)
* ---------------------------------------------------------------------
.subckt nand3 out a b c vdd gnd
Mpa out a vdd vdd NP W=180n L=45n
Mpb out b vdd vdd NP W=180n L=45n
Mpc out c vdd vdd NP W=180n L=45n
Mna out c  n1  gnd NN W=270n L=45n
Mnb n1  b  n2  gnd NN W=270n L=45n
Mnc n2  a  gnd gnd NN W=270n L=45n
.ends nand3

* ---------------------------------------------------------------------
* Top level: decoder2x4
* ---------------------------------------------------------------------
* NOTE (DFT only): N3 is exposed as a test-access port so that the SA0
* clamp at the top level lands on the very node the Y3 inverter sees.
* The healthy netlist keeps N3 internal.
.subckt decoder2x4 EN A1 A0 Y3 Y2 Y1 Y0 N3 vdd gnd
XinvA1 A1 A1_bar vdd gnd inv
XinvA0 A0 A0_bar vdd gnd inv

Xnand0 N0 EN A1_bar A0_bar vdd gnd nand3
Xnand1 N1 EN A1_bar A0      vdd gnd nand3
Xnand2 N2 EN A1      A0_bar vdd gnd nand3
* --- SA0 fault #1: faulted gate no longer drives N3 ------------------
Xnand3 N3_floating EN A1 A0  vdd gnd nand3

XinvY3 N3 Y3 vdd gnd inv
XinvY2 N2 Y2 vdd gnd inv
XinvY1 N1 Y1 vdd gnd inv
XinvY0 N0 Y0 vdd gnd inv
.ends decoder2x4

* ---------------------------------------------------------------------
* Testbench
* ---------------------------------------------------------------------
V_DD vdd 0 dc 1.0

* --- SA0 fault #2: hard clamp N3 to GND (0 V source, no transistor) --
V_SA0 N3 0 dc 0

* Stimulus: each source carries a dc level (used by the DC fault test)
* and the same pulse waveform as the healthy netlist (used by the
* transient run, kept here so the two files stay duplicates).
V_A0 A0 0 dc 0 PULSE(0 1 0 0.1n 0.1n 20n  40n)
V_A1 A1 0 dc 0 PULSE(0 1 0 0.1n 0.1n 40n  80n)
V_EN EN 0 dc 0 PULSE(0 1 0 0.1n 0.1n 80n 160n)

Xdec EN A1 A0 Y3 Y2 Y1 Y0 N3 vdd 0 decoder2x4

.control
set filetype=ascii
set noaskquit

* ---------------- Transient (same as healthy netlist) --------------
tran 2p 320n
meas tran tpd_a0_y1 trig v(A0) val=0.5 rise=2 targ v(Y1) val=0.5 rise=1
meas tran I_avg avg i(V_DD) from=160n to=320n
let P_avg = -I_avg * 1.0
print P_avg

* ---------------- DC fault test #1: sensitizing vector --------------
* EN = 1, A1 = 0, A0 = 0  (healthy Y3 = 0, fault makes Y3 = 1)
alter V_EN dc=1
alter V_A1 dc=0
alter V_A0 dc=0
op
let Y3_sens = v(Y3)
let N3_sens = v(N3)
let N3float_sens = v(xdec.n3_floating)
print Y3_sens N3_sens N3float_sens

* ---------------- DC fault test #2: masking vector -----------------
* EN = 1, A1 = 1, A0 = 1  (healthy Y3 = 1, faulty Y3 = 1 -> masked)
alter V_EN dc=1
alter V_A1 dc=1
alter V_A0 dc=1
op
let Y3_mask = v(Y3)
let N3_mask = v(N3)
let N3float_mask = v(xdec.n3_floating)
print Y3_mask N3_mask N3float_mask

echo
echo "==================== SA0 fault on N3 ===================="
echo "sensitizing vector EN=1,A1=0,A0=0 : Y3 = (faulty) 1, healthy 0  -> DETECTED"
echo "masking     vector EN=1,A1=1,A0=1 : Y3 = (faulty) 1, healthy 1  -> MASKED"
echo "N3_floating shows the fault-free gate output for each vector."
echo "========================================================"
.endc

.end
