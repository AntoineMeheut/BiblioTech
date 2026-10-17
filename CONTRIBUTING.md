# Contribuer à BiblioTech

Le projet vise le Raspberry Pi Zero W original : **ARMv6, 32 bits et 512 Mo de RAM**. Les contributions doivent préserver cette cible et le fonctionnement hors ligne après installation.

## Préparer l’environnement

Sur Linux ou macOS, installer Bash, Python 3.9 ou plus récent, Node.js 18 ou plus récent et ShellCheck. Aucune dépendance Python supplémentaire n’est nécessaire pour les tests.

```bash
./tests/check.sh
```

La commande n’exécute pas l’installateur système, ne télécharge pas les ZIM et ne convertit pas l’Europe. ShellCheck et Node.js sont utilisés lorsqu’ils sont présents ; le workflow GitHub Actions exige les deux pour éviter une validation partielle.

Pour travailler sur la carte, voir [la prévisualisation locale](docs/validation.md#aperçu-local-facultatif). Les ressources téléchargées dans `web/vendor/` et les fichiers générés dans `build/` restent hors du dépôt.

## Organisation

| Chemin | Rôle |
| :--- | :--- |
| `install.sh` | Installation et configuration des services sur le Pi. |
| `scripts/` | Configuration, contenus, cartographie et prévisualisation. |
| `config/contents.json` | Éditions, URL, tailles et empreintes des collections. |
| `web/` | Portail local et interface cartographique. |
| `tests/` | Contrôles et tests qui fonctionnent sans matériel Raspberry Pi. |
| `docs/` | Installation, état des vérifications et publication manuelle. |
| `docs/assets/` | Illustrations SVG originales du README. |

## Proposer un changement

1. Décrire le besoin dans une issue ou directement dans une pull request pour une correction ciblée.
2. Créer une branche et réaliser un changement de portée limitée.
3. Exécuter les vérifications et actualiser la documentation concernée.
4. Décrire le résultat, les tests effectués et les éventuelles limites de validation matérielle.

Pour l’installation ou le réseau, vérifier la conservation des profils Wi-Fi existants, la reprise après erreur, les permissions des services et le démarrage après redémarrage. Ne pas présenter un test sur ordinateur comme une validation sur ARMv6.

Pour une nouvelle édition ZIM, récupérer la taille et le SHA-256 depuis son `.meta4`, conserver le lien de consultation d’origine et mettre à jour les chiffres documentés. Un changement d’édition doit être explicite. La commande `python3 scripts/content.py check-remote` nécessite Internet ; elle ne télécharge que les métadonnées.

## Style et licences

Conserver les messages utilisateur et la documentation en français, les scripts shell avec des fins de ligne LF et des dépendances compatibles avec le Pi. Les nouveaux visuels doivent rester lisibles sur GitHub en thème clair comme en thème sombre, avec un texte alternatif.

Les contributions au code du projet sont distribuées sous la [licence GPL-3.0](LICENSE). Conserver les attributions des dépendances, contenus et données. Les archives, ressources téléchargées et configurations privées ne sont pas à joindre aux pull requests.
