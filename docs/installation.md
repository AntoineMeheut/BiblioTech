# Installation et exploitation

[← Retour au projet](../README.md)

Ce projet automatise la méthode du dépôt [RaynerMDZ/Kiwix-Raspberry-Pi](https://github.com/RaynerMDZ/Kiwix-Raspberry-Pi) : installation de `kiwix-tools`, création de `library.xml` et démarrage par systemd. Il ajoute un point d’accès Wi-Fi et une carte interactive hors ligne de l’Europe. Le dépôt d’origine est un guide, pas un logiciel à compiler ; ses commandes ont été adaptées ici au **Pi Zero W original, ARMv6, 32 bits**.

Après installation et activation, les utilisateurs rejoignent le réseau **BiblioTech**, saisissent votre mot de passe et ouvrent **http://10.42.0.1/**. Le portail propose les 15 collections Kiwix et la carte. Aucun compte, application cliente ou accès Internet n’est nécessaire ; un navigateur avec WebGL est requis pour la carte.

## Matériel et système

- Raspberry Pi Zero W avec **Raspberry Pi OS Lite 32 bits**, Trixie ou Bookworm, NetworkManager actif. Utiliser l’image officielle adaptée au Zero W dans Raspberry Pi Imager. Un binaire ARMv7 ou ARM64 ne convient pas au Zero W original.
- Alimentation stable et stockage **ext4** suffisamment grand. Les ZIM demandés occupent **105 346 030 965 octets, soit 98,11 Gio**. Ajouter la carte produite, l’OS et une marge : partir sur 256 Go, puis vérifier que l’ensemble tient réellement. La taille de la carte dépend du zoom et des données. FAT32 est refusé, car plusieurs archives dépassent 4 Go.
- Internet pendant la préparation et l’installation. Pour les gros transferts, un adaptateur Ethernet USB/OTG ou le téléchargement préalable sur ordinateur est préférable.
- Pour convertir **Geofabrik Europe** : un ordinateur 64 bits, Java 21+, Python 3 et curl. Prévoir environ **32 Go de RAM et 350 Go de SSD libre**, comme ordre de grandeur, et plusieurs heures. Ces besoins évoluent avec les données.

Le Zero W dispose de peu de mémoire : le serveur utilise deux threads et limite la recherche globale à une archive. Pour chercher dans une collection précise, ouvrir celle-ci avant de lancer la recherche. Les performances avec plusieurs lecteurs et les gros ZIM restent à mesurer sur votre Pi.

## 1. Préparer la carte sur un ordinateur

Geofabrik fournit des données OpenStreetMap `.osm.pbf`, que Kiwix ne sait pas afficher. Le script les convertit en **PMTiles vectoriel avec le schéma OpenMapTiles**. Le Pi sert ensuite le fichier avec nginx ; le téléphone ou l’ordinateur du lecteur dessine la carte. Les scripts, styles et polices sont hébergés sur le Pi.

Depuis le dossier du projet sur l’ordinateur :

```bash
./scripts/prepare-map.sh
```

Le script télécharge Planetiler **0.10.2**, vérifie son SHA-256, télécharge l’extrait **Europe de Geofabrik** et les données auxiliaires du profil OpenMapTiles, puis crée :

```text
build/maps/europe.pmtiles
```

Le zoom maximal des tuiles est 14 ; le navigateur permet de zoomer davantage, sans ajouter de détails. La carte affiche notamment routes, villes, cours d’eau et bâtiments. Elle ne fournit ni recherche d’adresses ni calcul d’itinéraires.

On peut choisir un disque de travail, la mémoire Java et le zoom :

```bash
MAP_JAVA_HEAP=20g MAP_MAXZOOM=14 ./scripts/prepare-map.sh europe /chemin/vers/disque/maps
```

Pour un premier essai léger avec les données de Monaco :

```bash
MAP_JAVA_HEAP=1g ./scripts/prepare-map.sh monaco ./build/monaco
```

Cette commande d’essai télécharge aussi les fonds géographiques mondiaux utilisés par Planetiler. Elle produit `build/monaco/monaco.pmtiles`, **pas la carte Europe**. La génération n’est pas reprise au milieu du calcul : après un échec, déplacer le fichier `*.building.pmtiles` avant de relancer. Les sources déjà téléchargées sont réutilisées. Un fichier final existant n’est jamais écrasé.

## 2. Copier le projet et la carte sur le Pi

Configurer dans Raspberry Pi Imager le compte utilisateur, SSH, le pays Wi-Fi et la connexion Internet initiale. Démarrer le Pi. Remplacer `utilisateur` et `raspberrypi.local` par votre compte et votre adresse réelle dans les commandes suivantes.

Depuis l’ordinateur :

```bash
rsync -av --exclude build --exclude data --exclude .git --exclude __pycache__ \
  ./ utilisateur@raspberrypi.local:~/BiblioTech/

ssh utilisateur@raspberrypi.local 'sudo mkdir -p /srv/bibliotech/maps'
rsync -avP --rsync-path='sudo rsync' build/maps/europe.pmtiles \
  utilisateur@raspberrypi.local:/srv/bibliotech/maps/europe.pmtiles
```

`sudo rsync` à distance suppose que ce compte dispose de sudo sans saisie de mot de passe pour cette commande. Sinon, transférer vers le dossier personnel, puis déplacer le fichier avec `sudo mv`, ou utiliser un disque externe. Éviter deux copies si l’espace manque.

Pour un disque externe, le monter **durablement par UUID** via `/etc/fstab`, par exemple sous `/mnt/bibliotheque`. Créer `maps/` sous ce point de montage et adapter `DATA_DIR`. Le projet ne formate aucun disque et ne modifie pas `/etc/fstab`. Les services utilisent `RequiresMountsFor` pour attendre le stockage au démarrage.

## 3. Installer sur le Pi

Dans une session SSH sur le Pi :

```bash
cd ~/BiblioTech
cp config.example.env config.env
chmod 600 config.env
nano config.env
```

Définir au minimum `WIFI_PASSWORD` (8 à 63 caractères ASCII). Adapter `WIFI_COUNTRY` au pays d’utilisation ; `FR` est la valeur fournie. Le SSID par défaut est `BiblioTech`. Le fichier est une configuration Bash de confiance, réservée à l’administrateur.

```bash
sudo ./install.sh
```

Le script vérifie le matériel, l’OS, le mode AP du pilote Wi-Fi et la présence de la carte. Il installe les paquets depuis les dépôts de Raspberry Pi OS, vérifie que les binaires fonctionnent, télécharge et contrôle les 15 ZIM, crée l’index puis configure les services. Les téléchargements sont séquentiels pour limiter la charge. Ils peuvent durer plusieurs jours sur le Wi-Fi du Zero W ; une session `tmux` ou une console locale permet de les laisser tourner.

Les ZIM sont téléchargés dans `DATA_DIR/zim/*.zim.part`. Chaque fichier devient `.zim` uniquement après vérification de sa taille et de son SHA-256. Relancer la même commande reprend les téléchargements interrompus. Une archive déjà complète est vérifiée et conservée. Un fichier corrompu provoque un arrêt avec un message : le déplacer avant de relancer. L’ancien index reste en place tant que les 15 archives n’ont pas été indexées avec succès.

**Alternative : télécharger les ZIM sur l’ordinateur**, puis les copier sur le Pi :

```bash
python3 scripts/content.py download --data-dir ./data
rsync -avP --rsync-path='sudo rsync' data/zim/ utilisateur@raspberrypi.local:/srv/bibliotech/zim/
```

Sur le Pi, lancer alors `sudo ./install.sh --no-download`. Cette option exige les 15 ZIM locaux et les vérifie ; elle ne supprime pas le besoin d’Internet pour les paquets APT et les ressources web non encore présentes. Pour préparer les ressources web avant la copie du projet : `python3 scripts/fetch-assets.py`.

## 4. Activer le Wi-Fi de la bibliothèque

L’installation prépare le point d’accès sans interrompre la connexion utilisée pour les téléchargements. Une fois l’installation réussie :

```bash
sudo bibliotech-hotspot on
```

La bascule intervient **10 secondes plus tard** dans un service systemd, même si SSH se déconnecte. Le profil démarre ensuite automatiquement au redémarrage. Si NetworkManager signale un échec d’activation, le script désactive l’autoconnection du point d’accès et tente de réactiver le profil précédent.

1. Rejoindre **BiblioTech** avec le mot de passe configuré.
2. Accepter de rester connecté même si le téléphone indique « pas d’Internet ».
3. Ouvrir **http://10.42.0.1/** (HTTP, pas HTTPS).

Le réseau utilise WPA2, 2,4 GHz, le canal configuré et le sous-réseau `10.42.0.0/24`. NetworkManager fournit DHCP et DNS. Le téléphone reçoit automatiquement une adresse. Il n’y a pas de portail captif automatique : l’adresse doit être ouverte dans le navigateur. Le nom d’hôte du Pi reste inchangé.

La radio intégrée est utilisée soit comme client du Wi-Fi habituel, soit comme point d’accès. Une connexion Ethernet/USB supplémentaire peut fournir Internet pendant que le point d’accès fonctionne. Le mode `shared` de NetworkManager partage aussi cette connexion amont avec les clients s’il en existe une.

## Collections exactes

Les liens ont été vérifiés le **17 octobre 2026** dans les répertoires officiels et via leurs fichiers Metalink `.meta4`. [config/contents.json](../config/contents.json) conserve les URL d’origine, les URL de téléchargement, les tailles et les SHA-256. Aucun remplacement par une édition plus récente n’est automatique.

| Collection | Identifiant | Taille arrondie |
|---|---|---:|
| Gutenberg | `gutenberg_fr_all_2026-01` | 9,81 Gio |
| iFixit | `ifixit_fr_all_2026-03` | 3,40 Gio |
| Breizh Partitions | `breizhpartitions_fr_all_2026-02` | 5,27 Gio |
| Cuisine Libre | `cuisinelibre.org_fr_all_2026-08` | 0,24 Gio |
| Bouquineux | `bouquineux.com_fr_all_2025-12` | 5,54 Gio |
| Low-tech Magazine | `solar.lowtechmagazine.com_mul_all_2025-01` | 0,65 Gio |
| Solidarité Numérique | `www.solidarite-numerique.fr_fr_all_2025-11` | 0,20 Gio |
| Psiram | `psiram_fr_all_maxi_2026-08` | 0,28 Gio |
| Wikibooks | `wikibooks_fr_all_maxi_2026-10` | 1,07 Gio |
| Wikipédia | `wikipedia_fr_all_maxi_2026-05` | 51,63 Gio |
| Wikiquote | `wikiquote_fr_all_maxi_2026-08` | 0,11 Gio |
| Wikisource | `wikisource_fr_all_maxi_2025-09` | 14,60 Gio |
| Wikiversity | `wikiversity_fr_all_maxi_2026-08` | 0,47 Gio |
| Wikivoyage | `wikivoyage_fr_all_maxi_2026-07c` | 0,23 Gio |
| Wiktionary | `wiktionary_fr_all_nopic_2026-08` | 4,60 Gio |

Le suffixe `07c` de Wikivoyage est volontaire : il existe bien sur le serveur. Geofabrik est représenté par la carte du portail, séparée de l’index Kiwix parce que son format n’est pas un ZIM.

```bash
python3 scripts/content.py plan          # Tailles sans connexion Internet
python3 scripts/content.py check-remote  # Revérifier les 15 éditions et empreintes
```

Si une édition disparaît du serveur, l’installation échoue explicitement. Pour changer d’édition, modifier son identifiant et son URL dans le manifeste, puis renseigner la taille et le SHA-256 du nouveau `.meta4`. Les anciens fichiers sur le disque ne sont pas supprimés ; l’index contient uniquement les entrées du manifeste.

## Maintenance et diagnostic

```bash
sudo bibliotech-hotspot status
sudo journalctl -u bibliotech -u bibliotech-web -n 100 --no-pager
sudo journalctl -u bibliotech-hotspot-on -n 100 --no-pager
df -h /srv/bibliotech
free -h
```

Pour revenir au Wi-Fi client et télécharger des mises à jour :

```bash
sudo bibliotech-hotspot off
```

La session SSH locale est interrompue après 10 secondes ; se reconnecter via le réseau habituel. En l’absence de profil mémorisé, utiliser une console locale ou Ethernet/USB et `sudo nmcli connection up NOM_DU_PROFIL`. Les profils clients existants ne sont pas supprimés.

Pour réindexer des ZIM déjà copiés, y compris hors ligne :

```bash
sudo python3 /opt/bibliotech/scripts/content.py index --data-dir /srv/bibliotech
sudo systemctl restart bibliotech
```

Pour mettre à jour la configuration, relancer le projet avec `sudo ./install.sh --no-download`. Si le point d’accès est déjà actif, appliquer les nouveaux paramètres radio avec `sudo bibliotech-hotspot on`. Ne pas lancer l’activation pendant les téléchargements.

En cas de carte vide, vérifier `sudo python3 /opt/bibliotech/scripts/check-map.py /srv/bibliotech/maps/europe.pmtiles` et l’URL `http://10.42.0.1/maps/europe.pmtiles`. Ce chemin sert un gros fichier : pour un contrôle technique limité, utiliser `curl -r 0-7 -i http://10.42.0.1/maps/europe.pmtiles` et vérifier HTTP **206**. Ne pas compresser le PMTiles au niveau HTTP et ne pas le remplacer par un fichier `.osm.pbf`.

Pour arrêter le projet : `sudo bibliotech-hotspot off`, puis `sudo systemctl disable --now bibliotech bibliotech-web`. Les données restent sur le disque. Le projet est destiné à un Pi dédié ; l’installateur refuse un port 80 ou 8080 déjà occupé lors de la première installation et désactive le service nginx standard au profit de sa propre instance.

## Vérification et limites des tests

```bash
./tests/check.sh
```

Les tests vérifient la reprise des transferts, l’intégrité, l’espace disque, les échecs d’indexation et les en-têtes cartographiques. ShellCheck est utilisé s’il est installé. Voir le [rapport de validation](validation.md) pour les essais effectués et les vérifications restant à faire sur le Pi. Aucun essai logiciel sur ordinateur ne remplace le test du Wi-Fi, du démarrage et de la mémoire sur le matériel réel.

## Sources et licences

- [Guide RaynerMDZ](https://github.com/RaynerMDZ/Kiwix-Raspberry-Pi) : méthode d’installation Kiwix, licence GPL-3.0 ; ce projet est distribué sous la même licence, voir [LICENSE](../LICENSE).
- [Documentation kiwix-serve](https://kiwix-tools.readthedocs.io/en/latest/kiwix-serve.html) : serveur et options.
- [Configuration Raspberry Pi](https://www.raspberrypi.com/documentation/computers/configuration.html) et [NetworkManager](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html) : réseau et mode partagé.
- [Geofabrik Europe](https://download.geofabrik.de/europe.html) : source OSM ; les données OSM sont sous ODbL avec attribution © OpenStreetMap contributors.
- [Planetiler 0.10.2](https://github.com/onthegomap/planetiler/tree/v0.10.2) : conversion, ressources nécessaires et sources auxiliaires ; licence Apache-2.0.
- [PMTiles avec MapLibre](https://docs.protomaps.com/pmtiles/maplibre) : consultation avec requêtes HTTP Range. MapLibre GL JS 5.6.1 et PMTiles JS 4.3.0 : BSD-3-Clause. Polices [OpenMapTiles](https://github.com/openmaptiles/fonts) : voir leurs licences dans `web/licenses/` et les mentions téléchargées dans `web/vendor/`.

Les contenus ZIM conservent leurs licences propres, consultables dans les archives. Le portail affiche l’attribution cartographique ; les liens d’attribution externes nécessitent Internet, mais la carte elle-même fonctionne sans réseau amont.
