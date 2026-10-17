#!/usr/bin/env bash
# =============================================================================
# BIBLIOTECH — INSTALLATION SUR LE RASPBERRY PI
# =============================================================================
# Rôle : installer la bibliothèque et son portail, puis préparer le profil Wi-Fi.
# Cible : Raspberry Pi OS Lite 32 bits Bookworm/Trixie, notamment le Zero W ARMv6.
# Exécution : sudo ./install.sh [--config /chemin/config.env] [--no-download]
#
# Avant de commencer :
#   - le Pi utilise encore sa connexion Internet habituelle ;
#   - le stockage est monté et la carte maps/europe.pmtiles est déjà copiée ;
#   - config.env définit au minimum le mot de passe et le pays du Wi-Fi.
#
# Ordre à préserver lors de la maintenance :
#   1. Contrôler les prérequis avant de modifier le système.
#   2. Installer les outils et valider leur exécution sur le processeur local.
#   3. Copier les ressources, télécharger/vérifier les ZIM et construire l'index.
#   4. Configurer, démarrer et contrôler les services HTTP.
#   5. Préparer le point d'accès ; son activation est une commande distincte.
# L'activation anticipée du Wi-Fi couperait la liaison utilisée pour télécharger.
#
# Emplacements persistants :
#   /opt/bibliotech/         scripts et portail installés ;
#   /etc/bibliotech/         configuration privée et configuration nginx ;
#   /var/lib/bibliotech/     état du précédent profil Wi-Fi ;
#   DATA_DIR/              carte, ZIM, index XML et état des contenus ;
#   /etc/systemd/system/   unités bibliotech et bibliotech-web.
#
# Une relance réutilise les contenus vérifiés, mais réécrit la configuration
# gérée ici et redémarre les services. Elle ne constitue pas une transaction :
# après un échec, certaines installations ou copies peuvent déjà être faites.
# Le détail des téléchargements et de l'index atomique est dans content.py.
# =============================================================================

# Mode strict : -e arrête les erreurs non prises en charge ; -E propage le trap
# ERR aux fonctions ; -u détecte les variables absentes ; pipefail propage les
# erreurs des pipelines. Les échecs attendus restent traités par if, || ou !.
# Ne pas ajouter set -x : des commandes manipulent le mot de passe du Wi-Fi.
set -Eeuo pipefail

# Les nouveaux fichiers ordinaires restent lisibles par les services HTTP.
# La configuration qui contient le mot de passe reçoit ensuite un chmod 0600.
umask 022

# Résoudre le dossier du script, indépendamment du répertoire courant de sudo.
# Les guillemets et -- protègent les chemins comportant des espaces ou tirets.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# La directive suivante renseigne ShellCheck ; elle ne s'exécute pas en Bash.
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

# Valeurs des options CLI. Les paramètres métier viennent de load_config plus bas.
# --no-download ne concerne que les ZIM, pas APT ni les ressources web manquantes.
CONFIG="$ROOT/config.env"
NO_DOWNLOAD=0

# Lire les options avant les contrôles système permet d'utiliser --help sur un
# ordinateur de développement sans root et sans matériel Raspberry Pi.
# Chaque branche consomme ses arguments ; une option inconnue provoque un arrêt.
while (($#)); do
    case "$1" in
        --config) [[ $# -ge 2 ]] || die '--config exige un fichier.'; CONFIG=$2; shift 2 ;;
        --no-download) NO_DOWNLOAD=1; shift ;;
        -h|--help)
            echo 'sudo ./install.sh [--config config.env] [--no-download]'
            echo 'La carte doit exister dans DATA_DIR/maps/europe.pmtiles.'
            echo 'Le Wi-Fi est préparé, puis activé par sudo bibliotech-hotspot on.'
            exit 0 ;;
        *) die "Option inconnue : $1" ;;
    esac
done

# -----------------------------------------------------------------------------
# 1. Contrôles de plateforme, de réseau et de données
# -----------------------------------------------------------------------------
# Vérifier root avant les écritures dans /etc, /opt et /run. Ne pas relancer sudo
# automatiquement : le contexte d'exécution doit être choisi par l'administrateur.
[[ $EUID -eq 0 ]] || die 'Exécuter avec sudo sur le Raspberry Pi.'
[[ $(uname -s) == Linux ]] || die "Ce script s’exécute sur Raspberry Pi OS, pas sur cet ordinateur."

# LONG_BIT contrôle l'espace utilisateur ; dpkg contrôle l'architecture des paquets.
# armhf seul n'identifie pas ARMv6 : la distribution et les binaires sont également
# contrôlés ci-dessous. Ne pas substituer des binaires génériques ARMv7/ARM64.
[[ $(getconf LONG_BIT) == 32 && $(dpkg --print-architecture) == armhf ]] || die 'Raspberry Pi OS 32 bits armhf requis.'
[[ -r /proc/device-tree/model ]] || die 'Matériel Raspberry Pi introuvable.'

# Le device tree termine ses chaînes par un octet NUL, retiré avant comparaison.
# Le filtre accepte la famille Raspberry Pi ; la cible prioritaire reste le Zero W.
MODEL=$(tr -d '\0' </proc/device-tree/model)
[[ "$MODEL" == *'Raspberry Pi'* ]] || die "Matériel non pris en charge : $MODEL"

# os-release est fourni par le système, contrairement à config.env fourni par
# l'administrateur. SC1091 est désactivé car ce fichier manque sur le poste macOS.
# shellcheck disable=SC1091
source /etc/os-release
[[ "${VERSION_CODENAME:-}" == bookworm || "${VERSION_CODENAME:-}" == trixie ]] || die 'Utiliser Raspberry Pi OS Lite 32 bits Bookworm ou Trixie.'
# Ce marqueur est un contrôle pratique de l'image choisie, pas une attestation
# cryptographique de la provenance de tous les paquets APT configurés.
[[ -f /etc/rpi-issue ]] || die 'Image officielle Raspberry Pi OS requise (ARMv6, pas Debian armhf générique).'

# Cette fonction source le fichier Bash de confiance, applique les valeurs par
# défaut et valide les paramètres utilisés dans les commandes et fichiers générés.
load_config "$CONFIG"

# Garder le descripteur 9 ouvert conserve le verrou pendant toute l'installation.
# -n refuse immédiatement une seconde instance au lieu d'attendre son exécution.
# La sortie du processus libère le verrou ; le fichier peut rester présent.
exec 9>/run/lock/bibliotech-install.lock
flock -n 9 || die 'Une installation est déjà en cours.'

# Fournir la ligne en échec sans afficher les arguments sensibles. Le trap
# signale l'erreur, mais n'annule pas les changements système déjà appliqués.
trap 'printf "Échec ligne %s. Les profils Wi-Fi clients sont conservés.\n" "$LINENO" >&2' ERR

# Ce projet utilise NetworkManager, déjà livré/configuré par l'image cible.
# Il ne convertit pas une ancienne installation dhcpcd/hostapd et ne doit pas
# lancer deux gestionnaires concurrents sur la même interface Wi-Fi.
command -v nmcli >/dev/null || die 'NetworkManager requis ; utiliser une image Raspberry Pi OS récente.'
systemctl is-active --quiet NetworkManager || die 'NetworkManager doit être actif.'
[[ -d /sys/class/net/$WIFI_INTERFACE ]] || die "Interface absente : $WIFI_INTERFACE"

# AP est une capacité annoncée par le pilote, pas un essai de diffusion réel.
# LC_ALL=C stabilise la réponse yes/no quelle que soit la langue du système.
AP_CAPABILITY=$(LC_ALL=C nmcli -g WIFI-PROPERTIES.AP device show "$WIFI_INTERFACE")
[[ "$AP_CAPABILITY" == yes ]] || die "Le pilote de $WIFI_INTERFACE ne propose pas le mode point d’accès."

# Exiger une carte existante évite de configurer un portail incomplet. Le helper
# vérifie l'en-tête PMTiles et le schéma OpenMapTiles, sans charger toute la carte
# en RAM et sans prétendre vérifier chaque tuile du fichier.
[[ -s "$DATA_DIR/maps/europe.pmtiles" ]] || die "Préparer la carte sur un PC avec scripts/prepare-map.sh, puis copier le résultat dans $DATA_DIR/maps/europe.pmtiles."
python3 "$ROOT/scripts/check-map.py" "$DATA_DIR/maps/europe.pmtiles"

# Plusieurs ZIM dépassent 4 Go ; un stockage FAT32 ne peut pas les contenir.
# Aucun formatage ni montage n'est réalisé ici : cela relève de l'administrateur.
FSTYPE=$(stat -f -c %T "$DATA_DIR")
[[ "$FSTYPE" != msdos && "$FSTYPE" != vfat ]] || die 'FAT32 est incompatible avec les archives de plus de 4 Go ; utiliser ext4.'

# Sur une première installation, refuser de prendre les ports d'un autre serveur.
# À la relance, les propres services du projet peuvent déjà occuper ces ports.
# Le fichier config.env installé sert de marqueur de cette relance ; s'il reste
# après une installation interrompue, contrôler les services lors du diagnostic.
# ss -H retire l'en-tête ; read détecte si au moins un socket TCP est en écoute.
if [[ ! -f /etc/bibliotech/config.env ]]; then
    if ss -H -ltn '( sport = :80 or sport = :8080 )' | read -r _; then
        die 'Le port 80 ou 8080 est occupé. Utiliser une installation dédiée ou libérer ces ports.'
    fi
fi

# -----------------------------------------------------------------------------
# 2. Paquets, compte de service et copie de la configuration
# -----------------------------------------------------------------------------
log "Installation des paquets Raspberry Pi OS pour $MODEL"
# Rafraîchir l'index APT sans effectuer une mise à niveau générale du système.
apt-get update

# Paquets principaux :
#   kiwix-tools          lecteur HTTP et gestionnaire de bibliothèque ;
#   nginx-light          portail statique, reverse proxy et requêtes Range ;
#   dnsmasq-base         binaire DHCP/DNS lancé par NetworkManager en mode shared ;
#   curl/ca-certificates transferts HTTPS avec validation des certificats ;
#   python3              assistants de téléchargement, contrôle et indexation ;
#   iw/rfkill            outils radio ; raspi-config persiste le pays Wi-Fi.
# dnsmasq-base ne doit pas être remplacé par un serveur DHCP autonome concurrent.
# --no-install-recommends limite les paquets annexes sur le petit stockage du Pi.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    kiwix-tools nginx-light dnsmasq-base curl ca-certificates python3 iw rfkill raspi-config
# Exécuter les outils détecte notamment les binaires inutilisables sur ce CPU.
# Ce contrôle ne garantit pas à lui seul la lecture de toutes les archives.
kiwix-serve --version
kiwix-manage --help >/dev/null

# Vérifier les options dont dépend l'unité systemd avant de la générer. Une
# évolution des arguments Kiwix doit être répercutée ici et dans ExecStart.
HELP=$(kiwix-serve --help)
for option in --urlRootLocation --threads --searchLimit; do
    [[ "$HELP" == *"$option"* ]] || die "Version de kiwix-serve incompatible : $option absent."
done

# Réutiliser le compte de service s'il existe. Il n'a ni shell de connexion ni
# dossier personnel créé par useradd ; les données restent gérées par root.
id bibliotech >/dev/null 2>&1 || useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin bibliotech

# install fixe explicitement les permissions et crée les dossiers manquants.
# Les scripts installés permettent la maintenance après déplacement du dépôt
# source ; modifier le dépôt seul ne met pas à jour ces copies automatiquement.
install -d -m 0755 "$DATA_DIR/zim" /opt/bibliotech /etc/bibliotech /var/lib/bibliotech
install -d -m 0755 /opt/bibliotech/scripts /opt/bibliotech/config /opt/bibliotech/web
install -m 0755 "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.py /opt/bibliotech/scripts/
install -m 0644 "$ROOT/config/contents.json" /opt/bibliotech/config/contents.json
# Persister uniquement les six paramètres utilisés par le projet. Le fichier
# source peut contenir du Bash ; ne pas en recopier les éventuelles commandes.
# %q produit un échappement relisible par Bash, notamment pour espaces et quotes.
# Le mot de passe se trouve dans ce fichier : conserver impérativement le mode 0600.
{
    printf 'DATA_DIR=%q\n' "$DATA_DIR"
    printf 'WIFI_INTERFACE=%q\nWIFI_SSID=%q\nWIFI_PASSWORD=%q\nWIFI_COUNTRY=%q\nWIFI_CHANNEL=%q\n' \
        "$WIFI_INTERFACE" "$WIFI_SSID" "$WIFI_PASSWORD" "$WIFI_COUNTRY" "$WIFI_CHANNEL"
} > /etc/bibliotech/config.env
chmod 0600 /etc/bibliotech/config.env

# -----------------------------------------------------------------------------
# 3. Portail local, archives et droits de lecture des services
# -----------------------------------------------------------------------------
log 'Installation des ressources web locales'
# Le suffixe /. copie aussi les éventuels fichiers cachés du dossier web.
# fetch-assets.py réutilise les ressources valides ou les récupère avec contrôle
# d'empreinte ; aucun CDN n'est requis au moment de consulter la carte.
cp -R "$ROOT/web/." /opt/bibliotech/web/
python3 /opt/bibliotech/scripts/fetch-assets.py --destination /opt/bibliotech/web/vendor

# index exige les fichiers déjà présents ; sync peut télécharger les manquants.
# Les deux chemins vérifient l'intégrité avant de remplacer library.xml.
# Le helper Python gère le verrou des contenus, l'espace disponible, les fichiers
# .part et le remplacement atomique de l'index : ne pas dupliquer ces règles ici.
if ((NO_DOWNLOAD)); then
    python3 /opt/bibliotech/scripts/content.py index --data-dir "$DATA_DIR"
else
    python3 /opt/bibliotech/scripts/content.py sync --data-dir "$DATA_DIR"
fi

# Autoriser la traversée des dossiers et la lecture, sans rendre les données
# modifiables par les comptes de service. content.py applique 0644 aux ZIM.
# Ne pas utiliser chmod -R ou chown -R : le volume peut contenir d'autres fichiers.
chmod 0755 "$DATA_DIR" "$DATA_DIR/zim" "$DATA_DIR/maps"
chmod 0644 "$DATA_DIR/maps/europe.pmtiles"

# Tester en tant que lecteur réel détecte aussi les parents non traversables
# d'un disque externe, qu'un simple test lancé par root ne révélerait pas.
runuser -u bibliotech -- test -r "$DATA_DIR/library.xml" || die 'Le compte bibliotech ne peut pas traverser DATA_DIR (vérifier les répertoires parents).'
runuser -u www-data -- test -r "$DATA_DIR/maps/europe.pmtiles" || die 'nginx ne peut pas lire la carte (vérifier les répertoires parents).'

# -----------------------------------------------------------------------------
# 4. Services HTTP et contrôles avant de préparer le point d'accès
# -----------------------------------------------------------------------------
log 'Configuration des services'
# Ce heredoc n'est pas quoté : DATA_DIR est remplacé lors de l'installation.
# Ne pas y ajouter une variable avec un signe dollar non échappé si elle doit
# être conservée pour systemd/nginx, ou même simplement affichée en commentaire.
#
# Unité Kiwix :
#   RequiresMountsFor attend les montages nécessaires au chemin des données ;
#   127.0.0.1:8080 réserve le backend au proxy nginx local ;
#   /bibliotheque doit rester cohérent avec les locations nginx et les liens du portail ;
#   threads=2 limite la concurrence sur le Zero W ; searchLimit=1 limite le nombre
#     d'archives d'une recherche globale, pas le nombre d'utilisateurs ;
#   Restart=on-failure relance les échecs, pas un arrêt demandé via systemctl ;
#   ProtectSystem/ProtectHome/NoNewPrivileges réduisent les droits du lecteur ;
#   PrivateTmp isole les fichiers temporaires et LimitNOFILE autorise assez de
#     fichiers/sockets sans imposer une consommation mémoire permanente.
# Modifier DATA_DIR sous /home entrerait en conflit avec ProtectHome=true.
cat > /etc/systemd/system/bibliotech.service <<EOF
[Unit]
Description=BiblioTech - Bibliotheque hors ligne
After=network.target
RequiresMountsFor=$DATA_DIR

[Service]
User=bibliotech
Group=bibliotech
ExecStart=/usr/bin/kiwix-serve --address=127.0.0.1 --port=8080 --urlRootLocation=/bibliotheque --threads=2 --searchLimit=1 --library $DATA_DIR/library.xml
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
# Instance nginx dédiée : les sites préexistants ne sont pas réécrits. Le service
# nginx standard sera toutefois arrêté plus bas : ce projet vise un Pi dédié.
#
# Choix nginx à conserver ou ajuster ensemble :
#   un worker et 128 connexions bornent la concurrence sans garantir une charge ;
#   access_log off limite les écritures SD, tandis que error_log garde les erreurs ;
#   sendfile sert les fichiers sans les charger entièrement en espace utilisateur ;
#   proxy_pass sans suffixe URI conserve /bibliotheque/ pour le backend configuré ainsi ;
#   proxy_buffering off évite la mise en tampon habituelle des réponses Kiwix ;
#   proxy_read_timeout laisse du temps au Pi pour les recherches lentes ;
#   alias pointe vers la carte hors de la racine web, sans exposer tout DATA_DIR ;
#   gzip off préserve le transfert des plages d'octets attendu par PMTiles ;
#   try_files refuse les chemins inexistants au lieu de masquer un fichier absent.
# Les variables http_host et uri sont échappées pour nginx, pas pour Bash.
cat > /etc/bibliotech/nginx.conf <<EOF
user www-data;
worker_processes 1;
pid /run/bibliotech-nginx.pid;
error_log /var/log/nginx/bibliotech-error.log;
events { worker_connections 128; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    sendfile on;
    keepalive_timeout 15;
    server {
        listen 80;
        server_name _;
        root /opt/bibliotech/web;
        index index.html;
        location = /bibliotheque { return 302 /bibliotheque/; }
        location /bibliotheque/ {
            proxy_pass http://127.0.0.1:8080;
            proxy_set_header Host \$http_host;
            proxy_buffering off;
            proxy_read_timeout 120s;
        }
        location = /maps/europe.pmtiles {
            alias $DATA_DIR/maps/europe.pmtiles;
            # PMTiles utilise des requêtes Range, prises en charge par nginx.
            gzip off;
        }
        location / { try_files \$uri \$uri/ =404; }
    }
}
EOF

# Le master nginx démarre sous systemd et ses workers utilisent www-data, défini
# dans nginx.conf. Type=simple exige daemon off : systemd suit le vrai processus.
# ExecStartPre refuse une configuration invalide ; HUP permet un rechargement.
# MAINPID est échappé pour que systemd le remplace au rechargement du service.
# After ordonne le démarrage sans rendre les deux services indissociables : le
# portail et la carte peuvent rester accessibles pendant une panne de Kiwix.
cat > /etc/systemd/system/bibliotech-web.service <<EOF
[Unit]
Description=BiblioTech - Accueil et carte hors ligne
After=network.target bibliotech.service
RequiresMountsFor=$DATA_DIR

[Service]
Type=simple
ExecStartPre=/usr/sbin/nginx -t -c /etc/bibliotech/nginx.conf
ExecStart=/usr/sbin/nginx -c /etc/bibliotech/nginx.conf -g 'daemon off;'
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
# APT peut démarrer nginx automatiquement sur une image vierge. Arrêter cette
# instance avant la nôtre libère le port 80 et évite deux masters concurrents.
# Le refus des ports occupés avant APT protège le cas d'une première installation.
systemctl disable --now nginx.service
# Valider d'abord la syntaxe, puis demander à systemd de relire les unités.
nginx -t -c /etc/bibliotech/nginx.conf
systemctl daemon-reload
# enable persiste le démarrage au boot ; restart applique les unités immédiatement.
systemctl enable bibliotech.service bibliotech-web.service
systemctl restart bibliotech.service bibliotech-web.service

# Sonder l'URL publique via nginx, pas seulement le processus Kiwix. Les 30 essais
# ajoutent au plus 60 secondes de pause, auxquels s'ajoute le temps des requêtes.
# Le dernier curl donne un échec explicite si aucun essai n'a abouti.
for _ in {1..30}; do
    if curl -fsS http://127.0.0.1/bibliotheque/ >/dev/null; then break; fi
    sleep 2
done
curl -fsS http://127.0.0.1/bibliotheque/ >/dev/null || die 'Kiwix ne répond pas. Voir journalctl -u bibliotech.'

# Demander uniquement les huit premiers octets de la carte : signature PMTiles
# et version 3. Le contrôle porte sur le corps reçu, pas explicitement sur le
# statut 206 ; le diagnostic manuel du guide permet de vérifier aussi ce statut.
curl -fsS -r 0-7 http://127.0.0.1/maps/europe.pmtiles | python3 -c 'import sys; assert sys.stdin.buffer.read() == b"PMTiles\x03"'

# -----------------------------------------------------------------------------
# 5. Profil NetworkManager, préparé sans bascule de la connexion actuelle
# -----------------------------------------------------------------------------
log "Préparation du point d’accès 2,4 GHz"
PROFILE=bibliotech

# Identifiant stable pour retrouver le profil même si son nom est modifié.
# Toute modification de cet UUID doit aussi être appliquée dans hotspot.sh.
# Il doit rester distinct des UUID des profils clients de l'administrateur.
PROFILE_UUID=675ec62b-7f50-457e-a6d2-9e57f0d4a457

# Créer le profil une seule fois, sans autoconnection initiale. Une réinstallation
# conserve l'état d'autoconnection d'un profil déjà activé avec bibliotech-hotspot on.
if ! nmcli -g connection.uuid connection show uuid "$PROFILE_UUID" >/dev/null 2>&1; then
    nmcli connection add type wifi ifname "$WIFI_INTERFACE" con-name "$PROFILE" \
        connection.uuid "$PROFILE_UUID" connection.autoconnect no ssid "$WIFI_SSID"
fi

# Paramètres du point d'accès :
#   connection.id : appliquer aussi le nom BiblioTech à un profil existant ;
#   priorité 100 : privilégier ce profil parmi les candidats à l'autoconnection ;
#   mode ap / band bg : point d'accès sur la bande 2,4 GHz du Zero W ;
#   powersave 2 : désactiver l'économie d'énergie Wi-Fi dans ce profil ;
#   wpa-psk + rsn + ccmp : WPA2 personnel, chiffrement AES-CCMP ;
#   shared : NetworkManager gère DHCP, DNS et le partage d'une connexion amont ;
#   10.42.0.1/24 : adresse du portail et sous-réseau des lecteurs ;
#   never-default : ne pas choisir ce profil comme route par défaut du Pi ;
#   IPv6 disabled : ce réseau local est configuré en IPv4 uniquement.
# Un changement de sous-réseau doit aussi mettre à jour hotspot.sh, les liens
# et textes du portail ainsi que la documentation. Éviter un conflit avec l'amont.
# Ne pas journaliser cette commande avec xtrace : elle contient le secret WPA2.
nmcli connection modify uuid "$PROFILE_UUID" \
    connection.id "$PROFILE" connection.interface-name "$WIFI_INTERFACE" connection.autoconnect-priority 100 \
    802-11-wireless.ssid "$WIFI_SSID" 802-11-wireless.mode ap \
    802-11-wireless.band bg 802-11-wireless.channel "$WIFI_CHANNEL" \
    802-11-wireless.powersave 2 \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.proto rsn 802-11-wireless-security.pairwise ccmp \
    802-11-wireless-security.group ccmp 802-11-wireless-security.psk "$WIFI_PASSWORD" \
    ipv4.method shared ipv4.addresses 10.42.0.1/24 ipv4.never-default yes ipv6.method disabled

# Point d'entrée stable pour l'administrateur. hotspot.sh résout ce lien pour
# retrouver common.sh dans /opt/bibliotech/scripts plutôt que dans /usr/local/sbin.
ln -sfn /opt/bibliotech/scripts/hotspot.sh /usr/local/sbin/bibliotech-hotspot
# Aucune commande connection up ici : tous les téléchargements et contrôles
# doivent être terminés avant l'activation explicite du point d'accès.
log 'Installation terminée. Activer avec : sudo bibliotech-hotspot on'
printf 'Wi-Fi : %s\nAccueil : http://10.42.0.1/\nActiver le point coupe la connexion Wi-Fi client/SSH après 10 secondes.\n' "$WIFI_SSID"
