# Publication manuelle sur GitHub

[← Retour au projet](../README.md)

Le projet est préparé pour un dépôt GitHub. Les commandes ci-dessous sont à exécuter par la personne qui publie. Aucun workflow de publication ou de déploiement n’est fourni.

## Présentation suggérée

| Champ GitHub | Valeur proposée |
| :--- | :--- |
| Nom du dépôt | `BiblioTech` |
| Description | `Bibliothèque Wi-Fi autonome et carte d’Europe hors ligne sur Raspberry Pi Zero W — Kiwix, ARMv6, Raspberry Pi OS 32 bits.` |
| Topics | `kiwix`, `raspberry-pi`, `pi-zero-w`, `offline`, `wifi-hotspot`, `openstreetmap`, `pmtiles`, `self-hosted` |

Le README utilise des images locales et des liens relatifs. Il peut être publié sous un autre nom de dépôt sans modifier ses liens. Les visuels SVG sont originaux ; leur palette jaune, cyan, magenta et noir reprend l’ambiance demandée. Aucun statut CI « réussi » n’est affiché avant une première exécution sur GitHub.

## Vérifier les fichiers

Depuis la racine du projet :

```bash
./tests/check.sh
```

Le dépôt doit contenir les sources, la documentation, le manifeste des contenus, les licences et la configuration d’exemple. `.gitignore` exclut notamment :

- `config.env` et les configurations privées ;
- `data/`, `build/` et `dist/` ;
- les ZIM, PMTiles, MBTiles, sources OSM et JAR ;
- `web/vendor/`, les caches et les journaux.

Les ressources de `web/vendor/` sont récupérées par l’installateur avec vérification des empreintes. Le projet reste donc utilisable à partir d’un clone propre, sans joindre les fichiers téléchargés pendant le développement.

## Créer le premier commit local

Si le dossier n’est pas encore un dépôt Git :

```bash
git init -b main
```

Préparer les sources et examiner exactement ce qui sera publié :

```bash
git add .
git status --short
git diff --cached --stat
git diff --cached
git diff --cached --check
```

Après votre vérification :

```bash
git commit -m "Initial commit: BiblioTech offline library"
```

## Créer le dépôt distant et envoyer le code

Sur GitHub, créer un dépôt **vide** sous le nom choisi. Ne pas ajouter de README, de licence ou de `.gitignore` à distance : ces fichiers sont déjà fournis ici. Adapter le compte et le nom dans la commande suivante :

```bash
git remote add origin git@github.com:VOTRE_COMPTE/BiblioTech.git
git push -u origin main
```

La commande `git push` réalise la publication. Si un dépôt distant est déjà configuré, examiner `git remote -v` et utiliser son URL au lieu d’ajouter un second `origin`.

Le workflow [Checks](../.github/workflows/ci.yml) s’exécutera sur les pushes et les pull requests, sous réserve que GitHub Actions soit activé. Il vérifie les scripts et tests sans télécharger les collections ni toucher un Raspberry Pi. Sa réussite ne constitue pas une validation matérielle.

## Après publication

Vérifier le rendu du README, le résultat du workflow et les liens. Renseigner la description et les topics, puis compléter la [validation sur le Pi](validation.md#vérifications-à-faire-sur-le-raspberry-pi) avant d’annoncer une version testée sur matériel. Le [journal des changements](../CHANGELOG.md) reste « Non publié » jusqu’à votre première version.

Référence : [créer et gérer un dépôt, documentation GitHub](https://docs.github.com/en/repositories/creating-and-managing-repositories/quickstart-for-repositories).
