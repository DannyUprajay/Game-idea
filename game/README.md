# Mage Volant

Jeu de super-pouvoirs en monde ouvert inspiré d'inFamous, fait avec Godot 4.
Tout est généré par code (ville, personnages, effets) : aucun modèle à importer.

La ville est tombée aux mains de la Milice Rouge. Absorbe l'électricité de la ville
pour alimenter tes pouvoirs, détruis les trois relais ennemis, puis affronte le Colosse.
Tes choix (soigner les civils ou absorber leur vie) décident de ton karma, de la
couleur de tes pouvoirs et de la fin du jeu.

## Ouvrir le jeu
1. Dans Godot (4.3 ou plus récent) : **Importer** → choisis `project.godot`.
2. Appuie sur **F5**.

## Commandes
| Touche | Action |
|---|---|
| ZQSD / WASD | Se déplacer |
| Souris | Viser |
| Espace | Sauter ; en l'air, appuyer encore pour s'envoler, puis monter |
| F | Voler / atterrir |
| Ctrl ou C | Descendre |
| Maj | Courir ; en vol : turbo (traverse antennes et colonnes) |
| Clic gauche (maintenu) | Boules d'énergie |
| E | Onde de choc (niveau 2) |
| Clic droit | Trou noir (niveau 3) |
| R (maintenu) | Absorber l'électricité (lampadaire, voiture, générateur) / soigner un civil blessé |
| T (maintenu) | Absorber la vie d'un civil blessé (infâme) |
| Tab | Améliorations |
| Échap | Pause |
| H | Cacher / afficher l'aide |

## Déroulement
1. **Recharge-toi** sur le générateur de la place centrale.
2. **Choisis** : soigner ou absorber le civil blessé près de la fontaine.
3. **Détruis les 3 relais** de la Milice Rouge (le marqueur jaune montre le plus proche).
4. **Bats le Colosse.** La fin dépend de ton karma : Héros, Justicier ou Tyran.

## Karma
| Action | Karma |
|---|---|
| Soigner un civil blessé | + |
| Absorber la vie d'un civil | − |
| Tuer un civil (tirs, explosions, voitures qui explosent...) | − |

Plus tu es héroïque, plus tes pouvoirs deviennent bleus ; plus tu es infâme, plus ils deviennent rouges.

## Où modifier quoi
| Fichier | Contenu |
|---|---|
| `scripts/main.gd` | Missions, karma, XP, améliorations, apparition des personnages |
| `scripts/city.gd` | Génération de la ville |
| `scripts/player.gd` | Déplacements, vol, pouvoirs, absorption d'énergie |
| `scripts/soldier.gd`, `scripts/enemy.gd` | Soldats et drones ennemis |
| `scripts/relay.gd`, `scripts/boss.gd` | Relais ennemis et boss final |
| `scripts/civilian.gd` | Civils |
| `scripts/car.gd`, `scripts/energy_source.gd` | Voitures, lampadaires, générateurs |
| `scripts/hud.gd`, `scripts/menus.gd` | Interface et menus |
