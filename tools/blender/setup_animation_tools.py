"""
Active les outils d'animation, de rig et d'import/export inclus avec Blender,
et règle quelques préférences pratiques pour animer des personnages de jeu.

Utilisation :
  1. Ouvre Blender, onglet "Scripting" (en haut).
  2. Clique sur "Open", choisis ce fichier, puis sur le bouton ▶ (Run Script).
  3. Lis le résultat dans la console : Window → Toggle System Console (Windows).

Les préférences sont sauvegardées : c'est à faire une seule fois.
"""

import addon_utils
import bpy

# Extensions incluses avec Blender (rien à télécharger).
ADDONS = {
    "rigify": "Rigify : crée un squelette complet avec contrôleurs en quelques clics",
    "pose_library": "Bibliothèque de poses : enregistre et réutilise tes poses clés",
    "io_scene_fbx": "Import/export FBX (Cascadeur, Mixamo, Godot)",
    "io_scene_gltf2": "Import/export glTF/GLB (le meilleur format pour Godot)",
    "io_anim_bvh": "Import BVH : fichiers de motion capture",
    "node_wrangler": "Node Wrangler : raccourcis pour les matériaux et textures",
}


def enable_addons() -> None:
    available = {m.__name__ for m in addon_utils.modules()}
    for module, description in ADDONS.items():
        if module not in available:
            print(f"  [absent]  {module} : pas inclus dans cette version de Blender")
            continue
        try:
            addon_utils.enable(module, default_set=True, persistent=True)
            print(f"  [activé]  {description}")
        except Exception as error:  # une extension en échec ne bloque pas les autres
            print(f"  [erreur]  {module} : {error}")


def set_preferences() -> None:
    prefs = bpy.context.preferences
    edit = prefs.edit
    # Nouvelles images clés en Bézier, poignées automatiques sans dépassement.
    edit.keyframe_new_interpolation_type = "BEZIER"
    edit.keyframe_new_handle_type = "AUTO_CLAMPED"
    # Plus d'annulations possibles.
    edit.undo_steps = 128
    print("  [réglé]   Interpolation par défaut : Bézier (poignées auto)")
    print("  [réglé]   128 annulations (Ctrl+Z)")


def set_scene_for_games() -> None:
    scene = bpy.context.scene
    # 30 images par seconde, comme dans le jeu.
    scene.render.fps = 30
    scene.render.fps_base = 1.0
    print("  [réglé]   Scène courante à 30 images par seconde")


print("\n=== Configuration de Blender pour l'animation ===")
enable_addons()
set_preferences()
set_scene_for_games()
bpy.ops.wm.save_userpref()
print("Préférences sauvegardées. Terminé !\n")
