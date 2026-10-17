# Validation du projet

État au 17 octobre 2026, sur l’ordinateur de développement macOS. Les commandes d’installation système n’ont pas été exécutées sur cet ordinateur.

## Contrôles effectués

- Les 15 archives exactes existent dans les répertoires de `download.kiwix.org`. Leurs fichiers `.meta4` ont fourni les tailles et SHA-256 enregistrés dans `config/contents.json`. Aucun ZIM complet n’a été téléchargé pendant le développement.
- `bash -n` et ShellCheck 0.11.0 : scripts shell valides.
- Après l’ajout des commentaires de maintenance, les lignes exécutables des cinq scripts shell sont identiques à celles de la version précédente.
- Le renommage BiblioTech a ensuite harmonisé les chemins, les services, le compte de service et les commandes d’administration. Les noms des paquets Kiwix et les URLs des 15 collections sont conservés ; la bibliothèque est désormais exposée sous `/bibliotheque/`.
- 14 tests Python passent : fichiers complets, reprise des fichiers partiels, coupure de transfert, mauvaise empreinte, réserve disque, index atomique, manifeste, carte tronquée et schéma incompatible.
- Les scripts Python se compilent ; la syntaxe JavaScript est vérifiée par Node.js.
- Les distributions MapLibre GL JS 5.6.1, PMTiles JS 4.3.0 et les polices sont téléchargées et leurs empreintes vérifiées. Les 260 fichiers nécessaires sont installés localement sous `web/vendor/`.
- Un extrait Geofabrik **Monaco** a été converti avec Planetiler 0.10.2, Java 21, `--maxzoom=14` et `--storage=mmap`. Pour ce test uniquement, les petits fonds d’essai Monaco du dépôt Planetiler ont été utilisés, avec les lignes de lacs du profil. Le résultat fait 420 861 octets et contient les couches OpenMapTiles attendues. Le script Europe utilise les fonds complets.
- Le style passe le validateur officiel `@maplibre/maplibre-gl-style-spec` 23.3.0. PMTiles JS lit les métadonnées du fichier produit et décompresse une vraie tuile de Monaco (186 148 octets). La configuration des tuiles et des polices ne référence que le serveur local.
- Le portail HTML/CSS a été ouvert depuis des fichiers locaux : cartes de navigation et bas de page dans Safari ; bannière complète à 1100 pixels et haut de page à 390 pixels dans Chrome. La revue complète des formats mobiles reste à faire ; ces contrôles locaux ne testent pas les services du Pi.

Les tests de lecture PMTiles et de conformité du style sont disponibles dans `tests/test_map.cjs`. La conversion de l’Europe complète n’a pas été exécutée : elle demande un stockage important et plusieurs heures de calcul.

## Vérifications à faire sur le Raspberry Pi

1. Installer sur Raspberry Pi OS Lite 32 bits et vérifier l’exécution de `kiwix-serve --version` sans erreur d’instruction CPU. L’installateur réalise ce contrôle avant la préparation Wi-Fi.
2. Vérifier que les 15 collections apparaissent dans `/bibliotheque/`, ouvrir des articles de Wikipédia et des pages de chacune des archives web, puis tester une recherche dans chaque collection.
3. Activer `bibliotech-hotspot on`, rejoindre le SSID depuis un téléphone, vérifier l’obtention d’une adresse `10.42.0.x` et l’accès à `http://10.42.0.1/`.
4. Débrancher la connexion Internet amont ; parcourir plusieurs zones de la carte et vérifier l’affichage des noms, des routes et des bâtiments. Un navigateur WebGL récent est nécessaire.
5. Redémarrer le Pi et confirmer le retour du Wi-Fi, de la bibliothèque et de la carte. Pour un disque externe, confirmer le montage automatique avant les services.
6. Tester `bibliotech-hotspot off` et le retour au profil Internet antérieur.
7. Observer la mémoire et la latence avec le nombre réel d’utilisateurs. Le Zero W ne permet pas de garantir une charge importante à partir de tests sur ordinateur.
8. Vérifier le portail à 320, 390, 768 et 1280 pixels de large, la bannière ASCII, le parcours au clavier et les liens vers la bibliothèque et la carte.

## Aperçu local facultatif

Après préparation des ressources web et d’un PMTiles compatible :

```bash
python3 scripts/fetch-assets.py
python3 scripts/preview.py --map build/maps/europe.pmtiles
```

Ouvrir `http://127.0.0.1:8765/`. Ce serveur de développement sait répondre aux requêtes Range ; il ne remplace pas nginx en production et ne démarre pas Kiwix. L’environnement de développement utilisé ici a refusé l’ouverture d’un port d’écoute : aucun test HTTP réel de nginx n’est donc revendiqué. L’accueil peut aussi être ouvert directement depuis `web/index.html` pour contrôler son apparence, sans accès aux services.
