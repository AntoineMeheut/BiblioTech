#!/usr/bin/env bash
# =============================================================================
# FONCTIONS PARTAGÉES — À SOURCER DEPUIS LES SCRIPTS BASH
# =============================================================================
# Utilisé par install.sh et hotspot.sh. Le chargement définit des fonctions et
# active le mode strict, mais ne touche ni au réseau ni aux fichiers du système.
# Garder cette séparation : charger une bibliothèque ne doit pas installer quoi
# que ce soit ni activer une connexion par effet de bord.
#
# Interface publique :
#   die MESSAGE       écrit sur stderr et termine le script appelant avec code 1 ;
#   log MESSAGE       écrit un titre d'étape sur stdout ;
#   load_config FILE  charge et valide les six paramètres globaux du projet.
# Ne pas lancer ce fichier seul pour configurer le système.
# =============================================================================

# Le mode strict s'applique également au shell appelant puisque le fichier est
# sourcé. Les valeurs optionnelles doivent donc être initialisées explicitement.
set -Eeuo pipefail

# printf utilise un format fixe : un signe % présent dans un message reste une
# donnée. Ne jamais passer le mot de passe à die ou log, même lors du débogage.
die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
log() { printf '\n>>> %s\n' "$*"; }

# Entrée : chemin d'un fichier Bash de confiance, choisi par l'administrateur.
# Sorties : DATA_DIR, WIFI_INTERFACE, WIFI_SSID, WIFI_PASSWORD, WIFI_COUNTRY,
#           WIFI_CHANNEL et la locale LC_ALL=C dans le shell appelant.
# Échec : termine immédiatement le script ; les appelants n'ont pas à interpréter
# un fichier invalide. La fonction ne modifie aucun profil NetworkManager.
load_config() {
    # Seul le chemin est local à la fonction ; les paramètres chargés restent
    # globaux pour les commandes appelantes et la configuration générée.
    local config=$1
    [[ -f "$config" ]] || die "Copier config.example.env vers $config et définir WIFI_PASSWORD."

    # source exécute du Bash : ce n'est pas un parseur de données .env inertes.
    # Le fichier doit donc être administré localement, jamais obtenu d'un lecteur
    # du portail ou d'une requête web. Les validations suivantes ne neutralisent
    # pas une commande déjà exécutée lors de source.
    # SC1090 signale un chemin dynamique normal ici ; l'annotation est ciblée.
    # shellcheck disable=SC1090
    source "$config"

    # La commande : n'a pas d'action ; les expansions := initialisent les valeurs
    # absentes ou vides. Le mot de passe reste volontairement vide par défaut :
    # sa validation impose que l'administrateur en choisisse un.
    : "${DATA_DIR:=/srv/bibliotech}" "${WIFI_INTERFACE:=wlan0}" "${WIFI_SSID:=BiblioTech}"
    : "${WIFI_PASSWORD:=}" "${WIFI_COUNTRY:=FR}" "${WIFI_CHANNEL:=6}"

    # Stabiliser les comparaisons et les plages ASCII. Avec la locale C, la
    # longueur du SSID correspond à des octets, comme la limite Wi-Fi de 32 octets.
    # Ce choix est également utile aux réponses yes/no de nmcli dans l'appelant.
    export LC_ALL=C

    # DATA_DIR est injecté dans des configurations systemd/nginx sans mécanisme
    # d'échappement propre à ces formats. Limiter sa syntaxe évite espaces,
    # retours à la ligne, caractères spéciaux et remontées de chemin avec .. .
    [[ "$DATA_DIR" =~ ^/[a-zA-Z0-9_/-]+$ && "$DATA_DIR" != / && "$DATA_DIR" != *'..'* ]] || die 'DATA_DIR : chemin absolu simple requis (sans espace ni ..).'

    # Les unités isolent /home et leurs répertoires temporaires. Les emplacements
    # retenus conviennent aux données système et aux volumes montés durablement.
    # Ce test ne monte pas le disque et ne résout pas les liens symboliques : les
    # droits et montages effectifs restent contrôlés lors de l'installation.
    [[ "$DATA_DIR" == /srv/* || "$DATA_DIR" == /mnt/* || "$DATA_DIR" == /media/* ]] || die 'Placer DATA_DIR sous /srv, /mnt ou /media (accès des services systemd).'

    # Autoriser des noms usuels comme wlan0 ou wlx..., sans imposer une interface
    # existante ici : install.sh vérifie ensuite sa présence et sa capacité AP.
    [[ "$WIFI_INTERFACE" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Interface Wi-Fi invalide.'

    # Contrôle de forme du code pays, pas vérification d'une table ISO complète.
    # raspi-config et la pile radio appliqueront les restrictions du pays choisi.
    [[ "$WIFI_COUNTRY" =~ ^[A-Z]{2}$ ]] || die 'WIFI_COUNTRY doit être un code ISO de deux lettres.'

    # Restreindre aux canaux 1 à 11 pour une configuration 2,4 GHz simple. Le pays
    # doit toujours correspondre au lieu réel d'utilisation du matériel.
    [[ "$WIFI_CHANNEL" =~ ^([1-9]|1[01])$ ]] || die 'Choisir un canal Wi-Fi de 1 à 11.'

    # Un SSID n'est pas le mot de passe : il peut contenir des caractères UTF-8,
    # tant que sa représentation ne dépasse pas 32 octets. CR/LF sont refusés pour
    # conserver des fichiers de configuration et messages lisibles sur une ligne.
    [[ ${#WIFI_SSID} -ge 1 && ${#WIFI_SSID} -le 32 && "$WIFI_SSID" != *$'\n'* && "$WIFI_SSID" != *$'\r'* ]] || die 'SSID invalide (1 à 32 octets).'

    # Phrase secrète WPA2 : 8 à 63 caractères imprimables ASCII, espaces inclus.
    # Le motif négatif détecte tout octet hors de cette plage. La forme alternative
    # d'une clé hexadécimale de 64 caractères n'est pas acceptée par ce projet.
    [[ ${#WIFI_PASSWORD} -ge 8 && ${#WIFI_PASSWORD} -le 63 && "$WIFI_PASSWORD" != *[!\ -~]* ]] || die 'WIFI_PASSWORD : 8 à 63 caractères ASCII imprimables requis.'
}
