# Détourage PhotoCraft

Compagnon macOS indépendant pour détourer une personne, ses accessoires ou un sujet dans PhotoCraft. Masque doux, transparences et cheveux, moteur BiRefNet-matting local ; icône du chat de Pallas sur fond vert. Projet personnel, non officiel et non affilié à ArtCraft.

## Installer

Télécharger le [DMG Apple Silicon](https://github.com/athoscaius/detourage-photocraft/releases/latest/download/Detourage-PhotoCraft-1.3.2-arm64.dmg), l’ouvrir et glisser l’application dans **Applications**. Lancer le compagnon puis **Ouvrir PhotoCraft**. Si PhotoCraft était déjà ouvert, enregistrer puis quitter et rouvrir PhotoCraft une fois.

Configuration : **Mac Apple Silicon, macOS 14+**, PhotoCraft avec son protocole de contrôle public, Python 3 des outils de ligne de commande Apple pour le pont. Le modèle et le runtime d’inférence sont inclus dans le DMG ; aucune clé API ni connexion réseau n’est nécessaire au détourage. L’app occupe environ 1,2 Go. Le calcul peut dépasser une minute selon la charge du Mac.

La distribution est signée localement (ad hoc), **sans Developer ID ni notarisation Apple**. Gatekeeper peut nécessiter une autorisation manuelle dans Réglages Système > Confidentialité et sécurité sur un autre Mac. Le DMG ne supprime aucune protection macOS.

## Utiliser

Ouvrir une image dans PhotoCraft, choisir Personne ou Autre sujet, puis Sélection fine ou Masque de calque. Laisser la photo et son calque actifs pendant le calcul. Une jauge animée indique l’activité et le temps écoulé ; la durée totale apparaît à la fin. Les résultats peuvent encore demander une retouche, surtout sur des contours flous ou proches du fond.

Le mode Personne utilise un repère Apple Vision et un masque général BiRefNet pour garder aussi les objets proches ou tenus. Inférence 1024 × 1024, masque redimensionné au document, alpha initial conservé. Limites : 64 MP, 32 768 pixels par côté. Aucun masque existant n’est écrasé.

## Connexion et mises à jour

L’application PhotoCraft n’est pas modifiée. Le compagnon vérifie les commandes du protocole et protège la photo contre des changements pendant le calcul. Les évolutions du protocole peuvent nécessiter une adaptation ; la compatibilité avec toutes les versions futures ne peut être garantie.

Au premier lancement, le compagnon installe un LaunchAgent utilisateur `local.artcraft.detourage-connection` qui configure les variables officielles du serveur PhotoCraft pour les prochains lancements graphiques. Le serveur écoute en boucle locale avec un jeton privé et des accès limités au dossier de travail. Les données et masques sont dans `~/Library/Application Support/ArtCraft Detourage IA/`. Le pont maintient la connexion pendant les calculs longs par une lecture toutes les dix secondes.

Pour désinstaller : quitter le compagnon, retirer l’application, décharger le LaunchAgent avec `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.artcraft.detourage-connection.plist`, puis supprimer ce plist. Retirer avec `launchctl unsetenv` les variables `PHOTOCRAFT_CONTROL_PORT`, `PHOTOCRAFT_CONTROL_TOKEN_FILE`, `PHOTOCRAFT_AUTOMATION_READ_ROOT`, `PHOTOCRAFT_AUTOMATION_WRITE_ROOT`. Le dossier de données peut être supprimé séparément.

## Construire et vérifier

```sh
./build.command
/usr/bin/python3 -m unittest discover -s source/tests
```

La construction nécessite les outils Xcode, une connexion réseau initiale et environ 2 Go pour récupérer le modèle officiel et le runtime autonome. Versions et SHA-256 sont figés dans `source/matting-model.json`, `requirements-matting.lock` et `prepare_ai.command`. Les grands binaires sont livrés en release et exclus du dépôt Git.

## Composants et droits

- [PhotoCraft](https://github.com/storytold/photocraft) : application hôte, non incluse.
- [BiRefNet-matting](https://huggingface.co/ZhengPeng7/BiRefNet-matting) : modèle officiel sous MIT, notice dans `source/BiRefNet-LICENSE.txt`.
- Runtime [python-build-standalone](https://github.com/astral-sh/python-build-standalone), notices conservées dans `source/runtime-licenses/` ; autres dépendances sous leurs licences propres.
- Icône du chat de Pallas fournie par l’utilisateur, source `assets/provided-icon.png`.

Aucune licence libre supplémentaire n’est accordée au code propre à ce projet ; les composants tiers conservent leurs licences respectives.

## Version 1.3.2

Nom de l’application : **Détourage PhotoCraft**. Icône fournie par l’utilisateur. Les fonctions, le moteur et la connexion de la version précédente sont conservés. La mise à jour migre l’ancien nom de l’application et conserve sa configuration.
