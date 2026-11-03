* =====================================================================
* decoder_healthy.sp  --  Static CMOS 2-to-4 Line Decoder with Enable
* HEALTHY version (reference / golden netlist)
*
* Specification
*   Inputs   : EN, A1, A0
*   Outputs  : Y3, Y2, Y1, Y0   (active high, enabled outputs)
*   VDD      : 1.0 V
*   Device count : 36 transistors
*                 6 x inv  (12 transistors)
*                 4 x nand3(24 transistors)
*   Technology : 45 nm rule set, level-1 MOSFET models embedded below
*                 (self-contained: no external .include / model library)
*
* Structure
*   A1 -> inv -> A1_bar      A0 -> inv -> A0_bar
*   N0 = NAND3(EN, A1_bar, A0_bar)
*   N1 = NAND3(EN, A1_bar, A0)
*   N2 = NAND3(EN, A1,      A0_bar)
*   N3 = NAND3(EN, A1,      A0)
*   Y3 = inv(N3)  Y2 = inv(N2)  Y1 = inv(N1)  Y0 = inv(N0)
*   => Y3 = EN.A1.A0   Y2 = EN.A1.A0'   Y1 = EN.A1'.A0   Y0 = EN.A1'.A0'
*
* Sizing (all devices L = 45 nm)
*   inv  : PMOS W = 180 nm, NMOS W =  90 nm
*   nand3: 3 PMOS in parallel W = 180 nm
*          3 NMOS in series   W = 270 nm (up-sized for stack resistance)
*
* Run:  ngspice -b decoder_healthy.sp
* =====================================================================

.title Static CMOS 2-to-4 Line Decoder with Enable - HEALTHY

.options reltol=1e-4 vntol=1e-6 abstol=1e-12 chgtol=1e-14

* ---------------------------------------------------------------------
* Embedded 45 nm-style level-1 models (no external library available)
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
*   PMOS: 3 in parallel (any one low input pulls the output high)
*   NMOS: 3 in series (all three high required to pull the output low)
*   Series order: input 'c' sits closest to the output so that the
*   fastest switching input sees the least stack resistance.
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
.subckt decoder2x4 EN A1 A0 Y3 Y2 Y1 Y0 vdd gnd
XinvA1 A1 A1_bar vdd gnd inv
XinvA0 A0 A0_bar vdd gnd inv

Xnand0 N0 EN A1_bar A0_bar vdd gnd nand3
Xnand1 N1 EN A1_bar A0      vdd gnd nand3
Xnand2 N2 EN A1      A0_bar vdd gnd nand3
Xnand3 N3 EN A1      A0      vdd gnd nand3

XinvY3 N3 Y3 vdd gnd inv
XinvY2 N2 Y2 vdd gnd inv
XinvY1 N1 Y1 vdd gnd inv
XinvY0 N0 Y0 vdd gnd inv
.ends decoder2x4

* ---------------------------------------------------------------------
* Testbench
* ---------------------------------------------------------------------
* Supply: the source name is exactly V_DD -- the power measurement
* below refers to i(V_DD) by that exact name.
V_DD vdd 0 dc 1.0

* Pulsed stimulus walking all 8 input combinations.
* One pattern every 20 ns, one full 8-pattern cycle every 160 ns.
*   slot :  0    1    2    3    4    5    6    7
*   time : [0,20)[20,40)[40,60)[60,80)[80,100)[100,120)[120,140)[140,160)
*   EN   :  1    1    1    1    0    0    0    0
*   A1   :  1    1    0    0    1    1    0    0
*   A0   :  1    0    1    0    1    0    1    0
V_A0 A0 0 PULSE(0 1 0     0.1n 0.1n 20n  40n)
V_A1 A1 0 PULSE(0 1 0     0.1n 0.1n 40n  80n)
V_EN EN 0 PULSE(0 1 0     0.1n 0.1n 80n 160n)

Xdec EN A1 A0 Y3 Y2 Y1 Y0 vdd 0 decoder2x4

.control
set filetype=ascii
set noaskquit

* ---------------- 1) Transient analysis ----------------------------
* 2 ps resolution over two 160 ns cycles.
tran 2p 320n

* Truth-table spot checks, one per triggered slot (EN=1 in slots 0..3):
*   slot0 EN=1,A1=1,A0=1 -> Y3=1   slot1 EN=1,A1=1,A0=0 -> Y2=1
*   slot2 EN=1,A1=0,A0=1 -> Y1=1   slot3 EN=1,A1=0,A0=0 -> Y0=1
*   slot4 EN=0           -> all outputs 0
meas tran tt_y3 find v(Y3) at=10n
meas tran tt_y2 find v(Y2) at=30n
meas tran tt_y1 find v(Y1) at=50n
meas tran tt_y0 find v(Y0) at=70n
meas tran tt_off find v(Y3) at=90n

* ---------------- 2) Propagation delay ----------------------------
* A0 rising edge #2 (t = 40 ns, EN = 1, A1 = 0) -> Y1 rising edge.
meas tran tpd_a0_y1 trig v(A0) val=0.5 rise=2 targ v(Y1) val=0.5 rise=1

* ---------------- 3) Average power --------------------------------
* Average supply current over exactly one full 160 ns cycle (second
* cycle, so the initial settling transient is excluded).
* SPICE convention: current into the + terminal of a source is
* positive, so the supply delivers current as a negative value.
meas tran I_avg avg i(V_DD) from=160n to=320n
let P_avg = -I_avg * 1.0
print P_avg

* ---------------- 4) DC analysis / noise margin --------------------
* Sweep A0 from 0 to 1.0 V with EN = 1 and A1 = 0 held.  V_IL / V_IH
* are the A0 levels where the unity-gain (slope = -1) criterion holds.
alter V_EN dc=1
alter V_A1 dc=0
dc V_A0 0 1.0 0.01

* The derivative MUST be materialised as a discrete vector first --
* ngspice refuses deriv() evaluated inline inside a .meas WHEN clause.
*
* Transfer polarity note: with EN=1, A1=0 the specified A0 -> Y1 path
* is a BUFFER (Y1 = EN.A1'.A0 = A0), so d(Y1)/d(A0) is never negative
* and slope = -1 does not exist on Y1.  These two lines are kept to
* document that behaviour: ngspice reports "no crossing" and carries on.
let dv = deriv(v(Y1))
meas dc V_IL     find v(A0) when dv=-1 cross=1
meas dc V_IH     find v(A0) when dv=-1 cross=2

* Noise margin on the INVERTING transfers of the same input A0:
*   Y0      = EN.A1'.A0' = A0'    (decoder output that inverts A0)
*   xdec.n1 = NAND(1,1,A0) = A0'  (first stage of the Y1 path)
let dv0 = deriv(v(Y0))
meas dc V_IL_y0 find v(A0) when dv0=-1 cross=1
meas dc V_IH_y0 find v(A0) when dv0=-1 cross=2
let dvn = deriv(v(xdec.n1))
meas dc V_IL_n1 find v(A0) when dvn=-1 cross=1
meas dc V_IH_n1 find v(A0) when dvn=-1 cross=2

wrdata dc_healthy.txt v(A0) v(Y1) v(Y0) v(xdec.n1) dv dv0 dvn
.endc

.end
