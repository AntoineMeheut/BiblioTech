# Personnaliser le portail

[← Retour au projet](../README.md)

Le site diffusé par le Raspberry Pi adopte une ambiance inspirée de **Blade Runner (1982)** : nuit, pluie, architecture verticale, écrans de terminal et enseignes lumineuses. La bannière est une composition ASCII originale représentant une ville survolée par un dirigeable BiblioTech. Le README conserve son identité cyberpunk jaune et cyan.

## Fichiers à modifier

| Fichier | Rôle |
| :--- | :--- |
| [web/index.html](../web/index.html) | Textes d’accueil, illustration ASCII et liens vers les deux services. |
| [web/style.css](../web/style.css) | Palette, typographie, disposition, effets et adaptations aux petits écrans. |
| [web/map/index.html](../web/map/index.html) | En-tête et commandes de la page cartographique. |
| [web/map/map.js](../web/map/map.js) | Affichage des données, couches, étiquettes et interactions de la carte. |

Le thème habille l’accueil et l’en-tête cartographique. Kiwix et les documents ZIM gardent leurs interfaces de lecture respectives. La carte conserve un fond clair pour distinguer les routes et les noms.

## Modifier la bannière ASCII

Dans `web/index.html`, modifier le contenu du bloc `<pre class="city-art">`. Conserver les espaces et les retours à la ligne : ils forment l’illustration. Ne pas utiliser de tabulations et ne pas appliquer de reformateur automatique à l’intérieur du bloc. Les classes `neon-amber`, `neon-cyan` et `neon-red` colorent les enseignes et les fenêtres.

Pour ajouter les caractères `<` ou `&`, écrire respectivement `&lt;` ou `&amp;`. Les antislashs restent de simples caractères HTML. Garder des lignes d’une largeur comparable à celles du dessin d’origine afin de préserver son affichage mobile.

L’art ASCII est masqué aux lecteurs d’écran pour éviter la lecture de chaque symbole. Mettre à jour l’attribut `aria-label` de la figure si la scène change. Les titres, descriptions et liens restent de véritables éléments HTML accessibles.

## Palette et comportement

Les variables définies au début de `web/style.css` pilotent le thème :

| Variable | Usage |
| :--- | :--- |
| `--night` | Fond nocturne. |
| `--ink`, `--muted` | Texte principal et texte secondaire. |
| `--amber` | Bibliothèque et accents chauds. |
| `--cyan` | Carte et accents froids. |
| `--red` | Détails des enseignes ASCII. |
| `--line` | Séparateurs et bordures. |

L’accueil ne charge ni JavaScript, ni police distante, ni image. Les effets de néon et de trame sont statiques. Les cartes de navigation se placent sur une seule colonne sous 700 pixels ; le défilement doux est désactivé quand le navigateur demande une réduction des mouvements.

Le nombre de collections affiché est éditorial : le modifier si la sélection du manifeste change. Il ne représente pas une mesure en temps réel. L’adresse `10.42.0.1` correspond au réseau configuré par l’installateur ; un changement d’adressage doit être reporté dans le portail et les scripts.

## Prévisualiser et déployer

Ouvrir `web/index.html` dans un navigateur pour voir l’accueil avec sa feuille de style locale. Les liens `/bibliotheque/` et `/map/` sont prévus pour le serveur HTTP et ne fonctionnent pas depuis une ouverture en `file://`. Pour tester la carte, suivre les instructions d’[aperçu local](validation.md#aperçu-local-facultatif).

Avant de diffuser une modification, vérifier les formats 320, 390, 768 et 1280 pixels, le focus au clavier et le contraste des textes. Conserver les crédits cartographiques et les explications de connexion sans Internet.

Sur un Pi déjà installé, depuis la nouvelle copie du projet :

```bash
sudo install -m 644 web/index.html web/style.css /opt/bibliotech/web/
sudo install -m 644 web/map/index.html /opt/bibliotech/web/map/
```

Ces fichiers statiques sont servis immédiatement ; recharger la page dans le navigateur. Aucun redémarrage de Kiwix ni téléchargement des collections n’est nécessaire pour une modification de présentation.
