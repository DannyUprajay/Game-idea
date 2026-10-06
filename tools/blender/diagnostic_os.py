"""
Diagnostic : pourquoi l'os sélectionné ne tourne pas ?

Utilisation : en mode Pose, sélectionne l'os (ex. le poignet), puis dans l'onglet
Scripting : Ouvrir ce fichier → ▶. Une fenêtre s'affiche avec le résultat.
"""

import bpy

lines = []


def say(text: str) -> None:
    lines.append(text)
    print(text)


obj = bpy.context.object
bone = bpy.context.active_pose_bone

if obj is None or obj.type != "ARMATURE" or bone is None:
    say("Aucun os actif : passe en mode Pose et clique sur l'os à tester.")
else:
    say(f"Os : {bone.name}   (mode de rotation : {bone.rotation_mode})")

    locks = [axis for axis, locked in zip("XYZ", bone.lock_rotation) if locked]
    if locks:
        say(f"!! Rotation VERROUILLÉE sur : {', '.join(locks)}  -> panneau N > Élément > Rotation : clique sur les cadenas")
    if bone.rotation_mode == "QUATERNION" and bone.lock_rotation_w:
        say("!! Rotation W verrouillée")

    for c in bone.constraints:
        state = "active" if (c.enabled and c.influence > 0.0) else "désactivée"
        say(f"Contrainte : {c.name} ({c.type}), influence {c.influence:.2f}, {state}")
        if c.type in {"COPY_ROTATION", "COPY_TRANSFORMS", "CHILD_OF", "DAMPED_TRACK", "TRACK_TO"} and c.enabled and c.influence > 0.99:
            say("   !! Cette contrainte impose la rotation : ta rotation est écrasée")

    # Pilotes (drivers) qui forceraient la rotation.
    anim = obj.animation_data
    if anim is not None:
        for d in anim.drivers:
            if f'pose.bones["{bone.name}"].rotation' in d.data_path:
                say(f"!! Un pilote (driver) contrôle : {d.data_path}")

    # Réglages IK/FK du rig (propriétés personnalisées des os, style Rigify).
    for pb in obj.pose.bones:
        for key in pb.keys():
            lowered = key.lower()
            if "ik_fk" in lowered or "ik/fk" in lowered or lowered.startswith("fk"):
                try:
                    value = float(pb[key])
                except (TypeError, ValueError):
                    continue
                side = bone.name.split(".")[-1] if "." in bone.name else ""
                if side and not pb.name.endswith(side):
                    continue
                mode = "FK" if value > 0.5 else "IK"
                say(f"Réglage {key} sur {pb.name} = {value:.2f}  -> mode {mode}")
    if "fk" in bone.name.lower():
        say("Cet os est un contrôleur FK : il n'agit que si le membre est en mode FK (réglage = 1.00)")
    if "ik" in bone.name.lower():
        say("Cet os est un contrôleur IK : il n'agit que si le membre est en mode IK (réglage = 0.00)")

    if not lines[1:]:
        say("Rien de bloquant trouvé sur cet os.")


def draw(self, _context):
    for text in lines:
        self.layout.label(text=text)


if bpy.context.window_manager is not None and not bpy.app.background:
    bpy.context.window_manager.popup_menu(draw, title="Diagnostic de l'os", icon="BONE_DATA")
