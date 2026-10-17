#!/usr/bin/env bash
# =============================================================================
# PRÉPARATION CARTOGRAPHIQUE — SUR ORDINATEUR, PAS SUR LE PI ZERO W
# =============================================================================
# Usage : ./scripts/prepare-map.sh [region_geofabrik] [dossier_de_travail]
# Exemple : MAP_JAVA_HEAP=1g ./scripts/prepare-map.sh monaco ./build/monaco
# Défaut : Europe complète, fichier final build/maps/europe.pmtiles.
#
# Prérequis : ordinateur 64 bits, Java 21+, Python 3, curl, accès Internet,
# suffisamment de RAM et d'espace SSD pour les sources ET les intermédiaires.
# Aucune installation système ni copie vers le Pi n'est faite par ce script.
# Le fichier final utilise le schéma OpenMapTiles attendu par web/map/map.js.
#
# Maintenance de Planetiler : mettre à jour ensemble la version dans le chemin
# du JAR, son URL, son empreinte SHA-256, les paramètres et la documentation.
# Tester une petite région avant de relancer plusieurs heures de calcul Europe.
# =============================================================================

# Arrêter les erreurs non gérées : une conversion ou une validation échouée ne
# doit jamais conduire à renommer le fichier intermédiaire en carte finale.
set -Eeuo pipefail

# Chemins basés sur l'emplacement du script pour accepter un lancement depuis
# n'importe quel dossier. WORK peut être un autre volume monté par l'utilisateur.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Paramètres positionnels : identifiant Geofabrik (ex. europe/france) et stockage.
# Variables d'environnement : mémoire du tas Java et niveau de zoom des tuiles.
# Le tas Java n'est pas toute la mémoire du processus : garder de la marge pour
# la mémoire native, les fichiers mappés et le système d'exploitation.
AREA=${1:-europe}
WORK=${2:-"$ROOT/build/maps"}
HEAP=${MAP_JAVA_HEAP:-20g}
MAXZOOM=${MAP_MAXZOOM:-14}

# Restreindre les valeurs avant de construire des noms et arguments. Les slashs
# sont utiles aux sous-régions ; .. est refusé. Ceci ne vérifie pas l'existence
# d'une région : Planetiler résoudra son identifiant pendant le téléchargement.
[[ "$AREA" =~ ^[a-z0-9/-]+$ && "$AREA" != *..* ]] || { echo 'Région Geofabrik invalide.' >&2; exit 1; }

# Autoriser des tailles explicites comme 20g ou 1024m, sans arguments Java libres.
# La limite du zoom est celle choisie par ce projet, pas une détection automatique
# des possibilités de chaque version de Planetiler.
[[ "$HEAP" =~ ^[0-9]+[gGmM]$ ]] || { echo 'MAP_JAVA_HEAP doit ressembler à 20g.' >&2; exit 1; }
[[ "$MAXZOOM" =~ ^([0-9]|1[0-4])$ ]] || { echo 'MAP_MAXZOOM doit être compris entre 0 et 14.' >&2; exit 1; }

# Refuser le Pi Zero 32 bits. Vérifier la présence des commandes ne vérifie pas
# la version du runtime Java : une version incompatible échouera au lancement.
[[ $(getconf LONG_BIT) == 64 ]] || { echo 'La conversion exige un ordinateur 64 bits.' >&2; exit 1; }
command -v java >/dev/null || { echo 'Installer Java 21 ou plus récent.' >&2; exit 1; }
command -v python3 >/dev/null

# Normaliser WORK en chemin absolu avant le cd utilisé pour lancer Planetiler.
# Les fichiers de travail par défaut du moteur resteront ainsi sur ce volume.
mkdir -p "$WORK"
WORK=$(cd -- "$WORK" && pwd)

# Un identifiant europe/france devient europe-france.pmtiles, sans sous-dossier
# implicite. Le fichier final existant est conservé : son remplacement doit être
# décidé explicitement en le déplaçant avant une nouvelle génération.
NAME=${AREA//\//-}
TARGET="$WORK/$NAME.pmtiles"
[[ ! -e "$TARGET" ]] || { echo "$TARGET existe déjà. Le déplacer pour le remplacer." >&2; exit 1; }

# Ces ordres de grandeur concernent l'Europe ; ils ne réservent pas les ressources
# et ne remplacent pas les contrôles de capacité réalisés ensuite par Planetiler.
echo "Conversion Geofabrik $AREA → $TARGET (zoom $MAXZOOM)."
echo "Europe : prévoir un PC de 32 Go de RAM, environ 350 Go de SSD libre et plusieurs heures."
echo 'Ces besoins varient avec les données ; Planetiler contrôle aussi les ressources.'

# Version figée pour rendre le format produit et les options reproductibles.
# Réutiliser le JAR local, mais vérifier son empreinte à chaque exécution.
JAR="$WORK/planetiler-0.10.2.jar"
if [[ ! -f "$JAR" ]]; then
    # -f : erreur sur statut HTTP d'échec ; -L : suivre les redirections GitHub.
    # Restreindre protocole initial et redirections à HTTPS. --continue-at -
    # reprend le fichier .part ; --retry traite les échecs transitoires de curl.
    # Le nom final n'est utilisé qu'une fois le transfert terminé avec succès.
    curl -fL --proto '=https' --proto-redir '=https' --retry 5 --continue-at - \
        https://github.com/onthegomap/planetiler/releases/download/v0.10.2/planetiler.jar \
        --output "$JAR.part"
    mv "$JAR.part" "$JAR"
fi

# Utiliser Python évite de dépendre des différences entre sha256sum (Linux) et
# shasum (macOS). Le heredoc quoté 'PY' est transmis sans expansion par Bash ;
# le chemin du fichier arrive séparément dans sys.argv[1].
# Lire par blocs garde une consommation mémoire constante pour le contrôle.
# Une empreinte incorrecte arrête le script avant l'exécution du code Java.
# Le JAR en erreur est conservé pour diagnostic ; le déplacer avant de relancer.
python3 - "$JAR" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
if h.hexdigest() != 'f310bd0413e2e4512b27f4046d418664e8e1d3bf31603c2a70e23de06c167e4d':
    sys.exit('Empreinte Planetiler incorrecte : déplacer le JAR et relancer.')
PY

# Planetiler crée notamment data/sources et ses fichiers temporaires relativement
# au dossier courant. Ne pas supprimer ces sources automatiquement : elles peuvent
# être réutilisées après un échec ou pour une autre génération compatible.
cd "$WORK"

# --download récupère l'extrait Geofabrik et les sources auxiliaires OpenMapTiles
# (fonds Natural Earth, polygones d'eau et lignes de lacs), pas seulement l'OSM.
# --storage=mmap choisit le stockage temporaire mappé ; cela n'élimine pas le
# besoin de RAM ni celui de beaucoup d'espace disque.
# L'extension finale de l'intermédiaire reste .pmtiles : le moteur choisit son
# format de sortie à partir de cette extension, et non du mot "building".
# Le calcul des tuiles ne reprend pas à mi-parcours. En cas d'échec, déplacer un
# éventuel *.building.pmtiles avant de relancer ; aucun --force n'est utilisé.
java "-Xmx$HEAP" -jar "$JAR" --download "--area=$AREA" \
    "--output=$WORK/$NAME.building.pmtiles" "--maxzoom=$MAXZOOM" \
    --storage=mmap

# Valider le conteneur et les couches attendues avant de publier le nom final.
# Le renommage reste sur le même volume ; une carte incomplète ne devient donc
# pas le fichier à transférer par une simple sortie réussie du moteur Java.
python3 "$ROOT/scripts/check-map.py" "$WORK/$NAME.building.pmtiles"
mv "$WORK/$NAME.building.pmtiles" "$TARGET"
# Le transfert vers le Pi est volontairement distinct : cet ordinateur n'a pas
# besoin de connaître des identifiants SSH ni la disposition du stockage du Pi.
echo "Carte prête : $TARGET"
echo 'Pour Europe, copier ce fichier vers /srv/bibliotech/maps/europe.pmtiles sur le Pi.'
