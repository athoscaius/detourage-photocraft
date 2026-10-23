# Détourage PhotoCraft

Extension compagnon personnelle pour **PhotoCraft**, l’éditeur d’images de la suite ArtCraft. Application native pour ce Mac Apple Silicon, macOS 14 ou ultérieur. Version 1.3.2.

L’icône utilise le chat de Pallas sur fond vert fourni par l’utilisateur. Le fichier original est conservé dans `assets/provided-icon.png`. La préparation ICNS garde le dessin et sa transparence, sans nouveau fond ni régénération.

## Utilisation

1. Ouvrir **Détourage PhotoCraft** depuis Applications.
2. Cliquer sur **Ouvrir PhotoCraft** dans le compagnon. Si PhotoCraft était déjà ouvert normalement, enregistrer le travail puis le quitter avant ce premier lancement connecté.
3. Ouvrir la photo ou le PSD souhaité dans PhotoCraft et choisir son calque.
4. Dans le panneau **Détecter**, choisir **Personne** ou **Autre sujet**. Dans **Créer**, choisir **Sélection fine** ou **Masque de calque**.
5. Cliquer sur le bouton bleu **Sélectionner la personne** ou **Sélectionner le sujet**. La sélection douce ou le masque modifiable apparaît dans PhotoCraft. Un masque existant est protégé contre l’écrasement.

La fenêtre adopte les panneaux anthracite, les séparateurs fins et l’accent bleu de PhotoCraft. Le bandeau supérieur indique la photo détectée lors de la dernière vérification ; **↻** actualise la connexion et le nom de la photo. La connexion est aussi vérifiée au lancement du compagnon si PhotoCraft est disponible. Les détails de progression et les erreurs restent dans le panneau inférieur. La fenêtre est redimensionnable.

Le mode **Sujet** traite aussi d’autres objets. Le mode Personne utilise un repère humain pour conserver aussi le contexte proche reconnu, notamment les objets tenus. Le mode Autre sujet traite le premier plan reconnu par le modèle. Les modes ne proposent pas le choix explicite d’une seule personne dans un groupe. L’analyse porte sur l’image visible composée de tous les calques, à la taille du document.

Laisser le document et le calque actifs inchangés pendant le calcul. Les pointillés de sélection représentent seulement le contour à 50 % : les nuances des cheveux restent dans la couverture du masque. Dans PhotoCraft, utiliser Sélectionner et masquer pour les retouches éventuelles. Annuler avec ⌘Z ; la création d’un masque ajoute une seconde étape d’historique après la sélection.

## Qualité et traitement

Les deux modes utilisent désormais **BiRefNet-matting**, modèle neuronal général dédié au matting, en entrée 1 024 × 1 024. Il analyse le premier plan complet pour mieux conserver les équipements et objets portés ou tenus. En mode Personne, Apple Vision `accurate` fournit un repère humain ; ce repère sert à retenir les composantes du sujet et les accessoires proches, sans couper le masque final à la silhouette du corps.

Le masque conserve les transparences partielles et les mèches, sans seuil binaire ni étirement automatique du contraste. La couverture est redimensionnée à la taille du document avant quantification ; l’alpha initial est appliqué exactement une fois. La résolution du document ne correspond donc pas à une inférence native sur chaque pixel. Le modèle ne peut pas recréer une mèche absente de la photo ; cheveux flous, fond proche ou objets mal séparés peuvent encore demander une retouche. Il ne corrige pas la contamination de couleur du fond dans les cheveux. Limite : 64 mégapixels, 32 768 pixels par côté.

Sur ce Mac, les essais du moteur seul ont pris environ **20 à 25 secondes**, y compris une image de 24 MP. Le premier essai dans l’application a dépassé une minute ; prévoir davantage selon le chargement initial et la charge du Mac. Le calcul est volontairement plus lourd que précédemment et dépend de la charge du Mac ; laisser finir une opération avant de relancer. La variante 2K a été écartée après un essai trop gourmand pour les 16 Go de ce Mac.

Les images restent sur le Mac. Aucune clé API, aucun abonnement ni envoi de photo à un service externe. Le modèle officiel MIT (environ 973 Mo), un runtime Python autonome et les dépendances figées sont inclus dans l’application, qui occupe environ 1,2 Go. L’inférence ne télécharge rien et la télémétrie ONNX Runtime est désactivée. L’interface et les fonctions de détourage restent inchangées dans cette mise à jour de nom et d’icône. Le pont effectue une lecture de session toutes les dix secondes pendant l’inférence pour éviter la fermeture de la connexion inactive par PhotoCraft ; les protections du document et l’absence de réessai des modifications restent en place. Le pont utilise encore Python 3 fourni par les outils Apple ; le nouveau moteur possède son propre Python et ne dépend pas de Codex.

## Mises à jour

Le compagnon est installé **à côté de PhotoCraft**, sans modifier son application ni sa signature. Les mises à jour effectuées par ArtCraft Launcher ne remplacent donc pas le compagnon. Il retrouve PhotoCraft par son identifiant d’application et vérifie les commandes nécessaires avant chaque exécution.

Cette architecture réduit la fragilité mais ne garantit pas une compatibilité éternelle : si ArtCraft modifie son protocole public, le pont pourra nécessiter une adaptation. En cas de commande manquante, l’extension s’arrête avec un message au lieu de tenter un clic ou une modification incertaine. Après une mise à jour, quitter puis rouvrir PhotoCraft depuis le compagnon.

Le canal de commande écoute uniquement sur `127.0.0.1`, avec un jeton d’authentification privé. Ses accès aux fichiers sont limités au dossier de travail du compagnon. Il reste actif jusqu’à la fermeture de PhotoCraft.

## Fichiers et entretien

- Application : `/Applications/Détourage PhotoCraft.app`.
- Données : `~/Library/Application Support/ArtCraft Detourage IA/`.
- Les masques calculés sont conservés dans son sous-dossier de travail pour récupération. L’export temporaire de la photo est supprimé après chaque tentative terminée ; une interruption brutale peut le laisser sur disque.
- La réinstallation conserve l’ancienne version du compagnon en ZIP dans `backups.noindex/`.
- Pour désinstaller, quitter le compagnon et PhotoCraft, puis mettre l’application compagnon à la Corbeille. Son dossier de données peut être conservé ou supprimé séparément. PhotoCraft reste intact.
- Le code source est dans `source/`. `build.command` reconstruit une application arm64 avec les outils de ligne de commande Xcode. `Installer.command` installe l’application construite.

La signature est locale (« ad hoc »), pour ce Mac. Ce paquet n’est pas une distribution signée et notariée pour d’autres utilisateurs.

## Références techniques

- [Contrat officiel des plugins PhotoCraft ABI v1](https://github.com/storytold/photocraft/blob/6a2d027ee2e7ca12afd248544ed2262b0fa078dd/docs/plugins.md).
- [Canal de commande officiel utilisé](https://github.com/storytold/photocraft/blob/6a2d027ee2e7ca12afd248544ed2262b0fa078dd/docs/control-protocol.md).
- [Algorithme de sélection actuel de PhotoCraft](https://github.com/storytold/photocraft/blob/6a2d027ee2e7ca12afd248544ed2262b0fa078dd/crates/algo/src/segment/subject.rs).
- [BiRefNet : modèle officiel de matting, licence MIT](https://huggingface.co/ZhengPeng7/BiRefNet-matting).
- [BiRefNet : code et publications officiels](https://github.com/ZhengPeng7/BiRefNet).
- [Runtime autonome Python officiel](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021).
- [Apple Vision : masques de personnes](https://developer.apple.com/documentation/vision/applying-matte-effects-to-people-in-images-and-video).
- [Apple Vision : masques de premier plan](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest).

La photo de contrôle NASA provient des exemples officiels [scikit-image](https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut). Elle sert uniquement à la vérification technique et n’implique aucun soutien de la NASA ou de la personne photographiée.


## Connexion automatique — 1.2.1

Le compagnon configure désormais les variables officielles PhotoCraft dans la session graphique macOS et installe `~/Library/LaunchAgents/local.artcraft.detourage-connection.plist` pour les réappliquer à chaque ouverture de session. Les lancements normaux via macOS héritent ainsi du port local authentifié et des accès limités au dossier de travail. Aucun fichier PhotoCraft n’est modifié. Une application déjà lancée ne peut pas recevoir rétroactivement ces variables : enregistrer les documents puis quitter et rouvrir PhotoCraft une fois après cette correction. Les lancements directs par un processus tiers déjà ouvert peuvent encore nécessiter le bouton du compagnon.

Le script privé se trouve dans le dossier de données du compagnon sous `connection-environment.command`. Pour retirer la configuration : décharger cet agent avec `launchctl bootout`, supprimer son plist puis retirer les quatre variables `PHOTOCRAFT_CONTROL_PORT`, `PHOTOCRAFT_CONTROL_TOKEN_FILE`, `PHOTOCRAFT_AUTOMATION_READ_ROOT`, `PHOTOCRAFT_AUTOMATION_WRITE_ROOT` avec `launchctl unsetenv`.


## Chargement — 1.3.0

Pendant une opération, une jauge bleue animée apparaît dans le panneau de statut avec le temps réellement écoulé, au format minutes:secondes. L’analyse IA n’expose pas de progression chiffrée : la jauge est volontairement indéterminée et n’invente ni pourcentage ni temps restant. Après application du résultat, elle se remplit et indique la durée totale. En cas d’erreur, l’animation et le compteur sont arrêtés et le message d’erreur prend la place. La préférence macOS Réduire les animations est respectée. Le panneau garde les surfaces anthracite, l’accent bleu et les petites tailles de texte de l’outil ; la fenêtre passe à 640 × 580 pour accueillir la jauge.


## Icône 1.3.1

L’icône actuelle est le nouveau dessin fourni par l’utilisateur, conservé tel quel dans `assets/provided-icon.png`.

Identité visuelle : nom « Détourage PhotoCraft » et nouvelle icône fournie par l’utilisateur. Le dessin source est conservé dans `assets/provided-icon.png`, sans régénération. Les identifiants internes et dossiers de connexion restent inchangés pour conserver la configuration existante.
