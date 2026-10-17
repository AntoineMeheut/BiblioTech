#!/usr/bin/env bash
# =============================================================================
# VÉRIFICATIONS LOCALES ET GITHUB ACTIONS — AUCUN BESOIN DE RASPBERRY PI
# =============================================================================
# Cette commande contrôle les sources sans installer les services ni modifier le
# réseau. Elle ne télécharge ni ZIM ni carte et ne doit jamais appeler install.sh
# sans --help. Un échec de contrôle arrête la suite avec un statut non nul.
# Dépendances : Bash et Python 3 ; ShellCheck et Node.js sont facultatifs en local
# mais exigés par .github/workflows/ci.yml pour une validation CI complète.
# =============================================================================
set -Eeuo pipefail

# Se placer à la racine du projet permet les mêmes chemins depuis le terminal,
# une archive extraite ou une copie de travail GitHub Actions.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# -n analyse la syntaxe Bash sans exécuter les commandes, même celles réservées
# à Linux ou à root. Inclure les tests shell dans leur propre contrôle syntaxique.
bash -n install.sh scripts/*.sh tests/*.sh

# ShellCheck ajoute une analyse statique : guillemets, variables, substitutions,
# redirections, etc. Son absence en local ne bloque pas les autres vérifications.
if command -v shellcheck >/dev/null; then
    shellcheck install.sh scripts/*.sh tests/*.sh
fi

# Les tests Python utilisent de petits fichiers temporaires et des simulations
# des commandes de transfert/indexation ; ils ne sollicitent pas les gros jeux
# de données. La compilation détecte également les erreurs des autres helpers.
python3 -m unittest discover -s tests -v
python3 -m py_compile scripts/*.py

# Le contrôle JS sans argument optionnel valide la configuration de la carte en
# mémoire. Il ne lance ni navigateur ni serveur HTTP et ne requiert pas vendor/.
# Les essais supplémentaires avec style-spec et un PMTiles réel sont documentés
# séparément et ne doivent pas devenir des téléchargements implicites de la CI.
if command -v node >/dev/null; then
    node --check web/map/map.js
    node tests/test_map.cjs
fi

# Essai de l'entrée CLI publique : --help doit rester disponible sans sudo,
# sans NetworkManager et sur un poste de développement non Linux.
./install.sh --help
