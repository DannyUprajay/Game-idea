# Mage Volant

Prototype Godot 4 : un mage qui vole, lance des boules de feu avec ses mains,
crée des trous noirs et des ondes de choc contre des drones ennemis.

Tout est généré par code (personnage, décor, effets) : aucun modèle à importer.

## Ouvrir le jeu
1. Télécharge le dossier `game/` (sur GitHub : bouton **Code → Download ZIP**, puis dézippe).
2. Dans Godot (4.3 ou plus récent) : **Importer** → choisis `game/project.godot`.
3. Appuie sur **F5** (ou le bouton ▶ en haut à droite).

## Commandes
| Touche | Action |
|---|---|
| ZQSD / WASD | Se déplacer |
| Souris | Viser |
| Espace | Sauter — en l'air : s'envoler, puis monter |
| F | Voler / atterrir |
| Ctrl ou C | Descendre (au sol : atterrir) |
| Maj | Courir — en vol : turbo |
| Clic gauche (maintenu) | Boules de feu, une main après l'autre |
| Clic droit | Trou noir (aspire et broie les ennemis, puis explose) |
| E | Onde de choc autour de toi |
| H | Cacher / afficher l'aide |
| Échap | Libérer la souris |

## Où modifier quoi
| Fichier | Contenu |
|---|---|
| `scripts/player.gd` | Vitesses, vol, coût en énergie et recharge des pouvoirs |
| `scripts/projectile.gd` | Boules de feu (dégâts, taille, couleur) |
| `scripts/black_hole.gd` | Trou noir (durée, force d'attraction, explosion) |
| `scripts/shockwave.gd` | Onde de choc |
| `scripts/enemy.gd` | Drones ennemis (vie, vitesse, tirs) |
| `scripts/main.gd` | Monde, touches, apparition des ennemis |
| `scripts/hud.gd` | Interface (barres, score, aide) |
