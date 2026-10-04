"""
Fusionne un katana en plusieurs morceaux (ex. Blade + Hilt) en un seul objet,
place le pivot sur la poignée, met la lame à la verticale, règle la taille
et exporte en FBX (pour Cascadeur) et en GLB (pour Godot).

Utilisation dans Blender :
  1. Ouvre l'onglet "Scripting" (en haut de Blender).
  2. Clique sur "Open", choisis ce fichier.
  3. Modifie INPUT_FILE ci-dessous avec le chemin de ton katana.
  4. Clique sur le bouton ▶ (Run Script).

Utilisation en ligne de commande :
  blender --background --python merge_katana.py -- chemin/katana.fbx [dossier_sortie]
"""

import os
import sys

import bpy
from mathutils import Matrix, Vector

# --- Réglages -----------------------------------------------------------------

# Chemin du katana d'origine (FBX, OBJ, GLB/GLTF ou BLEND).
# Exemple Windows : r"C:\Users\danny\Desktop\katana\source\katana.fbx"
INPUT_FILE = r""

# Dossier de sortie (vide = même dossier que le fichier d'origine).
OUTPUT_DIR = r""

# Longueur totale du katana en mètres (un vrai katana fait environ 1 m).
TARGET_LENGTH = 1.0

# Position du pivot sur la poignée : 0.0 = juste sous la garde,
# 1.0 = au bout du manche. 0.2 place la main près de la garde.
GRIP_POSITION = 0.2

# -----------------------------------------------------------------------------


def parse_cli_args():
    if "--" not in sys.argv:
        return
    args = sys.argv[sys.argv.index("--") + 1:]
    global INPUT_FILE, OUTPUT_DIR
    if args:
        INPUT_FILE = args[0]
    if len(args) > 1:
        OUTPUT_DIR = args[1]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
    else:
        raise RuntimeError(f"Format non supporté : {ext}")


def world_bbox(objects):
    points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def find_blade(meshes):
    for o in meshes:
        if "blade" in o.name.lower() or "lame" in o.name.lower():
            return o
    # Sinon : le morceau le plus long est la lame.
    return max(meshes, key=lambda o: max(o.dimensions))


def main():
    parse_cli_args()
    if not INPUT_FILE:
        raise RuntimeError("Renseigne INPUT_FILE en haut du script.")
    path = os.path.abspath(os.path.expanduser(INPUT_FILE))

    if not path.lower().endswith(".blend"):
        reset_scene()
    import_model(path)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("Aucun maillage trouvé dans le fichier.")
    print("Morceaux trouvés :", [o.name for o in meshes])

    # Mesurer la lame et le manche avant la fusion.
    blade = find_blade(meshes)
    others = [o for o in meshes if o is not blade] or meshes
    all_lo, all_hi = world_bbox(meshes)
    size = all_hi - all_lo
    axis = max(range(3), key=lambda i: size[i])  # axe de la longueur
    blade_lo, blade_hi = world_bbox([blade])
    hilt_lo, hilt_hi = world_bbox(others)

    # De quel côté se trouve la pointe de la lame ?
    blade_center = (blade_lo[axis] + blade_hi[axis]) / 2
    hilt_center = (hilt_lo[axis] + hilt_hi[axis]) / 2
    tip_dir = 1.0 if blade_center > hilt_center else -1.0

    # Point de prise : entre la garde et le bout du manche.
    guard_end = hilt_hi[axis] if tip_dir > 0 else hilt_lo[axis]
    pommel_end = all_lo[axis] if tip_dir > 0 else all_hi[axis]
    grip = (hilt_lo + hilt_hi) / 2
    grip[axis] = guard_end + (pommel_end - guard_end) * GRIP_POSITION

    # Détacher les morceaux de leurs parents (souvent des Empty dans les FBX).
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)

    # Fusion (équivalent de Ctrl + J).
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = blade
    if len(meshes) > 1:
        bpy.ops.object.join()
    katana = bpy.context.view_layer.objects.active
    katana.name = "Katana"
    katana.data.name = "Katana"

    # Appliquer les transformations dans le maillage (équivalent de Ctrl + A).
    katana.data.transform(katana.matrix_world)
    katana.matrix_world = Matrix.Identity(4)

    # Pivot sur la poignée, lame vers le haut (+Z), longueur voulue.
    tip_vec = Vector((0, 0, 0))
    tip_vec[axis] = tip_dir
    rot = tip_vec.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()
    scale = TARGET_LENGTH / size[axis]
    katana.data.transform(Matrix.Scale(scale, 4) @ rot @ Matrix.Translation(-grip))
    katana.data.update()

    # Export.
    out_dir = OUTPUT_DIR or os.path.dirname(path)
    os.makedirs(out_dir, exist_ok=True)
    fbx_path = os.path.join(out_dir, "katana.fbx")
    glb_path = os.path.join(out_dir, "katana.glb")

    bpy.ops.object.select_all(action="DESELECT")
    katana.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        object_types={"MESH"},
        apply_scale_options="FBX_SCALE_ALL",
        path_mode="COPY",
        embed_textures=True,
    )
    bpy.ops.export_scene.gltf(filepath=glb_path, use_selection=True, export_format="GLB")

    d = katana.dimensions
    print(f"Katana fusionné : {d.x:.2f} x {d.y:.2f} x {d.z:.2f} m")
    print("Exporté :", fbx_path)
    print("Exporté :", glb_path)


main()
