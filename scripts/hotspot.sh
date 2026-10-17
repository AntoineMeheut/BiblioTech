#!/usr/bin/env bash
# =============================================================================
# COMMANDE D'ADMINISTRATION DU POINT D'ACCÈS — SUR LE PI INSTALLÉ
# =============================================================================
# Commandes publiques : bibliotech-hotspot status | on | off.
# Branches internes : apply-on / apply-off, exécutées par systemd après le délai.
#
# Le script sépare la demande de bascule et son exécution : quitter le Wi-Fi
# client peut couper SSH, mais ne doit pas interrompre la commande nmcli en cours.
# Le service transitoire systemd reste indépendant de la session de connexion.
# Aucun profil client n'est supprimé ; son UUID est mémorisé avant la bascule.
# =============================================================================

# Ne pas utiliser xtrace : load_config lit une configuration contenant le secret
# Wi-Fi. Les messages doivent rester limités aux actions et à l'état du réseau.
set -Eeuo pipefail

# Le point d'entrée installé est un lien /usr/local/sbin/bibliotech-hotspot. readlink -f
# le résout pour retrouver common.sh au bon endroit. Cette commande vise Linux ;
# les tests sur macOS vérifient sa syntaxe sans exécuter la bascule réseau.
SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

# IMPORTANT : conserver cet UUID identique à celui défini dans install.sh.
# Utiliser l'UUID évite de dépendre d'un nom de connexion modifiable ou dupliqué.
PROFILE_UUID=675ec62b-7f50-457e-a6d2-9e57f0d4a457

# L'absence d'argument affiche l'état, sans modifier les connexions. Cette branche
# ne lit pas la configuration root contenant le mot de passe. systemctl peut
# retourner un code non nul si un service est inactif : c'est une information utile.
ACTION=${1:-status}
if [[ "$ACTION" == status ]]; then
    nmcli connection show --active
    systemctl --no-pager status bibliotech bibliotech-web
    exit
fi

# Les autres actions modifient NetworkManager ou programment une tâche système.
# Lire la copie installée de la configuration, pas un fichier du dossier courant.
[[ $EUID -eq 0 ]] || die 'Exécuter avec sudo.'
load_config /etc/bibliotech/config.env
case "$ACTION" in
    on|off)
        # Donner à l'administrateur le temps de lire l'adresse de reconnexion.
        # --on-active crée un timer ; --collect autorise la collecte des unités
        # transitoires après leur exécution, y compris en cas d'échec.
        # Le nom stable empêche de créer sans cesse la même unité déjà présente.
        # Le verrou des branches apply-* protège ensuite la modification effective.
        echo "Bascule Wi-Fi dans 10 secondes. La session SSH peut être interrompue."
        echo "Après activation : Wi-Fi $WIFI_SSID ; http://10.42.0.1/"
        systemd-run --unit="bibliotech-hotspot-$ACTION" --on-active=10s --collect \
            /opt/bibliotech/scripts/hotspot.sh "apply-$ACTION"
        ;;
    apply-on)
        # Même verrou que apply-off : deux bascules opposées ne doivent pas
        # modifier simultanément l'état du profil et l'UUID sauvegardé.
        exec 9>/run/lock/bibliotech-wifi.lock
        flock -n 9 || die 'Une bascule Wi-Fi est en cours.'

        # Mémoriser uniquement un vrai UUID de connexion différent du hotspot.
        # Quand le hotspot est déjà actif, conserver l'ancien profil mémorisé,
        # sinon un second appel à on ferait perdre la connexion à restaurer.
        # NetworkManager peut renvoyer un marqueur vide/indéfini si rien n'est actif.
        previous=$(nmcli -g GENERAL.CON-UUID device show "$WIFI_INTERFACE")
        if [[ "$previous" != "$PROFILE_UUID" && "$previous" =~ ^[0-9a-f-]{36}$ ]]; then
            printf '%s\n' "$previous" > /var/lib/bibliotech/previous-wifi
        fi

        # Persister le pays avant d'émettre. Réactiver aussi les blocages logiciels
        # RF-kill et la radio NetworkManager ; un blocage matériel nécessite une
        # intervention et ne peut pas être levé par ces commandes.
        raspi-config nonint do_wifi_country "$WIFI_COUNTRY"
        rfkill unblock wifi
        nmcli radio wifi on

        # L'autoconnection rend le profil disponible aux prochains démarrages.
        # connection up applique maintenant les paramètres préparés par install.sh.
        # --wait 45 borne l'attente de l'activation, pas toute la durée du script.
        nmcli connection modify uuid "$PROFILE_UUID" connection.autoconnect yes
        if ! nmcli --wait 45 connection up uuid "$PROFILE_UUID"; then
            # Éviter de retenter automatiquement un hotspot en échec au prochain
            # démarrage. Restaurer l'ancienne connexion si son UUID est disponible.
            # || true conserve le message d'erreur final même si la restauration
            # échoue aussi ; le retour au réseau précédent n'est pas garanti.
            nmcli connection modify uuid "$PROFILE_UUID" connection.autoconnect no
            if [[ -f /var/lib/bibliotech/previous-wifi ]]; then
                nmcli --wait 45 connection up uuid "$(cat /var/lib/bibliotech/previous-wifi)" || true
            fi
            die "Échec du point d’accès. Restauration du profil Wi-Fi précédent tentée."
        fi
        # Succès nmcli signifie profil activé ; vérifier depuis un appareil client
        # reste nécessaire pour confirmer association, DHCP et accès au portail.
        ;;
    apply-off)
        # Sérialiser également l'arrêt avec toute activation en cours.
        exec 9>/run/lock/bibliotech-wifi.lock
        flock -n 9 || die 'Une bascule Wi-Fi est en cours.'

        # Désactiver d'abord l'autoconnection, sinon NetworkManager pourrait
        # réactiver aussitôt le profil que l'on vient de déconnecter.
        # Un profil déjà inactif n'empêche pas de tenter le retour au Wi-Fi client.
        nmcli connection modify uuid "$PROFILE_UUID" connection.autoconnect no
        nmcli connection down uuid "$PROFILE_UUID" || true

        # Restaurer le profil sauvegardé, sans en créer un nouveau ni redemander
        # son mot de passe. NetworkManager conserve ses paramètres habituels.
        # Si ce profil a été supprimé entre-temps, nmcli échoue explicitement.
        if [[ -f /var/lib/bibliotech/previous-wifi ]]; then
            nmcli --wait 45 connection up uuid "$(cat /var/lib/bibliotech/previous-wifi)"
        else
            # Sans connexion précédente, ne pas deviner un réseau disponible.
            # Une console locale ou une autre liaison permet de choisir un profil.
            echo 'Aucun ancien profil Wi-Fi enregistré. Utiliser nmcli connection up ou une liaison USB/Ethernet.'
        fi
        ;;
    # Les branches apply-* sont internes ; l'aide ne présente que les actions
    # utiles à l'administrateur. Un argument inconnu ne déclenche aucune bascule.
    *) die 'Usage : bibliotech-hotspot [on|off|status]' ;;
esac
