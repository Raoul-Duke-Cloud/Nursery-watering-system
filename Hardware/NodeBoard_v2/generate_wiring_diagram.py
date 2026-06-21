#!/usr/bin/env python3
"""
NurseryHub Node Board v2 — Wiring Reference Diagram Generator
Reads NETLIST from generate_schematic.py and outputs an HTML wiring diagram.
Usage: python generate_wiring_diagram.py
Opens node_board_v2_wiring.html in your browser.
"""

import os, sys, webbrowser
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_schematic import NETLIST, COMPONENTS

# ── Build net → [(ref, pin)] mapping ─────────────────────────────────────────

net_pins = {}
for ref, pins in NETLIST.items():
    for pin, net in pins.items():
        if net.startswith("NC_"):
            continue
        net_pins.setdefault(net, []).append((ref, pin))

# Sort each net's pin list
for net in net_pins:
    net_pins[net].sort(key=lambda x: (x[0], x[1]))

# ── Functional sections ───────────────────────────────────────────────────────

SECTIONS = [
    ("Power Input & Switch", [
        "+12V_IN", "12V_PRE_SW", "+12V", "+5V", "+3V3", "ESP_3V3", "GND",
    ]),
    ("Status LEDs", [
        "LED1_A", "LED2_A", "LED3_A",
    ]),
    ("Zone A", [
        "RLY_A_SW", "RLY_A_IN", "RLY_A_OUT", "ZA_LED_A",
        "MST_A_VCC", "MST_A_SIG",
    ]),
    ("Zone B", [
        "RLY_B_SW", "RLY_B_IN", "RLY_B_OUT", "ZB_LED_A",
        "MST_B_VCC", "MST_B_SIG",
    ]),
    ("Zone C", [
        "RLY_C_SW", "RLY_C_IN", "RLY_C_OUT", "ZC_LED_A",
        "MST_C_VCC", "MST_C_SIG",
    ]),
    ("Zone D", [
        "RLY_D_SW", "RLY_D_IN", "RLY_D_OUT", "ZD_LED_A",
        "MST_D_VCC", "MST_D_SIG",
    ]),
    ("DHT22", [
        "DHT_VCC", "DHT_DATA",
    ]),
    ("I2C Bus", [
        "SDA", "SCL",
        "I2C1_VCC", "I2C2_VCC", "I2C3_VCC",
    ]),
    ("SD Card", [
        "SD_CS", "SD_MOSI", "SD_MISO", "SD_SCK",
    ]),
    ("Pi UART", [
        "PI_TX", "PI_RX",
    ]),
]

# Collect all nets that appear in sections
sectioned_nets = set()
for _, nets in SECTIONS:
    sectioned_nets.update(nets)

# Any remaining nets go in "Other"
other_nets = sorted(n for n in net_pins if n not in sectioned_nets)
if other_nets:
    SECTIONS.append(("Other", other_nets))

# ── Component descriptions ────────────────────────────────────────────────────

COMP_DESC = {
    "J_PWR":    "12V Terminal",
    "J_SW1":    "Power Switch Terminal",
    "D1":       "D1 Reverse Polarity",
    "U2":       "U2 LM2596 Buck 12V→5V",
    "U3":       "U3 AMS1117 5V→3V3",
    "C1":       "C1 100uF +12V bulk",
    "C2":       "C2 100uF +5V bulk",
    "C3":       "C3 100uF +3V3 bulk",
    "C12":      "C12 100uF +3V3 SD",
    "C13":      "C13 100nF AMS1117 decoup",
    "R13":      "R13 1k LED1 series",
    "R14":      "R14 1k LED2 series",
    "R15":      "R15 1k LED3 series",
    "LED1":     "LED1 Red 12V",
    "LED2":     "LED2 Yellow 5V",
    "LED3":     "LED3 Green 3V3",
    "U1":       "U1 ESP32-DevKitC",
    "SW2":      "SW2 DIP Zone Enable",
    "R1":       "R1 1k Zone A series",
    "R2":       "R2 1k Zone B series",
    "R3":       "R3 1k Zone C series",
    "R4":       "R4 1k Zone D series",
    "R16":      "R16 10k Zone A pulldown",
    "R17":      "R17 10k Zone B pulldown",
    "R18":      "R18 10k Zone C pulldown",
    "R19":      "R19 10k Zone D pulldown",
    "R9":       "R9 1k Zone A LED",
    "R10":      "R10 1k Zone B LED",
    "R11":      "R11 1k Zone C LED",
    "R12":      "R12 1k Zone D LED",
    "LED4":     "LED4 Blue Zone A",
    "LED5":     "LED5 Blue Zone B",
    "LED6":     "LED6 Zone C",
    "LED7":     "LED7 Zone D",
    "D2":       "D2 1N5819 Zone A VCC prot",
    "D3":       "D3 1N5819 Zone B VCC prot",
    "D4":       "D4 1N5819 Zone C VCC prot",
    "D5":       "D5 1N5819 Zone D VCC prot",
    "D6":       "D6 1N5819 DHT VCC prot",
    "D7":       "D7 1N5819 I2C1 VCC prot",
    "D8":       "D8 1N5819 I2C2 VCC prot",
    "D9":       "D9 1N5819 I2C3 VCC prot",
    "D10":      "D10 P6KE3.3A TVS Zone A",
    "D11":      "D11 P6KE3.3A TVS Zone B",
    "D12":      "D12 P6KE3.3A TVS Zone C",
    "D13":      "D13 P6KE3.3A TVS Zone D",
    "D14":      "D14 1N4007 Flyback DNP",
    "D15":      "D15 1N4007 Flyback DNP",
    "D16":      "D16 1N4007 Flyback DNP",
    "D17":      "D17 1N4007 Flyback DNP",
    "C4":       "C4 100nF Zone A VCC",
    "C5":       "C5 100nF Zone B VCC",
    "C6":       "C6 100nF Zone C VCC",
    "C7":       "C7 100nF Zone D VCC",
    "C8":       "C8 100nF DHT VCC",
    "C9":       "C9 100nF I2C1 VCC",
    "C10":      "C10 100nF I2C2 VCC",
    "C11":      "C11 100nF I2C3 VCC",
    "J_ZONE_A": "J_ZONE_A RJ45",
    "J_ZONE_B": "J_ZONE_B RJ45",
    "J_ZONE_C": "J_ZONE_C RJ45",
    "J_ZONE_D": "J_ZONE_D RJ45",
    "J_DHT":    "J_DHT RJ45",
    "J_I2C_1":  "J_I2C_1 RJ45",
    "J_I2C_2":  "J_I2C_2 RJ45",
    "J_I2C_3":  "J_I2C_3 RJ45",
    "R5":       "R5 10k DHT pullup",
    "R6":       "R6 4k7 SDA pullup",
    "R7":       "R7 4k7 SCL pullup",
    "R8":       "R8 10k SD CS pullup",
    "SD_MOD":   "SD_MOD MicroSD Socket",
    "J_PI":     "J_PI Pi UART DNP",
}

def desc(ref):
    return COMP_DESC.get(ref, ref)

# ── Section colour palette ────────────────────────────────────────────────────

SECTION_COLORS = [
    "#1a3a5c",  # Power
    "#2d1b4e",  # LEDs
    "#1a4a2e",  # Zone A
    "#2e3a1a",  # Zone B
    "#4a2e1a",  # Zone C
    "#3a1a3a",  # Zone D
    "#1a3a4a",  # DHT22
    "#2a1a3a",  # I2C
    "#3a2a1a",  # SD
    "#1a2a3a",  # Pi
    "#2a2a2a",  # Other
]

NET_COLORS = {
    "+12V_IN":   "#ff6b35",
    "12V_PRE_SW":"#ff8c42",
    "+12V":      "#ffa500",
    "+5V":       "#ffcc00",
    "+3V3":      "#44ff44",
    "ESP_3V3":   "#88ff88",
    "GND":       "#888888",
    "SDA":       "#66aaff",
    "SCL":       "#4488ff",
    "DHT_DATA":  "#ff88cc",
    "SD_MOSI":   "#ffaa88",
    "SD_MISO":   "#ff8888",
    "SD_SCK":    "#ffcc88",
    "SD_CS":     "#ffee88",
}

def net_color(net):
    return NET_COLORS.get(net, "#cccccc")

# ── ESP32 pin name lookup ─────────────────────────────────────────────────────

ESP32_GPIO = {
    "1":"GND","3":"IO23","5":"IO22","7":"TXD0","9":"RXD0","11":"IO21",
    "13":"GND","15":"IO19","17":"IO18","19":"IO5","21":"IO17","23":"IO16",
    "25":"IO4","27":"IO0","29":"IO2","31":"IO15","33":"GND","35":"IO8","37":"IO7",
    "2":"3V3","4":"EN","6":"IO36","8":"IO39","10":"IO34","12":"IO35",
    "14":"IO32","16":"IO33","18":"IO25","20":"IO26","22":"IO27","24":"IO14",
    "26":"IO12","28":"GND","30":"IO13","32":"IO9","34":"IO10","36":"IO11","38":"VIN",
}

def pin_label(ref, pin):
    if ref == "U1":
        gpio = ESP32_GPIO.get(pin, pin)
        return f"U1 pad{pin} ({gpio})"
    if ref.startswith("TP"):
        return f"{ref}"
    if ref.startswith("J_"):
        return f"{ref} pin{pin}"
    return f"{ref} pin{pin}"

# ── HTML generation ───────────────────────────────────────────────────────────

def build_html():
    rows = []

    for i, (section_title, nets) in enumerate(SECTIONS):
        color = SECTION_COLORS[i % len(SECTION_COLORS)]
        rows.append(f'''
    <tr>
      <td colspan="3" class="section-header" style="background:{color}">
        {section_title}
      </td>
    </tr>''')

        for net in nets:
            if net not in net_pins:
                continue
            pins = net_pins[net]
            nc = net_color(net)

            pin_cells = []
            for ref, pin in pins:
                label = pin_label(ref, pin)
                comp = desc(ref)
                dnp = " <span class='dnp'>DNP</span>" if COMPONENTS.get(ref, (None,None,False))[2] else ""
                pin_cells.append(
                    f'<div class="pin-chip" title="{comp}">{label}{dnp}</div>'
                )

            rows.append(f'''
    <tr>
      <td class="net-name" style="border-left: 4px solid {nc}; color:{nc}">
        {net}
      </td>
      <td class="pin-count">{len(pins)}</td>
      <td class="pins">{''.join(pin_cells)}</td>
    </tr>''')

    return "\n".join(rows)


HTML = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>NodeBoard v2 — Wiring Reference</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: 'Consolas', 'Courier New', monospace;
    background: #0d1117;
    color: #c9d1d9;
    padding: 24px;
    font-size: 13px;
  }}
  h1 {{
    color: #58a6ff;
    font-size: 20px;
    margin-bottom: 4px;
  }}
  .subtitle {{
    color: #8b949e;
    margin-bottom: 24px;
    font-size: 12px;
  }}
  table {{
    width: 100%;
    border-collapse: collapse;
  }}
  tr:hover td {{ background: rgba(255,255,255,0.03); }}
  td {{
    padding: 5px 10px;
    border-bottom: 1px solid #21262d;
    vertical-align: top;
  }}
  .section-header {{
    font-weight: bold;
    font-size: 14px;
    color: #ffffff;
    padding: 10px 12px;
    letter-spacing: 0.5px;
    border-top: 2px solid #30363d;
  }}
  .net-name {{
    width: 180px;
    font-weight: bold;
    white-space: nowrap;
    padding-left: 12px;
  }}
  .pin-count {{
    width: 36px;
    text-align: center;
    color: #8b949e;
    font-size: 11px;
  }}
  .pins {{
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    align-items: flex-start;
  }}
  .pin-chip {{
    background: #21262d;
    border: 1px solid #30363d;
    border-radius: 4px;
    padding: 2px 8px;
    font-size: 11px;
    white-space: nowrap;
    cursor: default;
    color: #c9d1d9;
  }}
  .pin-chip:hover {{
    background: #30363d;
    border-color: #58a6ff;
    color: #58a6ff;
  }}
  .dnp {{
    background: #6e2d2d;
    color: #ff8888;
    border-radius: 3px;
    padding: 0 4px;
    font-size: 10px;
    margin-left: 4px;
  }}
  .legend {{
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
    margin-bottom: 20px;
  }}
  .legend-item {{
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 11px;
  }}
  .legend-dot {{
    width: 12px;
    height: 12px;
    border-radius: 2px;
  }}
  @media print {{
    body {{ background: white; color: black; }}
    .pin-chip {{ border: 1px solid #999; background: #f5f5f5; color: black; }}
    .section-header {{ color: white !important; }}
  }}
</style>
</head>
<body>

<h1>NurseryHub NodeBoard v2 — Wiring Reference</h1>
<div class="subtitle">
  Generated from Hardware/NodeBoard_v2/generate_schematic.py &nbsp;|&nbsp;
  Hover over a pin chip to see component description &nbsp;|&nbsp;
  DNP = Do Not Populate
</div>

<div class="legend">
  <div class="legend-item"><div class="legend-dot" style="background:#ffa500"></div>+12V rail</div>
  <div class="legend-item"><div class="legend-dot" style="background:#ffcc00"></div>+5V rail</div>
  <div class="legend-item"><div class="legend-dot" style="background:#44ff44"></div>+3V3 rail</div>
  <div class="legend-item"><div class="legend-dot" style="background:#888888"></div>GND</div>
  <div class="legend-item"><div class="legend-dot" style="background:#66aaff"></div>I2C</div>
  <div class="legend-item"><div class="legend-dot" style="background:#ff88cc"></div>DHT</div>
  <div class="legend-item"><div class="legend-dot" style="background:#ffaa88"></div>SPI/SD</div>
</div>

<table>
  <thead>
    <tr>
      <th style="text-align:left; padding:8px 12px; background:#161b22; color:#8b949e; width:180px">Net</th>
      <th style="text-align:center; padding:8px; background:#161b22; color:#8b949e; width:36px">#</th>
      <th style="text-align:left; padding:8px 12px; background:#161b22; color:#8b949e">Connected Pins</th>
    </tr>
  </thead>
  <tbody>
{build_html()}
  </tbody>
</table>

</body>
</html>
"""

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "node_board_v2_wiring.html")
with open(out_path, "w", encoding="utf-8") as f:
    f.write(HTML)

print(f"Written: {out_path}")
webbrowser.open(f"file:///{out_path.replace(os.sep, '/')}")
