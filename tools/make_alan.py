"""Генерирует assets/alan/<mood>.svg — снежный барс Алан в шести настроениях.

Запуск: python3 tools/make_alan.py
Все позы собираются из одних деталей, поэтому стиль всегда единый.
"""
from pathlib import Path

FUR = "#EEF2F7"
FUR_SHADE = "#DCE3EC"
SPOT = "#56677E"
EAR_IN = "#E7CFD6"
MUZZLE = "#FFFFFF"
NOSE = "#C7868F"
IRIS = "#9EC3B4"
PUPIL = "#1D2B3A"
INK = "#23364D"
SCARF = "#2C7BE5"
SCARF_DARK = "#1D5FB8"
BLUSH = "#F4C3CC"


def rosette(x, y, r=6.5, rot=0):
    # открытое кольцо — узнаваемое пятно ирбиса
    return (f'<path transform="rotate({rot} {x} {y})" d="M{x - r} {y} a{r} {r} 0 1 1 {r * 1.6} {r * 0.9}" '
            f'fill="none" stroke="{SPOT}" stroke-width="3.6" stroke-linecap="round"/>')


def dot(x, y, r=3.2):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{SPOT}"/>'


def eye_open(cx, cy, dx=0, dy=0, scale=1.0):
    rx, ry = 10 * scale, 12 * scale
    return (f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{IRIS}"/>'
            f'<ellipse cx="{cx + dx}" cy="{cy + dy}" rx="{4.2 * scale}" ry="{7 * scale}" fill="{PUPIL}"/>'
            f'<circle cx="{cx + dx + 3}" cy="{cy + dy - 4}" r="2.6" fill="#fff"/>')


def eye_arc_happy(cx, cy):
    return (f'<path d="M{cx - 10} {cy + 3} Q{cx} {cy - 10} {cx + 10} {cy + 3}" fill="none" '
            f'stroke="{INK}" stroke-width="4.5" stroke-linecap="round"/>')


def eye_calm(cx, cy):
    return (f'<path d="M{cx - 10} {cy} Q{cx} {cy + 7} {cx + 10} {cy}" fill="none" '
            f'stroke="{INK}" stroke-width="4.2" stroke-linecap="round"/>')


def brow(x1, y1, x2, y2):
    return (f'<path d="M{x1} {y1} L{x2} {y2}" stroke="{INK}" stroke-width="4" '
            f'stroke-linecap="round"/>')


MOUTHS = {
    "smile": f'<path d="M88 146 Q94 153 100 146 Q106 153 112 146" fill="none" stroke="{INK}" stroke-width="3.4" stroke-linecap="round"/>',
    "open": (f'<path d="M86 145 Q100 172 114 145 Z" fill="#8E3F4E" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
             f'<path d="M92 157 Q100 164 108 157" fill="#E58A99"/>'),
    "flat": f'<path d="M91 149 Q100 146 110 150" fill="none" stroke="{INK}" stroke-width="3.4" stroke-linecap="round"/>',
    "worried": f'<path d="M89 152 Q100 144 111 152" fill="none" stroke="{INK}" stroke-width="3.4" stroke-linecap="round"/>',
    "o": f'<ellipse cx="100" cy="151" rx="7" ry="8.5" fill="#8E3F4E" stroke="{INK}" stroke-width="3"/>',
}

MOODS = {
    "happy": dict(eyes=lambda: eye_open(74, 104) + eye_open(126, 104), mouth="smile", blush=True, brows=""),
    "cheering": dict(eyes=lambda: eye_arc_happy(74, 104) + eye_arc_happy(126, 104), mouth="open", blush=True, brows=""),
    "thinking": dict(eyes=lambda: eye_open(74, 104, 3, -4) + eye_open(126, 104, 3, -4), mouth="flat", blush=False,
                     brows=brow(62, 84, 84, 86) + brow(116, 82, 138, 76)),
    "worried": dict(eyes=lambda: eye_open(74, 106, 0, 1) + eye_open(126, 106, 0, 1), mouth="worried", blush=False,
                    brows=brow(62, 88, 84, 80) + brow(116, 80, 138, 88)),
    "alarmed": dict(eyes=lambda: eye_open(74, 104, 0, 0, 1.18) + eye_open(126, 104, 0, 0, 1.18), mouth="o", blush=False,
                    brows=brow(62, 80, 84, 76) + brow(116, 76, 138, 80)),
    "calm": dict(eyes=lambda: eye_calm(74, 106) + eye_calm(126, 106), mouth="smile", blush=True, brows=""),
}


def build(mood: str) -> str:
    m = MOODS[mood]
    ears = (f'<circle cx="50" cy="60" r="24" fill="{SPOT}"/><circle cx="50" cy="62" r="18" fill="{FUR}"/>'
            f'<circle cx="51" cy="64" r="10" fill="{EAR_IN}"/>'
            f'<circle cx="150" cy="60" r="24" fill="{SPOT}"/><circle cx="150" cy="62" r="18" fill="{FUR}"/>'
            f'<circle cx="149" cy="64" r="10" fill="{EAR_IN}"/>')
    scarf = (f'<path d="M40 168 Q100 196 160 168 L166 186 Q100 214 34 186 Z" fill="{SCARF}"/>'
             f'<path d="M132 182 L152 214 L130 210 L122 186 Z" fill="{SCARF_DARK}"/>'
             f'<path d="M58 184 Q100 200 142 184" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="3"/>')
    body = f'<path d="M52 150 Q48 206 60 220 L140 220 Q152 206 148 150 Z" fill="{FUR_SHADE}"/>'
    head = (f'<ellipse cx="100" cy="112" rx="72" ry="64" fill="{FUR}"/>'
            f'<path d="M34 128 Q40 170 100 176 Q160 170 166 128 Q150 160 100 162 Q50 160 34 128 Z" fill="{FUR_SHADE}"/>')
    spots = (rosette(86, 62, 6, 20) + rosette(112, 58, 6.5, -30) + rosette(100, 76, 5, 60) +
             dot(72, 70) + dot(128, 72) + dot(99, 50, 2.6) +
             rosette(46, 116, 6, 90) + rosette(154, 116, 6, -60) + dot(42, 136, 2.8) + dot(158, 136, 2.8))
    blush = (f'<ellipse cx="58" cy="132" rx="11" ry="6" fill="{BLUSH}" opacity=".7"/>'
             f'<ellipse cx="142" cy="132" rx="11" ry="6" fill="{BLUSH}" opacity=".7"/>') if m["blush"] else ""
    muzzle = (f'<ellipse cx="86" cy="138" rx="20" ry="16" fill="{MUZZLE}"/>'
              f'<ellipse cx="114" cy="138" rx="20" ry="16" fill="{MUZZLE}"/>')
    whiskers = "".join(dot(x, y, 1.8) for x, y in [(80, 136), (86, 142), (74, 142), (120, 136), (114, 142), (126, 142)])
    nose = f'<path d="M92 126 Q100 122 108 126 Q104 136 100 137 Q96 136 92 126 Z" fill="{NOSE}"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 220">'
            f'{ears}{body}{scarf}{head}{spots}{blush}{muzzle}{whiskers}{nose}'
            f'{m["brows"]}{m["eyes"]()}{MOUTHS[m["mouth"]]}</svg>')


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "assets" / "alan"
    out.mkdir(parents=True, exist_ok=True)
    for mood in MOODS:
        (out / f"{mood}.svg").write_text(build(mood), encoding="utf-8")
    print("ok:", ", ".join(MOODS))
