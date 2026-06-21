#!/usr/bin/env python3
"""
NurseryHub NodeBoard v2 — SVG Wiring Diagram Generator
Produces node_board_v2_diagram.html with clear per-section circuit diagrams.
"""
import os, sys, webbrowser
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ── SVG helpers ───────────────────────────────────────────────────────────────
BG    = "#0d1117"
C12V  = "#ff6b35"
C5V   = "#ffcc00"
C3V3  = "#44cc44"
CGND  = "#778899"
CREL  = "#ff8844"
CMST  = "#cc88ff"
CSDA  = "#66aaff"
CSCL  = "#4488ff"
CDHT  = "#ff88cc"
CSPI  = "#ffaa44"
CWIRE = "#aaaaaa"
CBOX  = "#161b22"
CBORD = "#30363d"
CTXT  = "#c9d1d9"
CDIM  = "#8b949e"
CHL   = "#58a6ff"
CGRN  = "#3fb950"
CYEL  = "#d29922"
CRED  = "#f85149"

def svg_open(w, h):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}" style="background:{BG};display:block;margin:0 auto">\n'
            '<defs>'
            f'<marker id="dot" markerWidth="4" markerHeight="4" refX="2" refY="2">'
            f'<circle cx="2" cy="2" r="1.8" fill="{CWIRE}"/></marker>'
            '</defs>\n')

def svg_close():
    return '</svg>\n'

def R(x,y,w,h,fill=CBOX,stroke=CBORD,rx=4,sw=1.5):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>\n'

def T(x,y,s,sz=11,fill=CTXT,anchor="middle",bold=False):
    fw = "bold" if bold else "normal"
    return f'<text x="{x}" y="{y}" font-size="{sz}" fill="{fill}" text-anchor="{anchor}" font-weight="{fw}" font-family="Consolas,monospace">{s}</text>\n'

def L(x1,y1,x2,y2,col=CWIRE,sw=2,dash=""):
    da = f'stroke-dasharray="{dash}"' if dash else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{sw}" {da}/>\n'

def PL(pts,col=CWIRE,sw=2,dash=""):
    da = f'stroke-dasharray="{dash}"' if dash else ""
    ps = " ".join(f"{x},{y}" for x,y in pts)
    return f'<polyline points="{ps}" stroke="{col}" stroke-width="{sw}" fill="none" {da}/>\n'

def DOT(x,y,col=CWIRE,r=4):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{col}"/>\n'

def JDot(x,y):   # junction dot on wire
    return f'<circle cx="{x}" cy="{y}" r="3.5" fill="{CWIRE}"/>\n'

def NetLabel(x,y,net,col=CWIRE,sz=9,anchor="middle"):
    return T(x,y,net,sz=sz,fill=col,anchor=anchor)

def CompBox(x,y,w,h,ref,desc,col=CHL):
    s = R(x,y,w,h)
    s += R(x,y,w,18,fill=col,stroke="none",rx=4)
    s += R(x,y+14,w,4,fill=col,stroke="none")
    s += T(x+w//2, y+13, ref, sz=10, fill="#fff", bold=True)
    s += T(x+w//2, y+h-5, desc, sz=8, fill=CDIM)
    return s

def Pin(x,y,col):
    return f'<circle cx="{x}" cy="{y}" r="3" fill="{col}"/>\n'

# ── Component drawing helpers ─────────────────────────────────────────────────

def draw_resistor(x, y, ref, val, w=70, h=34, col=CBORD):
    s = CompBox(x, y, w, h, ref, val, col="#2a3a2a")
    return s, x, y+h//2, x+w, y+h//2   # svg, left_x, left_y, right_x, right_y

def draw_diode(x, y, ref, val, ak_labels=True, w=80, h=38, hcol="#2a2a3a"):
    s = CompBox(x, y, w, h, ref, val, col=hcol)
    # Anode/Cathode labels
    if ak_labels:
        s += T(x+8,  y+h-5, "A", sz=8, fill=C3V3, anchor="start")
        s += T(x+w-8,y+h-5, "K", sz=8, fill=CRED,  anchor="end")
        s += T(x+8,  y+26,  "anode", sz=7, fill=C3V3, anchor="start")
        s += T(x+w-8,y+26,  "cathode", sz=7, fill=CRED,  anchor="end")
    return s, x, y+h//2, x+w, y+h//2

def draw_tvs(x, y, ref, val, w=90, h=38):
    s = CompBox(x, y, w, h, ref, val, col="#3a1a3a")
    s += T(x+8,  y+h-5, "K→signal", sz=7, fill=CMST, anchor="start")
    s += T(x+w-8,y+h-5, "A→GND", sz=7, fill=CGND,  anchor="end")
    return s, x, y+h//2, x+w, y+h//2

def draw_cap(x, y, ref, val, w=60, h=34):
    s = CompBox(x, y, w, h, ref, val, col="#2a2a1a")
    return s, x, y+h//2, x+w, y+h//2

def draw_led(x, y, ref, col_desc, w=65, h=34):
    s = CompBox(x, y, w, h, ref, col_desc, col="#1a2a3a")
    s += T(x+8,  y+h-5, "A", sz=8, fill=CWIRE, anchor="start")
    s += T(x+w-8,y+h-5, "K→GND", sz=7, fill=CGND, anchor="end")
    return s, x, y+h//2, x+w, y+h//2

def draw_rj45(x, y, ref, pins, w=140, h=None):
    if h is None:
        h = len(pins)*18 + 28
    s = CompBox(x, y, w, h, ref, "RJ45", col=CGRN)
    for i,(pnum,pnet,pcol) in enumerate(pins):
        py = y + 26 + i*18
        s += Pin(x, py, pcol)
        s += T(x+6, py+4, f"p{pnum}={pnet}", sz=8, fill=pcol, anchor="start")
    return s, x, y, w, h

def gnd_symbol(x, y):
    s = L(x,y,x,y+10, col=CGND, sw=1.5)
    s += L(x-12,y+10,x+12,y+10, col=CGND, sw=2)
    s += L(x-8, y+15,x+8, y+15, col=CGND, sw=1.5)
    s += L(x-4, y+20,x+4, y+20, col=CGND, sw=1)
    return s

def power_rail(x,y,label,col,w=60):
    s = L(x,y,x+w,y, col=col, sw=3)
    s += T(x+w+4, y+4, label, sz=9, fill=col, anchor="start")
    return s


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION BUILDERS
# ═══════════════════════════════════════════════════════════════════════════════

def section_title(title, subtitle=""):
    s = f'<div style="background:#161b22;border:1px solid #30363d;border-radius:6px;padding:8px 16px;margin:16px 0 4px">'
    s += f'<span style="font-size:15px;font-weight:bold;color:#58a6ff">{title}</span>'
    if subtitle:
        s += f'<span style="font-size:11px;color:#8b949e;margin-left:12px">{subtitle}</span>'
    s += '</div>\n'
    return s


# ── POWER SECTION ─────────────────────────────────────────────────────────────
def make_power_svg():
    W,H = 1100,260
    s = svg_open(W,H)

    # J_PWR
    s += CompBox(20,80,90,50,"J_PWR","12V Terminal")
    s += T(65,110,"pin1=+12V_IN",sz=7,fill=C12V)
    s += T(65,122,"pin2=GND",    sz=7,fill=CGND)
    s += Pin(110,105,C12V)

    # Wire to D1
    s += L(110,105,150,105,col=C12V,sw=2)
    s += NetLabel(130,98,"+12V_IN",C12V)

    # D1
    d1s,_,_,d1rx,d1ry = draw_diode(150,80,"D1","1N5819  rev.pol.prot")
    s += d1s
    s += Pin(150,d1ry,C12V)
    s += Pin(230,d1ry,C12V)

    # Wire D1 → J_SW1
    s += L(230,105,270,105,col=C12V,sw=2)
    s += NetLabel(250,98,"12V_PRE_SW",C12V)

    # J_SW1
    s += CompBox(270,80,110,50,"J_SW1","Panel Switch Terminal")
    s += T(325,108,"pin1=12V_PRE_SW",sz=7,fill=C12V)
    s += T(325,120,"pin2=+12V",      sz=7,fill=C12V)
    s += Pin(270,105,C12V)
    s += Pin(380,105,C12V)

    # +12V rail
    s += L(380,105,440,105,col=C12V,sw=2.5)
    s += NetLabel(410,98,"+12V",C12V)

    # C1 bulk cap
    cap1s,_,_,_,_ = draw_cap(440,80,"C1","100µF 25V")
    s += cap1s
    s += Pin(440,97,C12V)
    s += L(380,105,380,70,col=C12V,sw=1.5)
    s += L(380,70,455,70,col=C12V,sw=1.5)
    s += L(455,70,455,80,col=C12V,sw=1.5)
    s += gnd_symbol(455+30,114)
    s += Pin(500,97,C12V)

    # U2 LM2596 buck
    s += L(380,105,380,160,col=C12V,sw=2)
    s += CompBox(350,150,130,60,"U2","LM2596 Buck 12→5V",col="#2a3a1a")
    s += T(415,178,"IN+(1)=+12V",sz=7,fill=C12V)
    s += T(415,190,"OUT+(3)=+5V",sz=7,fill=C5V)
    s += T(415,202,"IN-(2)=OUT-(4)=GND",sz=7,fill=CGND)
    s += Pin(350,160,C12V)
    s += Pin(480,178,C5V)

    # +5V rail
    s += L(480,178,540,178,col=C5V,sw=2.5)
    s += NetLabel(510,171,"+5V",C5V)

    # C2 bulk cap
    s += CompBox(540,160,60,34,"C2","100µF 25V",col="#2a2a1a")
    s += Pin(540,177,C5V)
    s += gnd_symbol(540+30,194)

    # U3 AMS1117
    s += L(540,178,600,178,col=C5V,sw=2)
    s += L(600,178,600,200,col=C5V,sw=2)
    s += CompBox(560,190,130,60,"U3","AMS1117-3.3  5V→3V3",col="#1a3a1a")
    s += T(625,215,"pin3=INPUT(+5V)",sz=7,fill=C5V)
    s += T(625,227,"pin2=OUTPUT(+3V3)",sz=7,fill=C3V3)
    s += T(625,239,"pin1=GND",sz=7,fill=CGND)
    s += Pin(560,210,C5V)
    s += Pin(690,210,C3V3)

    # +3V3 rail
    s += L(690,210,760,210,col=C3V3,sw=2.5)
    s += NetLabel(725,203,"+3V3",C3V3)

    # C3 bulk
    s += CompBox(760,192,60,34,"C3","100µF 16V",col="#2a2a1a")
    s += Pin(760,209,C3V3)
    s += gnd_symbol(760+30,226)

    # C13 AMS1117 decoupling
    s += L(760,210,760,240,col=C3V3,sw=1.5)
    s += CompBox(730,232,60,30,"C13","100nF",col="#2a2a1a")
    s += Pin(730,247,C3V3)
    s += gnd_symbol(730+30,247+6)

    # GND label
    s += T(500,230,"All GND pins → common GND plane",sz=9,fill=CGND)

    # AMS1117 warning
    s += R(850,80,230,80,fill="#1a1010",stroke=CRED,rx=4,sw=1)
    s += T(965,100,"⚠ Verify AMS1117 pinout",sz=10,fill=CRED,bold=True)
    s += T(965,116,"against your supplier datasheet",sz=9,fill=CTXT)
    s += T(965,132,"Some clones: pin1=IN, pin3=GND",sz=9,fill=CYEL)
    s += T(965,148,"(opposite to standard!)",sz=9,fill=CYEL)

    s += svg_close()
    return s


# ── STATUS LEDs ───────────────────────────────────────────────────────────────
def make_led_svg():
    W,H = 700,120
    s = svg_open(W,H)
    for i,(rail,rcol,rref,lref,ldesc) in enumerate([
        ("+12V",C12V,"R13","LED1","Red   12V"),
        ("+5V", C5V, "R14","LED2","Yellow 5V"),
        ("+3V3",C3V3,"R15","LED3","Green 3V3"),
    ]):
        bx = 20 + i*220
        s += T(bx+30,30,rail,sz=9,fill=rcol)
        s += L(bx+10,40,bx+30,40,col=rcol,sw=2)
        rs,_,_,rrx,rry = draw_resistor(bx+30,25,"","1kΩ",w=55,h=30)
        s += CompBox(bx+30,25,55,30,rref,"1kΩ",col="#2a3a2a")
        s += Pin(bx+30,40,rcol)
        s += L(bx+85,40,bx+110,40,col=rcol,sw=1.5)
        s += CompBox(bx+110,25,65,30,lref,ldesc,col="#1a2a3a")
        s += Pin(bx+110,40,rcol)
        s += L(bx+175,40,bx+185,40,col=CGND,sw=1.5)
        s += gnd_symbol(bx+185,40)
        s += T(bx+30,90,f"A→{rail}  K→GND",sz=8,fill=CDIM)
    s += svg_close()
    return s


# ── ZONE CIRCUIT (one per zone, parametric) ───────────────────────────────────
def make_zone_svg(zn, rly_sw, rly_in, rly_out, led_net,
                  mst_sig, mst_vcc, dvcc, dtvs, cap,
                  rser, rpd, rled, led, rj45, esp_gpio_rly, esp_gpio_adc):
    W,H = 1000,380
    s = svg_open(W,H)

    # Title
    s += T(500,20,f"ZONE {zn} — Relay Driver + Moisture Sensor",sz=13,fill=CHL,bold=True)

    # ── RELAY DRIVER PATH ─────────────────────────────────────────────────────
    s += T(30,45,"— RELAY DRIVER —",sz=9,fill=CREL)

    # ESP32 GPIO
    s += R(10,55,120,30,fill="#0d1f12",stroke=CGRN,rx=3)
    s += T(70,66,"ESP32",sz=8,fill=CGRN,bold=True)
    s += T(70,78,f"{esp_gpio_rly}→{rly_sw}",sz=7,fill=CREL)
    s += Pin(130,70,CREL)
    s += L(130,70,160,70,col=CREL,sw=2)
    s += NetLabel(145,62,rly_sw,CREL,sz=8)

    # SW2
    s += CompBox(160,55,70,30,"SW2",f"pos {ord(zn)-64}",col="#2a2a3a")
    s += Pin(160,70,CREL)
    s += Pin(230,70,CREL)
    s += L(230,70,260,70,col=CREL,sw=2)
    s += NetLabel(245,62,rly_in,CREL,sz=8)

    # R pulldown on RLY_IN node
    s += JDot(260,70)
    s += L(260,70,260,100,col=CGND,sw=1.5)
    s += CompBox(230,100,60,28,rpd,"10kΩ",col="#2a2a1a")
    s += Pin(230,114,CGND)
    s += gnd_symbol(260,128)
    s += T(300,120,"(pulldown\nholds off\nwhen idle)",sz=7,fill=CDIM)

    # R series
    s += L(260,70,320,70,col=CREL,sw=2)
    s += CompBox(320,55,65,30,rser,"1kΩ",col="#2a3a2a")
    s += Pin(320,70,CREL)
    s += Pin(385,70,CREL)
    s += L(385,70,420,70,col=CREL,sw=2)
    s += NetLabel(400,62,rly_out,CREL,sz=8)

    # RLY_OUT junction — splits to relay module and LED
    s += JDot(420,70)

    # Branch 1: → relay module (RJ45 pin4)
    s += L(420,70,480,70,col=CREL,sw=2)
    s += T(450,62,"→ J_ZONE pin4",sz=7,fill=CREL)

    # Branch 2: → LED via R
    s += L(420,70,420,140,col=CREL,sw=1.5)
    s += CompBox(390,140,65,28,rled,"1kΩ",col="#2a3a2a")
    s += Pin(390,154,CREL)
    s += L(390,154,455,154,col=CREL,sw=1.5)
    s += NetLabel(422,146,led_net,CREL,sz=7)
    s += CompBox(455,140,70,28,led,"Zone LED",col="#1a2a3a")
    s += Pin(455,154,CREL)
    s += L(525,154,535,154,col=CGND,sw=1.5)
    s += gnd_symbol(535,154)
    s += T(460,185,"A→rly_out via R  K→GND",sz=7,fill=CDIM)

    # ── MOISTURE SENSOR PATH ──────────────────────────────────────────────────
    s += T(30,225,"— MOISTURE SENSOR —",sz=9,fill=CMST)

    # +3V3 → VCC protection diode
    s += T(10,250,"+3V3",sz=9,fill=C3V3)
    s += L(45,260,80,260,col=C3V3,sw=2)

    d2s,_,_,d2rx,d2ry = draw_diode(80,245,dvcc,"1N5819  VCC prot",ak_labels=True,w=90,h=36,hcol="#1a2a3a")
    s += d2s
    s += Pin(80,263,C3V3)
    s += Pin(170,263,C3V3)

    # MST_VCC net → cap to GND + RJ45 pin3
    s += L(170,263,210,263,col=C3V3,sw=2)
    s += NetLabel(190,255,mst_vcc,C3V3,sz=8)
    s += JDot(210,263)

    # Cap to GND
    s += L(210,263,210,295,col=C3V3,sw=1.5)
    s += CompBox(180,295,60,28,cap,"100nF",col="#2a2a1a")
    s += Pin(180,309,C3V3)
    s += gnd_symbol(210,323)

    # → RJ45 pin3
    s += L(210,263,250,263,col=C3V3,sw=2)
    s += T(230,255,"→ J_ZONE pin3",sz=7,fill=C3V3)

    # RJ45 pin1 (SIG from sensor) → TVS + ESP32 ADC
    s += T(310,230,"← J_ZONE pin1 (sensor signal)",sz=7,fill=CMST)
    s += L(310,245,380,245,col=CMST,sw=2)
    s += NetLabel(345,237,mst_sig,CMST,sz=8)
    s += JDot(380,245)

    # TVS to GND
    s += L(380,245,380,295,col=CMST,sw=1.5)
    tvss,_,_,_,_ = draw_tvs(330,295,dtvs,"P6KE3.3A TVS",w=100,h=36)
    s += tvss
    s += Pin(330,313,CMST)
    s += gnd_symbol(380,331)
    s += T(330,345,"K=signal  A=GND",sz=7,fill=CDIM)
    s += T(330,356,"Rev.biased normally",sz=7,fill=CDIM)
    s += T(330,367,"Clamps spikes >3.3V",sz=7,fill=CDIM)

    # → ESP32 ADC
    s += L(380,245,450,245,col=CMST,sw=2)
    s += R(450,230,130,30,fill="#0d1f12",stroke=CGRN,rx=3)
    s += T(515,242,"ESP32",sz=8,fill=CGRN,bold=True)
    s += T(515,255,f"{esp_gpio_adc}←{mst_sig}",sz=7,fill=CMST)
    s += Pin(450,245,CMST)

    # RJ45 pin summary
    s += R(550,225,200,150,fill="#0d1f12",stroke=CGRN,rx=4,sw=1.5)
    s += T(650,242,rj45,sz=9,fill=CGRN,bold=True)
    s += T(650,255,"RJ45  T568B wiring",sz=7,fill=CDIM)
    rj_pins=[
        ("1",mst_sig, CMST),("2","GND",CGND),("3",mst_vcc,C3V3),
        ("4",rly_out, CREL),("5","GND",CGND),("6","GND",CGND),
        ("7","+5V",   C5V), ("8","GND",CGND),("S","GND",  CGND),
    ]
    for ii,(pn,pnet,pc) in enumerate(rj_pins):
        py = 266 + ii*11
        s += Pin(558,py,pc)
        s += T(564,py+4,f"pin{pn}={pnet}",sz=7.5,fill=pc,anchor="start")

    s += svg_close()
    return s


# ── I2C SECTION ───────────────────────────────────────────────────────────────
def make_i2c_svg():
    W,H = 1000,200
    s = svg_open(W,H)
    s += T(500,18,"I2C BUS  (3 ports, shared SDA/SCL)",sz=13,fill=CHL,bold=True)

    # Pull-ups
    s += T(20,45,"Pull-ups (one set for whole bus):",sz=9,fill=CTXT)
    s += L(10,60,40,60,col=C3V3,sw=2)
    s += T(25,52,"+3V3",sz=8,fill=C3V3)
    s += CompBox(40,48,65,28,"R6","4.7kΩ SDA↑",col="#2a2a3a")
    s += Pin(40,62,C3V3)
    s += L(105,62,140,62,col=CSDA,sw=2)
    s += NetLabel(122,54,"SDA",CSDA)

    s += L(10,100,40,100,col=C3V3,sw=2)
    s += T(25,92,"+3V3",sz=8,fill=C3V3)
    s += CompBox(40,88,65,28,"R7","4.7kΩ SCL↑",col="#2a2a3a")
    s += Pin(40,102,C3V3)
    s += L(105,102,140,102,col=CSCL,sw=2)
    s += NetLabel(122,94,"SCL",CSCL)

    # ESP32
    s += R(140,48,120,70,fill="#0d1f12",stroke=CGRN,rx=4)
    s += T(200,63,"ESP32",sz=9,fill=CGRN,bold=True)
    s += T(200,77,"IO21=SDA",sz=8,fill=CSDA)
    s += T(200,91,"IO22=SCL",sz=8,fill=CSCL)
    s += T(200,105,"(I2C master)",sz=7,fill=CDIM)
    s += Pin(140,77,CSDA)
    s += Pin(140,91,CSCL)

    # 3 ports
    for ii,(ji,di,ci) in enumerate([("J_I2C_1","D7","C9"),("J_I2C_2","D8","C10"),("J_I2C_3","D9","C11")]):
        bx = 300 + ii*230
        # VCC protection diode
        s += CompBox(bx,48,80,30,di,"1N5819 VCC",col="#1a2a3a")
        s += T(bx+8,70,"A",sz=7,fill=C3V3,anchor="start")
        s += T(bx+72,70,"K",sz=7,fill=CRED,anchor="end")
        s += Pin(bx,63,C3V3)
        s += L(bx-10,63,bx,63,col=C3V3,sw=1.5)
        s += T(bx-12,60,"+3V3",sz=7,fill=C3V3,anchor="end")
        # Cap
        s += CompBox(bx+90,48,50,30,ci,"100nF",col="#2a2a1a")
        s += Pin(bx+90,63,C3V3)
        s += L(bx+80,63,bx+90,63,col=C3V3,sw=1.5)
        s += gnd_symbol(bx+115,78)
        # RJ45
        s += R(bx,88,145,90,fill="#0d1f12",stroke=CGRN,rx=4,sw=1.5)
        s += T(bx+72,102,ji,sz=9,fill=CGRN,bold=True)
        s += T(bx+72,114,"p1=SDA  p2=GND",sz=7.5,fill=CSDA)
        s += T(bx+72,126,"p3=VCC  p4=SCL",sz=7.5,fill=C3V3)
        s += T(bx+72,138,"p5,p6=GND",sz=7.5,fill=CGND)
        # SDA/SCL to RJ45
        s += L(bx,114,bx-10,114,col=CSDA,sw=1.5)
        s += L(bx,126,bx-10,126,col=CSCL,sw=1.5)
        # VCC to RJ45
        s += L(bx+80,63,bx+80,88,col=C3V3,sw=1.5)

    # Note: SDA/SCL are bus lines
    s += T(500,190,"SDA and SCL are shared across all 3 ports — I2C bus topology. "
           "Only ONE set of pull-ups needed (R6+R7).",sz=8,fill=CYEL)
    s += svg_close()
    return s


# ── SD CARD SECTION ───────────────────────────────────────────────────────────
def make_sd_svg():
    W,H = 820,220
    s = svg_open(W,H)
    s += T(410,18,"SD CARD  (SPI mode)",sz=13,fill=CHL,bold=True)

    # ESP32
    s += R(10,40,130,130,fill="#0d1f12",stroke=CGRN,rx=4)
    s += T(75,58,"ESP32",sz=9,fill=CGRN,bold=True)
    spi = [("IO5","SD_CS","#ffee88"),("IO23","SD_MOSI","#ffaa88"),
           ("IO19","SD_MISO","#ff8888"),("IO18","SD_SCK","#ffcc88")]
    for ii,(gpio,net,col) in enumerate(spi):
        py = 72+ii*24
        s += T(75,py,f"{gpio}={net}",sz=8,fill=col)
        s += Pin(140,py-8,col)
        s += L(140,py-8,180,py-8,col=col,sw=1.5)
        s += NetLabel(160,py-16,net,col,sz=7)

    # R8 CS pull-up
    s += T(185,40,"R8 10kΩ CS pull-up",sz=8,fill=CTXT)
    s += L(185,50,185,64,col="#ffee88",sw=1.5)
    s += T(175,58,"+3V3",sz=7,fill=C3V3,anchor="end")
    s += L(160,55,185,55,col=C3V3,sw=1.5)

    # SD Module
    s += R(230,40,200,140,fill="#0d1f12",stroke=CGRN,rx=4,sw=1.5)
    s += T(330,58,"SD_MOD",sz=10,fill=CGRN,bold=True)
    s += T(330,70,"MicroSD Socket",sz=8,fill=CDIM)
    sd=[("4","VDD",C3V3),("6","VSS",CGND),("2","CS (DAT3)","#ffee88"),
        ("3","MOSI (CMD)","#ffaa88"),("7","MISO (DAT0)","#ff8888"),
        ("5","SCK (CLK)","#ffcc88"),("1","DAT2→GND",CGND),("8","DAT1→GND",CGND),("SH","Shield→GND",CGND)]
    for ii,(pn,pnet,pc) in enumerate(sd):
        py = 82+ii*11
        s += Pin(230,py,pc)
        s += T(237,py+4,f"p{pn}={pnet}",sz=7.5,fill=pc,anchor="start")

    # C12 VCC decoupling
    s += CompBox(460,75,70,30,"C12","100µF VCC",col="#2a2a1a")
    s += L(460,90,450,90,col=C3V3,sw=1.5)
    s += T(448,88,"+3V3",sz=7,fill=C3V3,anchor="end")
    s += gnd_symbol(495,105)

    s += T(330,195,"DAT2 (pin1) and DAT1 (pin8) unused in SPI mode — tied to GND",sz=8,fill=CDIM)
    s += T(330,210,"DAT3/CD (pin2) = SPI chip select",sz=8,fill=CDIM)
    s += svg_close()
    return s


# ── DHT22 SECTION ─────────────────────────────────────────────────────────────
def make_dht_svg():
    W,H = 700,180
    s = svg_open(W,H)
    s += T(350,18,"DHT22 Temperature/Humidity",sz=13,fill=CHL,bold=True)

    # +3V3 → D6 → DHT_VCC
    s += T(10,55,"+3V3",sz=9,fill=C3V3)
    s += L(45,65,80,65,col=C3V3,sw=2)
    d6s,_,_,d6rx,_ = draw_diode(80,50,"D6","1N5819 VCC prot",ak_labels=True,w=85,h=34,hcol="#1a2a3a")
    s += d6s
    s += Pin(80,67,C3V3)
    s += Pin(165,67,C3V3)
    s += L(165,67,200,67,col=C3V3,sw=2)
    s += NetLabel(182,58,"DHT_VCC",C3V3)
    s += JDot(200,67)

    # Cap to GND
    s += L(200,67,200,95,col=C3V3,sw=1.5)
    s += CompBox(175,95,50,28,"C8","100nF",col="#2a2a1a")
    s += Pin(175,109,C3V3)
    s += gnd_symbol(200,123)

    # → RJ45 pin3
    s += L(200,67,250,67,col=C3V3,sw=2)
    s += T(225,58,"→ J_DHT pin3",sz=7,fill=C3V3)

    # +3V3 → R5 pull-up → DHT_DATA
    s += T(10,130,"+3V3",sz=9,fill=C3V3)
    s += L(45,140,80,140,col=C3V3,sw=2)
    s += CompBox(80,128,65,28,"R5","10kΩ pull-up",col="#2a2a3a")
    s += Pin(80,142,C3V3)
    s += L(145,142,180,142,col=CDHT,sw=2)
    s += NetLabel(162,133,"DHT_DATA",CDHT)
    s += JDot(180,142)
    s += L(180,142,220,142,col=CDHT,sw=2)
    s += T(200,133,"→ J_DHT pin1",sz=7,fill=CDHT)

    # → ESP32 IO27
    s += L(180,142,180,160,col=CDHT,sw=1.5)
    s += R(155,160,110,24,fill="#0d1f12",stroke=CGRN,rx=3)
    s += T(210,175,"ESP32 IO27=DHT_DATA",sz=8,fill=CGRN)
    s += Pin(180,167,CDHT)

    # RJ45 summary
    s += R(340,40,200,120,fill="#0d1f12",stroke=CGRN,rx=4,sw=1.5)
    s += T(440,56,"J_DHT",sz=10,fill=CGRN,bold=True)
    s += T(440,68,"RJ45",sz=8,fill=CDIM)
    dht_pins=[("1","DHT_DATA",CDHT),("2","GND",CGND),("3","DHT_VCC",C3V3),
              ("4","NC",CDIM),("5","GND",CGND),("6","GND",CGND),
              ("7","NC",CDIM),("8","NC",CDIM),("S","GND",CGND)]
    for ii,(pn,pnet,pc) in enumerate(dht_pins):
        py = 78+ii*9
        s += Pin(348,py,pc)
        s += T(355,py+4,f"p{pn}={pnet}",sz=7,fill=pc,anchor="start")

    s += svg_close()
    return s


# ── DIODE CONVENTION REFERENCE ────────────────────────────────────────────────
def make_diode_ref_svg():
    W,H = 900,200
    s = svg_open(W,H)
    s += T(450,18,"DIODE POLARITY — KiCad D_DO-41 Footprint Convention",sz=12,fill=CRED,bold=True)

    # Physical convention
    s += R(10,30,260,50,fill="#1a1010",stroke=CRED,rx=4,sw=1)
    s += T(140,48,"DO-41 FOOTPRINT: pad1=CATHODE(K)  pad2=ANODE(A)",sz=8,fill=CRED)
    s += T(140,62,"Band (stripe) on component body = CATHODE end",sz=8,fill=CYEL)

    # D2 example
    s += T(10,95,"EXAMPLE D2 (VCC protection):",sz=9,fill=CTXT)
    s += T(10,110,"+3V3 bus → ANODE(A) → CATHODE(K) → MST_A_VCC → sensor",sz=9,fill=C3V3)
    s += T(10,125,"Schematic pin1→MST_A_VCC, pin2→+3V3 (pin1=A in symbol, but pad1=K in footprint)",sz=8,fill=CDIM)
    s += T(10,140,"∴ Physical board: pad1(K)=MST_A_VCC, pad2(A)=+3V3  → current flows +3V3→sensor ✓",sz=8,fill=CGRN)

    # D10 example
    s += T(10,158,"EXAMPLE D10 (TVS clamp):",sz=9,fill=CTXT)
    s += T(10,173,"CATHODE(K) → MST_A_SIG signal line    ANODE(A) → GND",sz=9,fill=CMST)
    s += T(10,188,"Reverse biased in normal op. Clamps voltage spikes above 3.3V to protect ESP32 ADC.",sz=8,fill=CDIM)

    # D1 example
    s += T(470,95,"EXAMPLE D1 (reverse polarity protection):",sz=9,fill=CTXT)
    s += T(470,110,"ANODE(A) → +12V_IN     CATHODE(K) → 12V_PRE_SW",sz=9,fill=C12V)
    s += T(470,125,"Normal: forward biased — passes +12V to switch",sz=8,fill=CDIM)
    s += T(470,140,"Reverse polarity: reverse biased — blocks current → protects board",sz=8,fill=CDIM)
    s += T(470,158,"Band on body faces away from J_PWR (toward J_SW1)",sz=8,fill=CYEL)

    s += svg_close()
    return s


# ── ESP32 PIN REFERENCE ───────────────────────────────────────────────────────
def make_esp32_svg():
    W,H = 820,560
    s = svg_open(W,H)
    s += T(410,18,"ESP32-DevKitC-32E Socket — GPIO Assignments",sz=13,fill=CHL,bold=True)

    L_PINS=[
        ("pad1", "GND",   "GND",      CGND),
        ("pad3", "IO23",  "SD_MOSI",  CSPI),
        ("pad5", "IO22",  "SCL",      CSCL),
        ("pad7", "TXD0",  "PI_TX",    CDIM),
        ("pad9", "RXD0",  "PI_RX",    CDIM),
        ("pad11","IO21",  "SDA",      CSDA),
        ("pad13","GND",   "GND",      CGND),
        ("pad15","IO19",  "SD_MISO",  CSPI),
        ("pad17","IO18",  "SD_SCK",   CSPI),
        ("pad19","IO5",   "SD_CS",    CSPI),
        ("pad21","IO17",  "NC",       CDIM),
        ("pad23","IO16",  "NC",       CDIM),
        ("pad25","IO4",   "NC",       CDIM),
        ("pad27","IO0",   "NC ⚠boot", CRED),
        ("pad29","IO2",   "NC ⚠boot", CRED),
        ("pad31","IO15",  "NC",       CDIM),
        ("pad33","GND",   "GND",      CGND),
        ("pad35","IO8*",  "NC ⚠flash",CRED),
        ("pad37","IO7*",  "NC ⚠flash",CRED),
    ]
    R_PINS=[
        ("pad2", "3V3out","ESP_3V3",  CGRN),
        ("pad4", "EN",    "NC",       CDIM),
        ("pad6", "IO36",  "NC",       CDIM),
        ("pad8", "IO39",  "NC",       CDIM),
        ("pad10","IO34",  "MST_C_SIG",CMST),
        ("pad12","IO35",  "MST_D_SIG",CMST),
        ("pad14","IO32",  "MST_A_SIG",CMST),
        ("pad16","IO33",  "MST_B_SIG",CMST),
        ("pad18","IO25",  "RLY_A_SW", CREL),
        ("pad20","IO26",  "RLY_B_SW", CREL),
        ("pad22","IO27",  "DHT_DATA", CDHT),
        ("pad24","IO14",  "RLY_D_SW", CREL),
        ("pad26","IO12",  "NC ⚠boot", CRED),
        ("pad28","GND",   "GND",      CGND),
        ("pad30","IO13",  "RLY_C_SW", CREL),
        ("pad32","IO9*",  "NC ⚠flash",CRED),
        ("pad34","IO10*", "NC ⚠flash",CRED),
        ("pad36","IO11*", "NC ⚠flash",CRED),
        ("pad38","VIN",   "+5V",      C5V),
    ]

    # ESP32 body
    s += R(280,35,260,500,fill="#0d1f12",stroke=CGRN,rx=6,sw=2)
    s += T(410,55,"U1  ESP32-DevKitC-32E",sz=11,fill=CGRN,bold=True)
    s += T(410,68,"Socket 2×19 pins P2.54mm",sz=8,fill=CDIM)

    ROW=24
    for i,(pad,gpio,net,col) in enumerate(L_PINS):
        py=80+i*ROW
        s += Pin(280,py,col)
        s += T(275,py+4,pad,sz=7,fill=CDIM,anchor="end")
        s += T(245,py+4,gpio,sz=8,fill=col,anchor="end")
        s += T(200,py+4,net,sz=8,fill=col,anchor="end")
        s += L(0,py,200,py,col=col,sw=1,dash="4,3")

    for i,(pad,gpio,net,col) in enumerate(R_PINS):
        py=80+i*ROW
        s += Pin(540,py,col)
        s += T(545,py+4,pad,sz=7,fill=CDIM,anchor="start")
        s += T(580,py+4,gpio,sz=8,fill=col,anchor="start")
        s += T(620,py+4,net,sz=8,fill=col,anchor="start")
        s += L(620,py,820,py,col=col,sw=1,dash="4,3")

    s += T(5,540,"⚠ NC = Not Connected  |  * = connected to internal flash — must leave NC  |  ⚠boot = strapping pin — must leave NC",
           sz=8,fill=CRED,anchor="start")
    s += svg_close()
    return s


# ═══════════════════════════════════════════════════════════════════════════════
# BUILD HTML
# ═══════════════════════════════════════════════════════════════════════════════

ZONES = [
    ("A","RLY_A_SW","RLY_A_IN","RLY_A_OUT","ZA_LED_A","MST_A_SIG","MST_A_VCC",
     "D2","D10","C4","R1","R16","R9","LED4","J_ZONE_A","IO25","IO32"),
    ("B","RLY_B_SW","RLY_B_IN","RLY_B_OUT","ZB_LED_A","MST_B_SIG","MST_B_VCC",
     "D3","D11","C5","R2","R17","R10","LED5","J_ZONE_B","IO26","IO33"),
    ("C","RLY_C_SW","RLY_C_IN","RLY_C_OUT","ZC_LED_A","MST_C_SIG","MST_C_VCC",
     "D4","D12","C6","R3","R18","R11","LED6","J_ZONE_C","IO13","IO34"),
    ("D","RLY_D_SW","RLY_D_IN","RLY_D_OUT","ZD_LED_A","MST_D_SIG","MST_D_VCC",
     "D5","D13","C7","R4","R19","R12","LED7","J_ZONE_D","IO14","IO35"),
]

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>NodeBoard v2 Wiring Diagram</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ background: {BG}; color: #c9d1d9; font-family: Consolas, monospace; padding: 20px; }}
h1 {{ color: {CHL}; font-size: 22px; margin-bottom: 4px; }}
.subtitle {{ color: {CDIM}; font-size: 11px; margin-bottom: 20px; }}
.section {{ margin-bottom: 24px; }}
.sec-title {{ background: #161b22; border: 1px solid #30363d; border-radius: 6px;
              padding: 8px 16px; margin-bottom: 8px; }}
.sec-title h2 {{ color: {CHL}; font-size: 14px; display: inline; }}
.sec-title span {{ color: {CDIM}; font-size: 10px; margin-left: 12px; }}
svg {{ border-radius: 6px; overflow: visible; }}
.note {{ background: #1a1a10; border: 1px solid {CYEL}; border-radius: 4px;
         padding: 8px 14px; margin: 8px 0; font-size: 11px; color: {CYEL}; }}
@media print {{
  body {{ background: white; }}
  .note {{ border-color: #999; color: #333; }}
}}
</style>
</head>
<body>
<h1>NurseryHub NodeBoard v2 — Wiring Diagram</h1>
<div class="subtitle">Generated from generate_schematic.py · All connections match NETLIST source of truth</div>

<div class="section">
<div class="sec-title"><h2>Power Chain</h2><span>J_PWR → D1 → J_SW1 → U2 (12→5V) → U3 (5→3.3V)</span></div>
{make_power_svg()}
</div>

<div class="section">
<div class="sec-title"><h2>Status LEDs</h2><span>Power rail indicators</span></div>
{make_led_svg()}
</div>

<div class="section">
<div class="sec-title"><h2>Diode Polarity Reference</h2><span>DO-41 footprint convention — read before assembling</span></div>
{make_diode_ref_svg()}
</div>

<div class="section">
<div class="sec-title"><h2>ESP32 GPIO Assignments</h2><span>U1 ESP32-DevKitC-32E socket</span></div>
{make_esp32_svg()}
</div>
"""

for z in ZONES:
    zn = z[0]
    html += f"""
<div class="section">
<div class="sec-title"><h2>Zone {zn}</h2>
<span>Relay driver + moisture sensor · RJ45 connector {z[14]}</span></div>
{make_zone_svg(*z)}
</div>
"""

html += f"""
<div class="section">
<div class="sec-title"><h2>DHT22 Temperature/Humidity</h2></div>
{make_dht_svg()}
</div>

<div class="section">
<div class="sec-title"><h2>I2C Bus (3 ports)</h2><span>Shared SDA/SCL · Single pull-up pair R6+R7</span></div>
{make_i2c_svg()}
</div>

<div class="section">
<div class="sec-title"><h2>SD Card (SPI mode)</h2></div>
{make_sd_svg()}
</div>

<div class="note">
SW2 DIP SWITCH — Zone enable: each position (1-4) connects RLY_x_SW to RLY_x_IN when ON.
With standard DIP numbering: pos1 bridges pad1↔pad8, pos2↔pad7, pos3↔pad6, pos4↔pad5.
NETLIST corrected: pad8=RLY_A_IN, pad7=RLY_B_IN, pad6=RLY_C_IN, pad5=RLY_D_IN.
</div>

</body></html>
"""

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "node_board_v2_diagram.html")
with open(out_path, "w", encoding="utf-8") as f:
    f.write(html)
print(f"Written: {out_path}")
webbrowser.open(f"file:///{out_path.replace(os.sep, '/')}")
