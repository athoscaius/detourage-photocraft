# Icône actuelle — Manul / Chat de Pallas (1.3.1)

Illustration originale créée avec l’outil ImageGen intégré. Le manul remplace le lynx : visage large, oreilles petites et arrondies placées sur les côtés, fourrure dense. Le style reprend les gravures naturalistes des icônes PhotoCraft, FilmCraft et PdfCraft installées : encre noire, aplats ivoire, fond cuivre-orange. Ces images servent uniquement de références de style.

Le prompt final exact et les rôles des références sont conservés dans [MANUL-PROMPT.txt](MANUL-PROMPT.txt). Le dessin source est `manul-opaque.png`, entièrement opaque. `source/prepare_icon.command` applique le gabarit macOS avec transparence extérieure puis crée `app-icon.png` et `AppIcon.icns` en tailles standard et Retina. L’intérieur du carré arrondi reste opaque, sans trou dans le visage ou les yeux.

Dans l’application, le fichier ICNS est versionné `AppIcon-v4.icns` pour actualiser l’icône macOS. Le PNG interne conserve son alias `AppIcon-v3.png`, utilisé par le code existant pour l’image du Dock ; il contient bien le nouveau manul. Le code et le fonctionnement de l’application sont conservés.

## Historique : ancien lynx

# Icône — ArtCraft Détourage IA

Illustration originale produite avec l’outil intégré ImageGen, à partir des icônes installées PhotoCraft, FilmCraft et PdfCraft utilisées uniquement comme références visuelles. Animal choisi : lynx. Gravure noire et ivoire, fond cuivre, angles arrondis et transparence extérieure. Le signe reste distinct des mascottes officielles de la suite.

Prompt initial :

Create a SINGLE new polished macOS app icon, 1024 square, matching the reference icons' natural history woodcut engraving aesthetic. References show a fox, owl and lion; create a NEW beautiful LYNX head and chest instead. Calm alert expression, front view, long ear tufts fully visible, delicate long whiskers and crisp black engraved fur hatching on warm ivory paper-colored fills. Strong readable silhouette at small sizes.
Use a SOLID FLAT BURNT ORANGE / COPPER (#D86D35) rounded square backdrop, NOT teal or cyan. No texture, gradient, marks, holes, objects or rings on the background: clean completely uniform orange EVERYWHERE behind the animal including between and above the ears. The only elements are the orange tile and the black-and-ivory lynx engraving.
Composition matches the reference icons: colored tile at approximately [100,100,924,924] on a 1024x1024 canvas, corner radius185; generous fully transparent outer margin. Lynx ear tips near145; head and chest fill the tile, chest cropped at bottom920. All parts of the orange tile are fully opaque. Outside the tile is genuinely transparent alpha. No text, badges, logo initials, scissors, sparkle, gradients, shadow, glow, photography, 3D, extra animal, border or mockup. ONE finished icon.

Correction 1.0.2 : le dessin est désormais généré sans transparence, puis intégré dans un gabarit natif macOS aux coins arrondis. L’intérieur est opaque à 100 % ; seule la marge extérieure est transparente. Le fichier `lynx-opaque.png` est le dessin source, `app-icon.png` le résultat du gabarit, et `AppIcon.icns` l’icône multi-résolution.

Prompt de correction (outil ImageGen intégré) :

Repair this lynx app icon for reliable macOS packaging. Preserve the black-and-ivory engraved lynx, face, ear tufts, whiskers, and copper-orange palette. Make a COMPLETELY OPAQUE square image: extend a clean flat copper-orange #D86D35 backdrop to EVERY EDGE and EVERY CORNER of the canvas. Remove the original transparent outside margin and rounded-square shape by filling them with matching orange. The entire square must be opaque, with NO transparent pixels or holes anywhere, including eyes, forehead and fur. No rings, empty spots, watermarks, extra shapes or text. Keep full ear tufts and ample room above them; do NOT crop the ears. Keep the same animal composition, with chest meeting the bottom edge. Output a flat square illustration, NOT a mockup; native macOS packaging will add the exterior rounded mask separately.
