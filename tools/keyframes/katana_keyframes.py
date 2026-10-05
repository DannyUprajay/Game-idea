"""
Génère une planche de keyframes (poses clés) pour un combo au katana,
dans un style croquis / mannequin, à utiliser comme référence dans Cascadeur.

    python3 tools/keyframes/katana_keyframes.py

Sortie : docs/animation/keyframes_katana_combo.svg

Chaque pose est décrite par quelques valeurs (bassin, inclinaison du buste,
position des mains, angle du sabre, position des pieds) ; bras et jambes sont
calculés en cinématique inverse pour garder des longueurs de membres correctes.
"""

import math
import os
import random

# --- Proportions (1 unité ≈ 1 m) ---------------------------------------------
TORSO = 0.56      # bassin -> base du cou
NECK = 0.08
HEAD_R = 0.105
UPPER_ARM = 0.30
FOREARM = 0.28
THIGH = 0.46
SHIN = 0.45
ANKLE_H = 0.07
FOOT = 0.16
GRIP = 0.25       # longueur de la poignée (tsuka)
BLADE = 0.72      # longueur de la lame

SCALE = 112       # pixels par unité
CELL_W = 300
CELL_H = 300
GROUND_Y = 284    # position du sol dans une case (pixels)
ORIGIN_X = 0.78   # décalage horizontal de l'origine dans une case (unités)

INK = "#2b2b2b"
INK_FAR = "#a3a3a3"
ACTION = "#d9534f"
SMEAR = "#3a8fd9"


# --- Petits outils de géométrie ----------------------------------------------
def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def length(a):
    return math.hypot(a[0], a[1])


def norm(a):
    l = length(a) or 1.0
    return (a[0] / l, a[1] / l)


def perp(a):
    return (-a[1], a[0])


def from_angle(deg):
    r = math.radians(deg)
    return (math.cos(r), math.sin(r))


def ik(root, target, l1, l2, bend):
    """Résout un membre à 2 segments. bend = +1 / -1 choisit le côté du coude/genou."""
    d = sub(target, root)
    dist = min(length(d), (l1 + l2) * 0.999)
    dist = max(dist, abs(l1 - l2) + 1e-3)
    dirn = norm(d)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    mid = add(add(root, mul(dirn, a)), mul(perp(dirn), h * bend))
    end = add(root, mul(dirn, dist))
    return mid, end


# --- Calcul d'une pose -------------------------------------------------------
def solve(p):
    pel = p["pel"]
    t_dir = from_angle(90 - p["tor"])          # direction du buste
    neck_base = add(pel, mul(t_dir, TORSO))
    head_dir = from_angle(90 - p["tor"] - p.get("head", 0))
    head_c = add(neck_base, mul(head_dir, NECK + HEAD_R))

    side = perp(t_dir)
    sh = add(neck_base, mul(t_dir, -0.06))
    sh_near = add(sh, mul(side, -0.025))
    sh_far = add(sh, mul(side, 0.035))

    sw = from_angle(p["sw"])
    hand_front = p["hand"]
    hand_back = add(hand_front, mul(sw, -0.17))
    if p.get("one_hand"):
        hand_back = p["free_hand"]

    el_near, hn = ik(sh_near, hand_front, UPPER_ARM, FOREARM, p.get("elbow_n", -1))
    el_far, hf = ik(sh_far, hand_back, UPPER_ARM, FOREARM, p.get("elbow_f", -1))

    hip_near = add(pel, mul(side, -0.03))
    hip_far = add(pel, mul(side, 0.03))
    ff = p["front_foot"]       # (x, levée du talon en degrés)
    bf = p["back_foot"]
    ankle_f = (ff[0], ANKLE_H + ff[2] if len(ff) > 2 else ANKLE_H)
    ankle_b = (bf[0], ANKLE_H + bf[2] if len(bf) > 2 else ANKLE_H)
    knee_f, ankle_f = ik(hip_near, ankle_f, THIGH, SHIN, 1)
    knee_b, ankle_b = ik(hip_far, ankle_b, THIGH, SHIN, 1)

    guard = add(hand_front, mul(sw, 0.035))
    pommel = add(hand_front, mul(sw, -(GRIP - 0.035)))
    tip = add(guard, mul(sw, BLADE))

    return dict(
        pel=pel, t_dir=t_dir, neck_base=neck_base, head_c=head_c, head_dir=head_dir,
        sh_near=sh_near, sh_far=sh_far, el_near=el_near, el_far=el_far,
        hand_near=hn, hand_far=hf, hip_near=hip_near, hip_far=hip_far,
        knee_f=knee_f, knee_b=knee_b, ankle_f=ankle_f, ankle_b=ankle_b,
        heel_f=ff[1], heel_b=bf[1], sw=sw, guard=guard, pommel=pommel, tip=tip,
    )


# --- Dessin -------------------------------------------------------------------
class Pen:
    """Convertit les unités en pixels et produit des traits « crayon »."""

    def __init__(self, ox, oy, seed):
        self.ox, self.oy = ox, oy
        self.rng = random.Random(seed)
        self.out = []

    def pt(self, p):
        return (self.ox + (p[0] + ORIGIN_X) * SCALE, self.oy + GROUND_Y - p[1] * SCALE)

    def j(self, amount=0.9):
        return self.rng.uniform(-amount, amount)

    def limb(self, a, b, wa, wb, color, bulge=0.25):
        """Membre effilé : contour fermé, légèrement bombé, rempli de blanc."""
        A, B = self.pt(a), self.pt(b)
        d = norm(sub(B, A))
        n = perp(d)
        wa, wb = wa * SCALE, wb * SCALE
        L = length(sub(B, A))
        m = add(A, mul(d, L * 0.45))
        wm = (wa + wb) / 2 * (1 + bulge)
        p1, p2 = add(A, mul(n, wa)), add(B, mul(n, wb))
        p3, p4 = sub(B, mul(n, wb)), sub(A, mul(n, wa))
        c1, c2 = add(m, mul(n, wm)), sub(m, mul(n, wm))
        capB = add(B, mul(d, wb * 1.3))
        capA = sub(A, mul(d, wa * 1.3))
        path = (
            f"M{p1[0]:.1f},{p1[1]:.1f} Q{c1[0]:.1f},{c1[1]:.1f} {p2[0]:.1f},{p2[1]:.1f} "
            f"Q{capB[0]:.1f},{capB[1]:.1f} {p3[0]:.1f},{p3[1]:.1f} "
            f"Q{c2[0]:.1f},{c2[1]:.1f} {p4[0]:.1f},{p4[1]:.1f} "
            f"Q{capA[0]:.1f},{capA[1]:.1f} {p1[0]:.1f},{p1[1]:.1f} Z"
        )
        self.out.append(f'<path d="{path}" fill="#fff" stroke="{color}" stroke-width="1.5" stroke-linejoin="round"/>')
        # second passage léger, décalé, pour l'effet croquis
        jp1 = (p1[0] + self.j(), p1[1] + self.j())
        jp2 = (p2[0] + self.j(), p2[1] + self.j())
        jc1 = (c1[0] + self.j(1.5), c1[1] + self.j(1.5))
        self.out.append(
            f'<path d="M{jp1[0]:.1f},{jp1[1]:.1f} Q{jc1[0]:.1f},{jc1[1]:.1f} {jp2[0]:.1f},{jp2[1]:.1f}" '
            f'fill="none" stroke="{color}" stroke-width="0.8" opacity="0.45"/>'
        )

    def foot(self, ankle, heel_raise, color):
        A = self.pt(ankle)
        ang = math.radians(heel_raise)
        toe = (ankle[0] + FOOT * math.cos(ang), max(ankle[1] - ANKLE_H - FOOT * math.sin(ang) + 0.01, 0.01))
        heel = (ankle[0] - 0.04, max(ankle[1] - ANKLE_H + 0.01 + math.sin(ang) * 0.05, 0.01))
        T, H = self.pt(toe), self.pt(heel)
        self.out.append(
            f'<path d="M{A[0]-4:.1f},{A[1]:.1f} Q{H[0]-2:.1f},{H[1]:.1f} {H[0]+3:.1f},{H[1]:.1f} '
            f'L{T[0]:.1f},{T[1]:.1f} Q{T[0]-6:.1f},{T[1]-7:.1f} {A[0]+4:.1f},{A[1]:.1f} Z" '
            f'fill="#fff" stroke="{color}" stroke-width="1.4" stroke-linejoin="round"/>'
        )

    def hand(self, p, color):
        P = self.pt(p)
        self.out.append(f'<circle cx="{P[0]:.1f}" cy="{P[1]:.1f}" r="4.6" fill="#fff" stroke="{color}" stroke-width="1.4"/>')

    def katana(self, s):
        G, T, Pm = self.pt(s["guard"]), self.pt(s["tip"]), self.pt(s["pommel"])
        d = norm(sub(T, G))
        n = perp(d)
        L = length(sub(T, G))
        # légère courbure (sori), côté dos de la lame
        c = add(add(G, mul(d, L * 0.55)), mul(n, -L * 0.035))
        edge = add(G, mul(n, 1.6))
        self.out.append(
            f'<path d="M{G[0]:.1f},{G[1]:.1f} Q{c[0]:.1f},{c[1]:.1f} {T[0]:.1f},{T[1]:.1f}" '
            f'fill="none" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/>'
        )
        self.out.append(
            f'<path d="M{edge[0]:.1f},{edge[1]:.1f} Q{c[0]+n[0]*1.6:.1f},{c[1]+n[1]*1.6:.1f} {T[0]:.1f},{T[1]:.1f}" '
            f'fill="none" stroke="#fff" stroke-width="0.7"/>'
        )
        self.out.append(
            f'<line x1="{Pm[0]:.1f}" y1="{Pm[1]:.1f}" x2="{G[0]:.1f}" y2="{G[1]:.1f}" '
            f'stroke="{INK}" stroke-width="4.2" stroke-linecap="round"/>'
        )
        t1, t2 = add(G, mul(n, 6)), sub(G, mul(n, 6))
        self.out.append(
            f'<line x1="{t1[0]:.1f}" y1="{t1[1]:.1f}" x2="{t2[0]:.1f}" y2="{t2[1]:.1f}" '
            f'stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
        )

    def head(self, s, color):
        C = self.pt(s["head_c"])
        hd = s["head_dir"]
        ang = math.degrees(math.atan2(-hd[1], hd[0])) + 90
        r = HEAD_R * SCALE
        self.out.append(
            f'<ellipse cx="{C[0]:.1f}" cy="{C[1]:.1f}" rx="{r*0.82:.1f}" ry="{r:.1f}" '
            f'transform="rotate({ang:.1f} {C[0]:.1f} {C[1]:.1f})" fill="#fff" stroke="{color}" stroke-width="1.5"/>'
        )
        # menton / direction du regard
        fwd = perp(hd)
        fwd = (-fwd[0], -fwd[1]) if fwd[0] < 0 else fwd
        chin = add(s["head_c"], add(mul(fwd, HEAD_R * 0.75), mul(hd, -HEAD_R * 0.55)))
        Ch = self.pt(chin)
        mid = self.pt(add(s["head_c"], mul(fwd, HEAD_R * 0.95)))
        self.out.append(
            f'<path d="M{mid[0]:.1f},{mid[1]:.1f} Q{mid[0]+1:.1f},{mid[1]+6:.1f} {Ch[0]:.1f},{Ch[1]:.1f}" '
            f'fill="none" stroke="{color}" stroke-width="1.2"/>'
        )

    def hair(self, s, flow):
        """Queue de cheval qui traîne derrière le mouvement."""
        back = add(s["head_c"], add(mul(s["head_dir"], HEAD_R * 0.6), (-HEAD_R * 0.7, 0)))
        end = add(back, flow)
        ctrl = add(back, (flow[0] * 0.3, flow[1] * 0.9 + 0.05))
        B, E, Cc = self.pt(back), self.pt(end), self.pt(ctrl)
        for k in range(3):
            o = (k - 1) * 2.2
            self.out.append(
                f'<path d="M{B[0]:.1f},{B[1]+o:.1f} Q{Cc[0]+o:.1f},{Cc[1]:.1f} {E[0]+o*1.5:.1f},{E[1]+o:.1f}" '
                f'fill="none" stroke="{INK}" stroke-width="{1.2 - k*0.25:.2f}" opacity="0.8"/>'
            )

    def line_of_action(self, s):
        a = self.pt(s["ankle_b"])
        b = self.pt(s["pel"])
        c = self.pt(add(s["head_c"], mul(s["head_dir"], HEAD_R)))
        ctrl = (2 * b[0] - (a[0] + c[0]) / 2, 2 * b[1] - (a[1] + c[1]) / 2)
        self.out.append(
            f'<path d="M{a[0]:.1f},{a[1]:.1f} Q{ctrl[0]:.1f},{ctrl[1]:.1f} {c[0]:.1f},{c[1]:.1f}" '
            f'fill="none" stroke="{ACTION}" stroke-width="2" opacity="0.35" stroke-dasharray="1 0"/>'
        )

    def smear(self, prev_tip, tip, prev_hand, hand, bow):
        """Arc de mouvement de la lame entre la pose précédente et celle-ci."""
        for k, f in enumerate((1.0, 0.85, 0.7, 0.55)):
            a = add(prev_hand, mul(sub(prev_tip, prev_hand), f))
            b = add(hand, mul(sub(tip, hand), f))
            mid = mul(add(a, b), 0.5)
            off = mul(perp(norm(sub(b, a))), bow * length(sub(b, a)) * f)
            A, B, C = self.pt(a), self.pt(b), self.pt(add(mid, off))
            self.out.append(
                f'<path d="M{A[0]:.1f},{A[1]:.1f} Q{C[0]:.1f},{C[1]:.1f} {B[0]:.1f},{B[1]:.1f}" '
                f'fill="none" stroke="{SMEAR}" stroke-width="{2.4 - k*0.5:.1f}" opacity="{0.55 - k*0.1:.2f}" '
                f'stroke-linecap="round"/>'
            )

    def speed_lines(self, tip, sw):
        d = sw
        for k in range(4):
            base = add(tip, add(mul(perp(d), (k - 1.5) * 0.06), mul(d, -0.15 - k * 0.04)))
            a = self.pt(base)
            b = self.pt(add(base, mul(d, -0.25)))
            self.out.append(
                f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" '
                f'stroke="{INK}" stroke-width="0.9" opacity="0.5"/>'
            )


def draw_pose(pen, s, p):
    pen.out.append(
        f'<line x1="{pen.ox+12}" y1="{pen.oy+GROUND_Y}" x2="{pen.ox+CELL_W-12}" y2="{pen.oy+GROUND_Y}" '
        f'stroke="#cfcfcf" stroke-width="1" stroke-dasharray="4 4"/>'
    )
    pen.line_of_action(s)
    if p.get("smear"):
        pen.smear(*p["smear"])
    # membres éloignés (gris clair), puis corps, puis membres proches
    pen.limb(s["hip_far"], s["knee_b"], 0.065, 0.045, INK_FAR)
    pen.limb(s["knee_b"], s["ankle_b"], 0.045, 0.03, INK_FAR)
    pen.foot(s["ankle_b"], s["heel_b"], INK_FAR)
    pen.limb(s["sh_far"], s["el_far"], 0.042, 0.032, INK_FAR)
    pen.limb(s["el_far"], s["hand_far"], 0.032, 0.024, INK_FAR)
    if p.get("one_hand"):
        pen.hand(s["hand_far"], INK_FAR)
    if p.get("hair"):
        pen.hair(s, p["hair"])
    waist = add(s["pel"], mul(s["t_dir"], 0.2))
    pen.limb(s["pel"], waist, 0.11, 0.085, INK, bulge=0.05)
    pen.limb(waist, s["neck_base"], 0.085, 0.12, INK, bulge=0.12)
    pen.limb(s["neck_base"], add(s["neck_base"], mul(s["head_dir"], NECK + 0.02)), 0.032, 0.03, INK, 0)
    pen.head(s, INK)
    pen.limb(s["hip_near"], s["knee_f"], 0.07, 0.048, INK)
    pen.limb(s["knee_f"], s["ankle_f"], 0.048, 0.032, INK)
    pen.foot(s["ankle_f"], s["heel_f"], INK)
    pen.katana(s)
    if p.get("speed"):
        pen.speed_lines(s["tip"], s["sw"])
    pen.limb(s["sh_near"], s["el_near"], 0.045, 0.034, INK)
    pen.limb(s["el_near"], s["hand_near"], 0.034, 0.026, INK)
    pen.hand(s["hand_near"], INK)


# --- Les poses du combo ------------------------------------------------------
# pel : bassin (x, y) | tor : inclinaison du buste (° vers l'avant)
# hand : main avant (x, y) | sw : angle du sabre (0 = vers l'avant, 90 = vers le haut)
# front_foot / back_foot : (x, talon levé en °, [hauteur du pied])
GARDE = dict(pel=(0.0, 0.86), tor=6, head=-4, hand=(0.34, 1.02), sw=38,
             front_foot=(0.28, 0), back_foot=(-0.30, 18), hair=(-0.18, -0.22))

COMBO = [
    dict(
        title="Coup 1 · Coupe diagonale descendante (kesa-giri)",
        timing="≈ 0,9 s au total — lent à armer, très rapide à frapper",
        keys=[
            dict(GARDE, label="Garde", frame=0, note="Poids au centre, lame vers les yeux de l'ennemi"),
            dict(label="Armer", frame=9, note="Poids en arrière, sabre au-dessus de la tête",
                 pel=(-0.06, 0.83), tor=-10, head=6, hand=(0.02, 1.58), sw=158,
                 front_foot=(0.28, 0), back_foot=(-0.30, 10), hair=(-0.12, -0.28)),
            dict(label="IMPACT", frame=13, note="Fente avant, bras tendus — la lame arrive en 4 images",
                 pel=(0.26, 0.74), tor=24, head=-14, hand=(0.70, 1.02), sw=-8,
                 front_foot=(0.74, 0), back_foot=(-0.24, 28), hair=(-0.34, 0.02),
                 smear_from=1, smear_bow=-0.35, speed=True),
            dict(label="Suivi", frame=17, note="La lame continue vers le bas — ne pas l'arrêter net",
                 pel=(0.30, 0.70), tor=32, head=-18, hand=(0.58, 0.70), sw=-58,
                 front_foot=(0.74, 0), back_foot=(-0.24, 30), hair=(-0.30, 0.10)),
        ],
    ),
    dict(
        title="Coup 2 · Coupe remontante (kiri-age)",
        timing="≈ 0,6 s — enchaîne directement depuis le suivi du coup 1",
        keys=[
            dict(label="Armer", frame=0, note="Lame ramenée en bas derrière la hanche, buste tourné",
                 pel=(0.24, 0.70), tor=16, head=-10, hand=(0.18, 0.80), sw=-160,
                 front_foot=(0.74, 0), back_foot=(-0.20, 28), hair=(-0.30, -0.05)),
            dict(label="IMPACT", frame=5, note="Pousse sur la jambe arrière, la lame remonte en diagonale",
                 pel=(0.38, 0.80), tor=10, head=-12, hand=(0.76, 1.18), sw=42,
                 front_foot=(0.80, 0), back_foot=(-0.10, 40), hair=(-0.30, -0.18),
                 smear_from=0, smear_bow=0.45, speed=True),
            dict(label="Suivi", frame=10, note="Lame au-dessus, épaules ouvertes — prêt pour le final",
                 pel=(0.42, 0.85), tor=-4, head=4, hand=(0.52, 1.56), sw=118,
                 front_foot=(0.80, 0), back_foot=(0.02, 45), hair=(-0.18, -0.30)),
        ],
    ),
    dict(
        title="Coup 3 · Estoc en fente (tsuki) — coup final",
        timing="≈ 1,1 s — longue préparation, impact lourd, retour lent",
        keys=[
            dict(label="Armer", frame=0, note="Se ramasser : bas, sabre tiré en arrière à l'horizontale",
                 pel=(0.0, 0.66), tor=8, head=-6, hand=(0.08, 1.00), sw=4,
                 front_foot=(0.36, 0), back_foot=(-0.34, 24), hair=(-0.14, -0.26)),
            dict(label="IMPACT", frame=6, note="Grande fente, tout le corps derrière la pointe",
                 pel=(0.52, 0.62), tor=26, head=-20, hand=(1.06, 1.06), sw=3,
                 front_foot=(1.04, 0), back_foot=(-0.14, 35), hair=(-0.40, 0.08),
                 smear_from=0, smear_bow=0.0, speed=True),
            dict(label="Tenir", frame=14, note="Garder la pose 4-6 images : c'est ce qui donne du poids",
                 pel=(0.50, 0.60), tor=28, head=-20, hand=(1.02, 1.04), sw=2,
                 front_foot=(1.04, 0), back_foot=(-0.14, 35), hair=(-0.28, -0.12)),
            dict(GARDE, label="Retour en garde", frame=32, note="Revenir EXACTEMENT à la pose de garde",
                 pel=(0.42, 0.86), hand=(0.76, 1.02),
                 front_foot=(0.70, 0), back_foot=(0.12, 18)),
        ],
    ),
]


def build_svg():
    cols = max(len(r["keys"]) for r in COMBO)
    margin = 28
    header_h = 74
    row_head = 52
    note_h = 44
    width = margin * 2 + cols * CELL_W
    height = header_h + len(COMBO) * (row_head + CELL_H + note_h) + 40
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
        f'font-family="Helvetica, Arial, sans-serif">',
        f'<rect width="{width}" height="{height}" fill="#fbfaf7"/>',
        f'<text x="{margin}" y="40" font-size="26" font-weight="700" fill="{INK}">Combo katana — poses clés</text>',
        f'<text x="{margin}" y="62" font-size="13" fill="#666">Vue de profil · le personnage regarde à droite · '
        f'membres foncés = côté caméra, gris = côté opposé · '
        f'<tspan fill="{ACTION}">rouge</tspan> = ligne d\'action · <tspan fill="{SMEAR}">bleu</tspan> = trajectoire '
        f'de la lame · images à 30 fps</text>',
    ]
    y = header_h
    seed = 7
    for row in COMBO:
        out.append(f'<text x="{margin}" y="{y+26}" font-size="18" font-weight="700" fill="{INK}">{row["title"]}</text>')
        out.append(f'<text x="{margin}" y="{y+43}" font-size="12.5" fill="#777">{row["timing"]}</text>')
        y += row_head
        solved = [solve(k) for k in row["keys"]]
        for i, (k, s) in enumerate(zip(row["keys"], solved)):
            ox = margin + i * CELL_W
            out.append(f'<rect x="{ox+4}" y="{y}" width="{CELL_W-8}" height="{CELL_H+note_h-6}" rx="10" '
                       f'fill="#fff" stroke="#e4e1da"/>')
            if "smear_from" in k:
                prev = solved[k["smear_from"]]
                k = dict(k, smear=(prev["tip"], s["tip"], prev["hand_near"], s["hand_near"], k["smear_bow"]))
            pen = Pen(ox, y, seed)
            seed += 1
            draw_pose(pen, s, k)
            out.extend(pen.out)
            impact = k["label"] == "IMPACT"
            out.append(f'<text x="{ox+18}" y="{y+24}" font-size="15" font-weight="700" '
                       f'fill="{ACTION if impact else INK}">{i+1}. {k["label"]}</text>')
            out.append(f'<text x="{ox+CELL_W-18}" y="{y+24}" font-size="13" text-anchor="end" fill="#888">'
                       f'frame {k["frame"]}</text>')
            out.extend(wrap_note(k["note"], ox + 18, y + CELL_H + 4, CELL_W - 36))
        y += CELL_H + note_h
    out.append("</svg>")
    return "\n".join(out)


def wrap_note(text, x, y, w, size=12.5):
    max_chars = int(w / (size * 0.52))
    words, lines, cur = text.split(), [], ""
    for wd in words:
        if len(cur) + len(wd) + 1 > max_chars:
            lines.append(cur)
            cur = wd
        else:
            cur = f"{cur} {wd}".strip()
    lines.append(cur)
    return [f'<text x="{x}" y="{y + i*16}" font-size="{size}" fill="#555">{l}</text>' for i, l in enumerate(lines)]


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_dir = os.path.join(root, "docs", "animation")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "keyframes_katana_combo.svg")
    with open(path, "w", encoding="utf-8") as f:
        f.write(build_svg())
    print(path)
