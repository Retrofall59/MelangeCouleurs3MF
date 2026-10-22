# Changelog

Historique de développement au fil des sessions (notes datées, dans l'ordre chronologique).
Terminologie ancienne conservée telle quelle dans les entrées ci-dessous : l'outil a démarré sur
des "quatuors" de 4 primaires (CMYW/RYBW), avant de passer en "trios" de 3 primaires une fois
vérifié que l'AMS ne mélange que 3 couleurs à la fois, pas 4 — voir le README pour l'état actuel.

---

## Fix : coins arrondis + marge (barre preview "toujours ultra moche", capture d'écran à l'appui), 23/10/2026

Tomyn, capture d'écran envoyée après le fix du défilé continu : "c'est toujours ultra moche".
Cette fois la capture montre clairement le vrai problème restant : une bande **rectangulaire**,
collée **pile** contre le bas de la vignette, sans le moindre espace - alors que
`$overlayProgression` (voir sa capture envoyée plus tôt) est une carte visiblement **flottante**,
avec des coins arrondis et de l'air tout autour.

Deux correctifs concrets :
- Coins arrondis sur la carte via une `Region` GDI+ (nouvelle fonction `Definir-RegionArrondie`,
  rayon 8px) - un simple `FormBorderStyle=None` ne les donne pas automatiquement sur ce type de
  petite fenêtre (confirmé par la capture : coins bien carrés).
- 4px d'espace vertical entre le bas de la vignette et le haut de la carte (au lieu d'être collée
  dessus), et la carte elle-même agrandie (34 → 40px de haut, marges internes 4 → 8px) pour
  respirer un peu plus, plus proche des proportions de `$overlayProgression`.

Non vérifié visuellement (toujours pas de GDI+ sous Linux ici) - à tester par Tomyn.

---

## Fix : remplacement du rebond par un défilé continu (barre preview "toujours ultra moche"), 23/10/2026

Tomyn, une fois le blocage corrigé : "c'est bon mais elle est toujours ultra moche". Le va-et-vient
fonctionnait désormais correctement, mais un rebond linéaire (vitesse constante, arrêt net puis
repart brutalement en sens inverse à chaque bord) reste un effet visuel grossier en lui-même,
carte ou pas - ce n'est tout simplement pas comme ça qu'une barre de chargement a l'air pro.

Remplacé par un défilé continu, type tapis roulant : le bloc glisse toujours dans le même sens,
sort par le bord droit de la piste, puis réapparaît hors-cadre à gauche et glisse à nouveau - plus
jamais d'arrêt ni de changement de sens brutal. C'est l'effet classique d'une barre de chargement
indéterminée (le même principe que le style natif "Marquee" essayé plus tôt, mais en gardant les
couleurs et la carte de la marque). Plus besoin de variable de direction du tout - code simplifié
d'autant.

Non vérifié visuellement (toujours pas de GDI+ sous Linux ici) - à tester par Tomyn.

---

## Fix (confirmé par test direct) : vrai bug de fond du va-et-vient - scalaire qui ne survit pas à travers Add_Tick/GetNewClosure, 23/10/2026

Tomyn, capture d'écran à l'appui : "toujours aussi moche se rempli en quelques seconde et stagne" -
le bloc orange est bien flush contre le bord droit de la piste, immobile, pendant que le titre
affiche toujours "Chargement de l'aperçu...".

Cette fois testé DIRECTEMENT en PowerShell (pas une hypothèse de plus) : un scriptblock
`.GetNewClosure()` invoqué plusieurs fois de suite (comme le fait `Add_Tick` à chaque tic du
`Timer`) NE PERSISTE PAS les réassignations faites à une variable scalaire simple à l'intérieur
de son propre corps - chaque appel repart de la valeur capturée à l'origine, la réassignation est
jetée à la fin de l'appel. Confirmé par un test minimal : une boucle de 60 appels avec
`$left = $left + 10` reste bloquée à `10` pour toujours, au lieu d'accumuler. Exactement la même
famille de piège que le bug `$script:` déjà documenté plus haut dans ce fichier (section "PAS de
`.GetNewClosure()` ici"), sauf que celui-ci touche une variable locale, pas une variable de script.

C'est très exactement ce qui causait le blocage : `$directionBarre` (scalaire, réassigné à `1` ou
`-1` à l'intérieur du `Add_Tick`) revenait TOUJOURS à sa valeur capturée (`1`) au tic suivant. La
barre avance donc toujours vers la droite, se cogne contre le bord, le `-1` est jeté, et au tic
d'après elle recalcule exactement la même position butée contre le bord - immobile pour de bon,
pas juste "moche". C'est aussi, très probablement, la vraie explication du tout premier signalement
("se fini tres vite") que j'avais mal diagnostiqué comme un problème purement esthétique : la barre
ne finissait pas sa course vite, elle restait bloquée après une seule course.

Un tableau à 1 élément (type référence - on mute l'ÉLÉMENT, jamais la variable elle-même) confirmé
par le même test comme survivant correctement à travers les tics. `$directionBarre = @(1)`, lu/écrit
partout via `$directionBarre[0]`, dans les deux fonctions (`Mettre-A-Jour-Apercu` et
`Redessiner-Apercu-AvecRotation`). `$remplissageApercu.Left` n'avait pas ce problème : c'est une
PROPRIÉTÉ d'un vrai contrôle WinForms (objet, pas scalaire), qui se lit/écrit correctement sur
l'objet réel à chaque tic.

---

## Fix : la barre de progression preview reprend la vraie carte de $overlayProgression, 23/10/2026

Tomyn, après le passage au `ProgressBar` natif en `Style="Marquee"` de l'entrée précédente :
"elle est toujours ultra moche pkps prendre la même barre que celle de la prod".

Le vrai problème n'était ni la couleur ni le type d'animation : `$overlayProgression` (la fenêtre
du mélange, jolie) est une **petite carte** - fond violet (`$THEME.FondBanniere`), titre, piste
sombre + remplissage orange, avec des marges - alors que la barre preview, dans les deux versions
précédentes (Panel puis ProgressBar), était une simple bande collée brute sous l'image, sans
carte, sans titre, sans marge. `ProgressBar` en `Style="Marquee"` a en plus un défaut supplémentaire
: ce style ignore largement `BackColor`/`ForeColor` sur Windows (rendu par les styles visuels
natifs), donc la couleur orange de la marque ne s'appliquait probablement même pas - rendu bleu/gris
générique Windows au lieu des couleurs de l'appli.

Nouvelle fonction `Creer-CarteProgressionApercu` qui reconstruit la même structure que
`$overlayProgression` (sans les boutons Pause/Annuler, pas d'action possible pendant un calcul
d'aperçu) : carte 34px de haut, titre "Chargement de l'aperçu...", piste sombre + remplissage
orange avec marges de 4px. Toujours pas de vraie progression chiffrée disponible depuis le
runspace (voir les notes plus anciennes), donc le remplissage reste animé en va-et-vient - mais
cette fois dans une carte qui ressemble vraiment à celle de la prod, pas une bande nue.

Non vérifié visuellement (toujours pas de GDI+ sous Linux ici) - à tester par Tomyn.

---

## Fix : remplacement du remplissage "va-et-vient" fait à la main par un vrai ProgressBar Windows, 23/10/2026

Tomyn, après le fix `MinimumSize` : "la barre se ferme pas elle se rempli trop vite et se ferme
quand le chargement est ok mais elle se rempli en quelques secondes et elle est ultra moche pas
comme la barre de progression prod qui elle est jolie". Donc : pas de fermeture prématurée (la
question laissée ouverte dans l'entrée précédente ne se posait pas - elle ferme bien quand le
calcul est fini), le problème est purement visuel.

Cause : le remplissage était un `Panel` animé à la main, 10px tous les 200ms dans une piste de
300px - ça atteint un bout de la piste en 4,8s puis reste visuellement figé jusqu'à la vraie fin
du calcul (qui peut prendre 2-3 minutes). Un bloc qui bouge un peu puis se fige, avec un rendu de
rectangle brut, donne effectivement une impression "ultra moche" comparée à la barre de
progression du mélange (`$overlayProgression`), qui elle est un vrai contrôle animé par Windows.

Remplacé par un vrai `System.Windows.Forms.ProgressBar` en `Style = "Marquee"` (le style NATIF
conçu exactement pour une progression de durée inconnue) sur toute la largeur de l'aperçu, avec
`MarqueeAnimationSpeed = 30`. Windows anime le défilé en continu tout seul, aucun calcul de
position à la main n'est plus nécessaire - tout le code `$directionBarre`/`$pas`/`.Left` et le
diagnostic qui avait servi à localiser les deux bugs précédents (clé d'interpolation, taille
39px) ont été retirés : les deux faits qu'il avait établis sont maintenant corrigés et confirmés,
il ne faisait plus que remplir le journal.

Non vérifié visuellement (toujours pas de GDI+ sous Linux ici) - à tester par Tomyn.

---

## Fix : "ultra moche" (taille 300x39 au lieu de 300x6) - question encore ouverte sur une fermeture trop tôt, 23/10/2026

Le diagnostic a payé une 2e fois, mais partiellement. Un premier journal envoyé par Tomyn (chargement
de 84,2s, fichier avec angle déjà en cache) montrait 388 lignes DIAGNOSTIC, Visible=True sur toute la
durée, jusqu'à la dernière ligne juste avant "Apercu : lecture... dessin...". Ce journal-là ne
montrait donc PAS de fermeture prématurée.

Juste après, Tomyn signale : "elle se ferme en quelques secondes alors que le preview se charge en
environ 2-3 minutes" - sur un chargement visiblement différent (beaucoup plus long, probablement un
fichier sans angle en cache cette fois). Les deux retours ne se contredisent pas forcément (deux
fichiers/situations différentes), mais la question d'une fermeture trop tôt reste OUVERTE pour ce
cas précis - pas encore de diagnostic sur CE chargement-là.

Le diagnostic révèle en revanche, de façon solide (confirmé sur le premier journal), la vraie cause
de "ultra moche" : **taille réelle 300x39**, alors que 300x6 avait été demandé. Même avec
`FormBorderStyle=None`, Windows impose une hauteur MINIMALE de fenêtre (~39px, la hauteur minimale
système classique) tant que `MinimumSize` n'est pas explicitement mise à (0,0) - d'où un gros bloc
épais sombre avec le petit filet orange de 6px perdu dans un coin, au lieu d'une fine bande nette.
`MinimumSize` mise à (0,0) avant `Size` sur les deux fenêtres-overlay - devrait donner la vraie bande
fine de 6px attendue.

Diagnostic laissé actif - besoin du journal complet du chargement de 2-3 minutes qui se ferme trop
tôt pour trancher cette question séparément.

---

## Fix (confirmé par test direct) : vraie cause de la barre invisible - bug d'interpolation PowerShell, 23/10/2026

Le diagnostic inconditionnel a payé immédiatement : `overlayApercu = NULL`, alors que la clé
`__ProgressOverlay_avant__` apparaissait bien, telle quelle, dans la liste des clés du hashtable
juste à côté. La clé existe, mais la LECTURE ne la trouve pas - ça ne pouvait être qu'un problème
de construction de la chaîne de recherche elle-même.

Cause, confirmée par test direct dans cet environnement :

    $cle = "avant"
    "__ProgressOverlay_$cle__"   -> "__ProgressOverlay_"          (FAUX)
    "__ProgressOverlay_${cle}__" -> "__ProgressOverlay_avant__"   (correct)

En PowerShell, `_` fait partie des caractères valides d'un nom de variable - dans une chaîne
interpolée, `$cle__` est donc lu comme UNE SEULE variable nommée `cle__` (inexistante, donc vide),
pas comme `$cle` suivi du texte littéral `__`. Repéré ce bug dans TOUT le fichier : 14 occurrences
du même piège (`"__PSActif_$cle__"`, `"__BoutonStop_$cle__"`, `"__Label_$cle__"`,
`"__ProgressOverlay_$cle__"`, `"__ProgressRemplissage_$cle__"`), présent depuis bien avant cette
session (le bouton Stop et le label d'angle du 10/10/2026 l'avaient déjà) - ce qui explique
D'AUTRES symptômes jamais identifiés comme liés jusqu'ici : la capture d'écran envoyée par Tomyn
montrait "Rotation : -- / Inclinaison : --" alors que le journal, juste à côté, affichait bien
"rotation 315 deg" - le label ne s'est simplement jamais mis à jour, exactement par ce bug
(`$labelAngle = $etatPartage["__Label_$cle__"]` ne trouvait jamais le contrôle).

Toutes les 14 occurrences remplacées par `${cle}__` (accolades autour du nom de variable, syntaxe
PowerShell standard pour ce cas). Recherche systématique du même motif sur tout le fichier
(`$cle__` et toute variante `$xxx__`) : plus aucune occurrence restante après correction.

---

## Diagnostic v2 : le premier diagnostic était lui-même invisible, 23/10/2026

Tomyn a renvoyé le journal complet d'un chargement (52,7s de dessin, ~263 tics de minuteur) : AUCUNE
ligne "DIAGNOSTIC" dedans. Le premier diagnostic ajouté était imbriqué DANS le `if ($overlayApercu)`
— s'il ne s'affiche jamais, ça veut déjà dire quelque chose : `$overlayApercu` est `$null`.

Diagnostic rendu INCONDITIONNEL (hors du `if`, dès le début de la fonction, pas dans le minuteur) :
s'affiche à coup sûr, "TROUVE" ou "NULL" — et si NULL, liste TOUTES les clés réellement présentes
dans le hashtable partagé à ce moment-là, pour voir si la clé attendue est juste absente, mal
orthographiée, ou si c'est le hashtable entier qui n'est pas le bon.

---

## Diagnostic (plus une hypothèse à l'aveugle) : barre de progression, 23/10/2026

Tomyn : "toujours non visible" même après le fix sur l'ordre d'exécution (ShowDialog/Maximized).
4e échec d'affilée sur ce point précis, sans jamais pouvoir vérifier visuellement ici (GDI+
indisponible sous Linux) — continuer à deviner une 5e fois sans nouvelle information serait
malhonnête.

Deux choses cette fois :
1. Un vrai correctif, basé sur une différence concrète trouvée avec `$overlayProgression` (la
   fenêtre du mélange, qui elle fonctionne en prod) : `Afficher-OverlayProgression` appelle
   `[System.Windows.Forms.Application]::DoEvents()` juste après `.Show()`/`.BringToFront()`, ce
   que les fonctions d'aperçu ne faisaient PAS. Ajouté par précaution.
2. Un DIAGNOSTIC écrit dans le journal de l'appli (une seule fois par calcul, au premier tick) :
   position écran calculée, taille de la fenêtre-barre, son `.Visible` réel, la taille de la
   PictureBox, et les limites de l'écran principal. Si la barre reste invisible après ce commit,
   ces chiffres (visibles dans le journal en bas de l'appli, à copier-coller) permettront de savoir
   EXACTEMENT ce qui cloche (position hors écran ? coordonnées négatives ? Visible=False malgré le
   Show() ? écran secondaire ?) plutôt que de continuer à deviner dans le vide.

---

## Fix : vraie cause de la barre de progression invisible trouvée, 23/10/2026

Tomyn : "barre toujours non visible" même avec la fenêtre TopMost séparée (recette du mélange).
Cause trouvée cette fois, précise : pour le chargement automatique au démarrage (le seul cas que
Tomyn semble avoir testé — fichier rouvert tout seul à l'ouverture, "Rotation : -- / Inclinaison :
--" sur sa capture d'écran), `Mettre-A-Jour-Apercu` est appelée dans le script AVANT
`$form.ShowDialog()` et avant `$form.WindowState = "Maximized"`, qui n'arrivent que quelques
lignes plus loin. À ce moment précis, `PointToScreen()` sur la PictureBox renvoyait une position
calculée sur la fenêtre PAS ENCORE affichée/agrandie — une position qui ne correspond à rien une
fois la fenêtre réellement montrée et maximisée. La barre se dessinait bel et bien, juste au
mauvais endroit de l'écran : invisible pour Tomyn, mais pas pour une raison de z-order ou de type
de contrôle cette fois (les deux fausses pistes précédentes).

Fix : la position n'est plus calculée une seule fois au lancement du calcul, mais RECALCULÉE À
CHAQUE TICK du minuteur d'animation (toutes les 200ms). Au moment où le premier tick arrive, le
formulaire principal est de toute façon déjà affiché et maximisé, qu'il s'agisse du chargement
automatique ou d'un chargement manuel - corrige les deux cas sans distinction, et gère en prime un
déplacement de la fenêtre principale pendant un calcul.

Non vérifiable visuellement ici (GDI+ indisponible sous Linux) — mais cette fois le raisonnement
tient sur une cause concrète et vérifiable dans le code (ordre d'exécution des lignes), pas une
simple hypothèse de rendu.

---

## Fix (non vérifié visuellement) : barre de progression toujours invisible + flou persistant, 22/10/2026, soir

Tomyn, après le repositionnement de la barre et l'agrandissement orienté des triangles sous-pixel :
"barre de progression non visible [...] pourquoi tu fais pas cette barre comme la barre de
progression de quand on lance le mélange" + "c'est toujours aussi flou". Les deux essais précédents
sur ces deux points n'ont rien changé.

**Barre de progression** : suivant directement la remarque de Tomyn, abandon du Panel enfant du
formulaire principal (sa visibilité dépendait d'un empilement avec la PictureBox jamais vérifiable
ici, deux tentatives infructueuses). Reprise à l'identique de la recette de `$overlayProgression`
(la fenêtre affichée au lancement du mélange, déjà fiable en production) : une fenêtre Windows
TopMost séparée (`FormBorderStyle=None`), positionnée au moment de l'affichage juste sous la
PictureBox via `PointToScreen` (coordonnées écran, pas coordonnées du formulaire). Comme `.Show()`
active/donne le focus à cette nouvelle fenêtre par défaut, un `$pictureBox.Focus()` juste après la
rend immédiatement au PictureBox pour ne pas casser les raccourcis clavier (flèches de rotation).

**Flou** : 3 tentatives sur la FORME des triangles sous-pixel (carré, vraie géométrie, vraie
géométrie agrandie) sans amélioration perçue — piste différente, indépendante de cette forme :
l'aperçu était jusqu'ici calculé À LA TAILLE EXACTE d'affichage (300x260) puis montré 1 pour 1.
Calculé désormais à une résolution interne 2x plus grande dans chaque dimension (600x520), avec la
PictureBox (déjà en mode "Zoom") inchangée à l'affichage : elle réduit donc l'image avec
interpolation, un sur-échantillonnage classique qui lisse les bords indépendamment de la forme des
triangles sous-pixel — et qui, en prime, fait grimper la surface écran de beaucoup de ces triangles
au-dessus du seuil de 4 px² déjà en place, donc moins souvent approximés du tout. Appliqué
seulement au chargement initial/complet (`Mettre-A-Jour-Apercu`), pas à la rotation manuelle
(`Redessiner-Apercu-AvecRotation`, déjà réduite à moitié résolution pour rester réactive au clic).

**Important : non vérifiable visuellement dans cet environnement** (GDI+/System.Drawing
indisponible sous Linux) — à tester réellement.

---

## Fix (non vérifié visuellement) : escalier + flou toujours présents en même temps, 22/10/2026, soir

Tomyn, après le fix couleur : flou ET escalier toujours là ensemble sur l'aperçu. Diagnostic : les
petits carrés (axis-aligned, utilisés pour tout triangle sous-pixel) ne peuvent représenter une
arête diagonale qu'en marches, quelle que soit leur taille — l'anti-crénelage (AntiAlias) adoucit
seulement les bords de CES carrés, il ne leur redonne jamais la bonne orientation. D'où les deux
symptômes en même temps : l'escalier (forme carrée) ET le flou (bords du carré adoucis).

La tentative précédente de "vraie géométrie" (commit 571b397, revertée) avait la bonne
orientation mais pas assez d'opacité sur les triangles sous-pixel sous AntiAlias (couverture
partielle fidèle mais minime).

Nouvelle approche, jamais tentée avant : garder la VRAIE forme/orientation du triangle (ses 3
vrais sommets) mais l'agrandir autour de son propre centre jusqu'à une aire cible (~3,6 px², même
ordre de grandeur que le carré qu'elle remplace) pour une opacité pleine, puis la recentrer sur la
cellule revendiquée (même ancrage que le carré, pour ne pas réintroduire les "manques" déjà
corrigés). Une arête diagonale est ainsi approximée par une suite de petits triangles INCLINÉS qui
suivent sa vraie direction, pas par des carrés droits.

**Important : non vérifiable visuellement dans cet environnement** (GDI+/System.Drawing
indisponible sous Linux, seule la syntaxe a pu être contrôlée) — à tester réellement avant de
considérer ce point résolu.

---

## Fix (hypothèse) : barre de progression invisible, 22/10/2026, soir

Tomyn : "rien n'apparaît du tout" pour la barre de progression ajoutée plus haut, sur aucun des
deux aperçus. La bande chevauchait jusqu'ici les 5 derniers pixels DU BAS DE LA PictureBox
elle-même (même rectangle), ce qui la rendait dépendante de l'ordre d'empilement (z-order) entre
deux contrôles frères — un empilement que je ne peux pas vérifier visuellement ici non plus.

Repositionnée entièrement SOUS la PictureBox, dans l'interstice de 4px déjà existant avant le
label d'angle (hauteur réduite à 3px pour y tenir sans jamais toucher le rectangle de la
PictureBox) : plus aucun chevauchement, donc plus aucune dépendance à un empilement non
vérifiable. Aucun autre changement dans la logique d'affichage/animation/masquage.

---

## Fix : couleur violette systématique sur l'aperçu "avant", 22/10/2026, soir

Tomyn : "les couleurs de la previews avant ne s'occupe pas du tout les couleurs [...] j'ai beau
prendre n'importe quel fichier il est toujours avec ce violet [...] il ne prend pas les couleurs
du fichier d'origine". Confirmé que Bambu Studio affiche les bonnes couleurs sur le même fichier -
donc pas un problème de données, un problème de lecture côté Mélangeur.

Cause trouvée et confirmée par test direct (pas une hypothèse) : `[System.Drawing.ColorTranslator]
::FromHtml()` ne gère PAS les hex 8 chiffres `#RRGGBBAA`. Test exécuté dans cette session :
`FromHtml("#FF5733FF")` renvoie R=87 G=51 B=255 au lieu de R=255 G=87 B=51 - il ignore les 2
premiers caractères et relit les 6 derniers comme RRGGBB, donc le "FF" d'opacité en fin de chaîne
devient le canal BLEU. Coloriser-STL (l'outil qui écrit ces .3mf) ajoute systématiquement "FF"
(opacité pleine) en suffixe 8 chiffres sur chaque `filament_colour` - confirmé en lisant son code
source. Résultat : bleu/violet forcé au maximum sur absolument toutes les couleurs de tous les
fichiers, peu importe le fichier - exactement le symptôme décrit.

Important : ce bug touche uniquement les chemins d'AFFICHAGE (aperçu 3D, pastilles de couleur,
sélecteurs, dialogues couleur - 17 endroits au total dans ce fichier). Le calcul du dosage/mélange
lui-même (`Obtenir-RGBDepuisHex`) utilise un découpage de sous-chaînes différent, déjà correct, et
n'a jamais été affecté : les proportions de mélange calculées étaient toujours bonnes, seul
l'affichage était faux.

Fix : nouvelle fonction `Convertir-HexEnCouleurGdi` qui découpe R/G/B manuellement par position
(comme `Obtenir-RGBDepuisHex`) au lieu de passer par `ColorTranslator.FromHtml`, et ignore tout
ce qui suit les 6 premiers chiffres hex. Remplace les 17 appels `ColorTranslator::FromHtml` du
fichier. Injectée dans les 3 Runspaces d'arrière-plan qui en ont besoin (génération d'aperçu et
de vignettes tournent dans des Runspaces séparés qui ne connaissent aucune fonction du script
principal sauf celles explicitement injectées).

Sans rapport avec la saga flou/escalier/nuage de points (grain, anti-aliasing, carrés) traitée
juste avant - bug totalement différent, sur un chemin de code différent.

---

## Ajout : barre de progression sur les aperçus, 22/10/2026, soir

Tomyn : "il faudrait une barre de progression de génération previews pour que l'utilisateur lambda
ne pense pas que l'application est bloqué". Un calcul d'aperçu prend couramment 20-60s sur un gros
maillage, et rien ne le montrait à l'écran avant (seul le journal en bas, facile à ne pas
remarquer).

Pas de vraie progression chiffrée possible : le calcul en arrière-plan (`Nouvelle-ImageApercu`,
dans un Runspace séparé) ne remonte aucun avancement intermédiaire pendant qu'il tourne. Une fine
bande **indéterminée** (va-et-vient, même principe visuel que la barre de l'écran de lancement :
piste violette sombre + remplissage orange) superposée au bas de chaque case d'aperçu suffit à
montrer "ça travaille", sans faire croire à une estimation précise qu'on n'a pas.

Affichée au lancement du calcul, animée à chaque tick du minuteur déjà existant (pas de second
Timer), masquée à la fin (succès ou échec) - sur le chargement initial (`Mettre-A-Jour-Apercu`) ET
la rotation manuelle/Auto (`Redessiner-Apercu-AvecRotation`).

---

## Annulé : retour à la vraie géométrie - régression confirmée ("pire qu'avant"), 22/10/2026, soir

Le passage au dessin systématique de la vraie géométrie du triangle (voir entrée annulée
ci-dessous) a été testé par Tomyn : "et pour le preview cest pire quavant" - capture d'écran à
l'appui, une forme très pâle/délavée, presque un fil de fer, bien pire que les versions
précédentes.

**Explication** : sur un maillage aussi dense, un triangle sous-pixel ne couvre souvent qu'une
toute petite fraction d'un pixel d'écran. Sous anticrénelage, GDI+ rend cette couverture
fidèlement - partielle, donc une opacité faible - au lieu de forcer le pixel plein comme le
faisait (par construction) le carré de secours, volontairement surdimensionné (1,9 px) pour
garantir une couverture pleine. Le carré n'était donc pas qu'un contournement pour la
rasterisation : il compensait aussi, par sa taille, la trop faible surface réelle des triangles
sous-pixel pris individuellement. Sans lui, même avec la sélection multi-cellule (qui garantit
qu'une cellule a toujours un représentant, mais pas que ce représentant couvre toute la cellule),
le rendu devient clairsemé et pâle.

**Correctif** : retour au carré de secours pour les triangles sous-pixel (`git revert` du
changement), `AntiAlias` conservé (voir entrée ci-dessous, inchangée par ailleurs). Le vrai
problème "escalier" reste donc non résolu à ce stade - prochaine piste à explorer : garder les
carrés (coverage garantie) mais avec l'anticrénelage actif dessus, ce qui devrait au moins adoucir
visuellement les marches sans revenir au rendu délavé.

---

## Correctif : "flou" identifié - aliasing, pas du flou (AntiAlias réactivé), 22/10/2026, soir

Tomyn précise enfin concrètement : "les lignes qui devraient être droites sont en escalier". Ce
n'est pas du flou au sens propre, c'est de l'**aliasing** - des bords en marches d'escalier au lieu
de lignes nettes - exactement ce que produit `SmoothingMode.HighSpeed` par conception (il
désactive l'anticrénelage). Aucun des correctifs précédents (grain, trous, AutoScaleMode) ne
pouvait avoir d'effet là-dessus, aucun ne touchait à ce réglage.

Le `HighSpeed` avait été choisi le 10/10/2026 car l'anticrénelage était jugé "ultra long" - mais ce
chronométrage datait d'**avant** le regroupement par couleur en un seul `FillPath` par teinte
(optimisation du même jour, plus bas dans le fichier) : à l'époque c'était un `FillPolygon`
individuel par triangle (centaines de milliers d'appels), où le coût par-appel de l'anticrénelage
devenait effectivement énorme. Aujourd'hui le dessin final ne fait plus qu'une poignée de
`FillPath` (un par teinte distincte, ~100-200 sur un fichier typique) - la structure de coût qui
justifiait `HighSpeed` à l'époque n'existe plus : l'anticrénelage ne coûte plus qu'une fois par
groupe, pas par triangle.

**Correctif** : `SmoothingMode.AntiAlias` à la place de `HighSpeed`. Pas de test visuel possible
dans cet environnement (`System.Drawing` indisponible sous Linux) ni de mesure de temps réelle - à
confirmer par Tomyn, sur le rendu ET sur le temps de calcul.

---

## Hypothèse : flou direct (AutoScaleMode WinForms), 22/10/2026, soir

Retour de Tomyn, clarifié via deux questions ciblées : le violet dominant est bien la vraie couleur
du fichier (pas un bug), mais le flou est visible **directement, sans zoomer**. Important : les
deux correctifs précédents (grain, trous) n'ont jamais eu d'effet sur ce flou précis, alors qu'ils
changent clairement le rendu pixel par pixel sur les captures reçues - signal fort que le flou
n'est PAS un problème de dessin.

**Piste** : `$pictureApres`/`$pictureAvant` (SizeMode "Zoom") ont une taille de contrôle fixée
exactement à 300x260, identique à l'image dessinée dedans - en théorie zéro étirement. Mais
`AutoScaleMode` de WinForms (mise à l'échelle basée sur la police, mécanisme différent et
indépendant du DPI-aware déjà réglé le 12/10/2026) peut re-dimensionner Size/Location de TOUS les
contrôles au chargement si l'environnement differe de la ligne de base implicite - dans ce cas la
PictureBox ne ferait plus exactement 300x260 à l'exécution, et "Zoom" étirerait alors réellement
l'image avec interpolation, d'où un flou direct sans rapport avec l'algorithme de dessin.

**Correctif** : `$form.AutoScaleMode = None` juste après la création du formulaire, pour garantir
que chaque contrôle garde exactement la taille en pixels fixée dans le code. Hypothèse, pas
confirmée visuellement (`System.Drawing` indisponible sous Linux) - à vérifier par Tomyn. Si ça ne
change rien, le flou vient d'ailleurs (peut-être inhérent à l'algorithme de dessin par petits
carrés quantifiés sur une image aussi petite) et il faudra une piste différente.

---

## Correctif : nuage de points - trous ponctuels (revendication multi-cellule), 22/10/2026, soir

Retour de Tomyn après capture d'écran zoomée : "c'est très moche, il y a des manques, c'est très
flou". Les "manques" sont des pixels isolés où le fond gris perce, au milieu d'une zone par
ailleurs bien couverte - pas une zone entière vide.

**Cause réelle** : la garantie "par construction" du 3e correctif (sélection par grille) ne
couvrait que la cellule du **centre projeté** de chaque triangle. Un triangle sous-pixel dont le
centre tombe en cellule A peut très bien avoir un sommet qui déborde en cellule B voisine, sans
qu'aucun AUTRE triangle du maillage n'ait jamais son propre centre dans B - B reste alors
totalement vide, même en plein milieu de la silhouette. Fréquent sur ce maillage (sortie Tripo très
dense, triangles plus petits qu'une cellule d'écran).

**Correctif** : chaque triangle sous-pixel revendique désormais ses 4 cellules candidates (centre
projeté + ses 3 sommets), pas seulement celle de son centre - comble ces trous ponctuels. Un
chemin rapide (1 seule revendication) reste utilisé dès que les 3 sommets et le centre tombent
dans la même cellule, pour ne pas payer ce coût sur l'immense majorité des triangles qui ne
débordent pas. Par la même occasion, chaque carré est maintenant centré sur le **centre de la
cellule qu'il représente** (et non plus sur la position réelle, parfois excentrée, du triangle
représentant) - garantit que cette cellule précise est toujours entièrement couverte. Validé par
un test synthétique (triangle débordant volontairement sur une cellule voisine vide) - toujours
pas de test visuel possible dans cet environnement (`System.Drawing` indisponible sous Linux) - à
confirmer par Tomyn, y compris sur le temps de calcul (coût en légère hausse sur les triangles à
cheval entre deux cellules).

---

## Correctif : nuage de points - grain résiduel (ombrage moyenné par cellule), 22/10/2026, soir

Confirmé par Tomyn ("peux mieux faire") : le polish 0,95 n'a pas réglé le grain - forme et
chevauchement sont bons (FillMode Winding, correctif précédent), mais la texture reste
granuleuse/sablée sur toute la surface, pas seulement en bordure.

**Cause réelle** : la sélection par grille (un seul triangle "représentant" par cellule d'écran)
choisit bien QUEL triangle dessiner, mais utilise directement l'ombrage (`$ombre`) de CE triangle
précis pour la couleur finale. Sur un maillage dense et bruité (sortie Tripo - normales par face
très variables même sur une zone localement plate), deux cellules voisines peuvent tomber sur deux
triangles dont l'ombrage diffère nettement par pur bruit de géométrie, même si la zone est
visuellement plate - d'où le grain, indépendant du FillMode (déjà corrigé) et de la taille des
carrés (qui ne peut rien faire contre un bruit de COULEUR, seulement contre un trou de
GÉOMÉTRIE).

**Correctif** : au lieu de l'ombrage du seul triangle représentant, on calcule la MOYENNE
d'ombrage de TOUS les triangles qui tombent dans une même cellule (accumulée en même temps que la
sélection, sans repasser sur le maillage) et c'est cette moyenne qui sert à quantifier la couleur
finale - lisse le bruit sans toucher à la géométrie ni au FillMode. Pas de test visuel possible
dans cet environnement (`System.Drawing` indisponible sur ce conteneur Linux) - à confirmer par
Tomyn.

---

## Ajustement : nuage de points - polish final (22/10/2026, soir)

Confirmé par Tomyn ("peut mieux faire") : le correctif FillMode (voir entrée ci-dessous) a réglé
le fond du problème - forme et ombrage nettement visibles, plus de nuage de points - reste un
grain résiduel sur les zones claires/en bordure. Léger coup de pouce : `$DEMI_TAILLE_CARRE` 0,7 →
0,95 (carrés de 1,9 px, 0,9 px de chevauchement) pour lisser ce grain, maintenant que le
chevauchement fusionne correctement. À confirmer par Tomyn.

---

## Correctif : nuage de points - vraie cause enfin trouvée (FillMode), 22/10/2026 soir

Les deux augmentations de taille de carré (1,6 → 2,6 → 4,4 px) changeaient à peine le rendu
("toujour pas ca") - signal qui aurait dû alerter plus tôt : si agrandir un carré qui se chevauche
de plus en plus avec ses voisins ne change presque rien, le problème n'est probablement pas la
taille.

**Cause réelle** : `GraphicsPath` utilise par défaut la règle de remplissage `Alternate`
(pair-impair). Dès que deux formes du même chemin se chevauchent (systématique ici, avec des
carrés voisins espacés d'environ 1 px et des côtés de plusieurs pixels), la zone de chevauchement
est comptée deux fois - donc paire - donc **non remplie** par cette règle. Plus les carrés
grossissaient, plus il y avait de zones de chevauchement ainsi "annulées", ce qui explique le
quasi-statu-quo malgré les augmentations successives : le vrai bug sabordait précisément le
mécanisme censé corriger le problème.

**Correctif** : `FillMode = Winding` (règle du nombre d'enroulement non nul) sur chaque
`GraphicsPath` de groupe - les formes qui se chevauchent fusionnent au lieu de s'annuler, du
moment qu'elles tournent dans le même sens (le cas ici, `AddRectangle` construit toujours ses
sommets dans le même ordre). Taille des carrés ramenée à une valeur raisonnable (1,4 px, 0,4 px de
chevauchement) maintenant que le chevauchement fonctionne enfin comme prévu - plus besoin du flou
des tailles précédentes qui tentaient (en vain) de compenser le vrai bug.

Toujours pas de rendu Windows possible depuis cette session Linux pour vérifier visuellement -
**à confirmer par Tomyn**, mais cette fois le diagnostic touche un mécanisme de rendu connu et
bien documenté (règle de remplissage pair-impair vs nombre d'enroulement), pas une hypothèse sur
le comportement non observable de la rasterisation.

---

## Ajustement : nuage de points - 2e augmentation, saut plus large (22/10/2026, soir)

1,3 (carrés 2,6 px) confirmé par Tomyn "nettement mieux" mais encore "pas encore ça" - texture
toujours grainy au lieu d'un remplissage lisse. Les deux ajustements précédents avançaient par
petits pas (+0,5) ; passage à un saut plus large cette fois pour converger plus vite :
`$DEMI_TAILLE_CARRE` 1,3 → 2,2 (carrés de 4,4 px, 3,4 px de chevauchement avec les cellules
voisines). Seul changement, même logique. Compromis assumé : des carrés plus gros peuvent flouter
légèrement les bords fins, acceptable face à l'aspect "nuage de points". À confirmer par Tomyn.

---

## Ajustement : nuage de points - taille des carrés augmentée (22/10/2026, soir)

Confirmé par Tomyn ("c'est mieux mais c'est pas encore ça") : le diagnostic de la 4e tentative
était le bon (la silhouette est désormais nettement visible, contrairement aux 3 tentatives
précédentes), mais le chevauchement entre carrés voisins (0,6 px, pour des carrés de 1,6 px)
restait insuffisant pour fusionner complètement les points en zones pleines. Seul changement :
`$DEMI_TAILLE_CARRE` passe de 0,8 à 1,3 (carrés de 2,6 px, soit 1,6 px de chevauchement avec les
cellules voisines, espacées de 1 px) - aucune autre logique touchée. Toujours à confirmer
visuellement par Tomyn.

---

## Correctif : bug "nuage de points" - 4e tentative, rasterisation garantie (22/10/2026, soir)

La 3e tentative (sélection par grille d'écran, voir entrée ci-dessous) - vérifiée mathématiquement
avant envoi (100% de couverture sur un test simulé) - était **toujours pas mieux** en pratique
("cesta pas mieux"), confirmé par capture d'écran réelle. Mais le log de cette capture est
révélateur : `32021 dessines` sur 1 472 326 triangles, un chiffre proche de la couverture pixel
attendue de la silhouette (donc la SÉLECTION fonctionnait comme prévu, cette fois) - le problème
n'était donc plus "quels triangles choisir" mais "comment ils se dessinent une fois choisis".

**Cause réelle** : les triangles sélectionnés sont toujours dessinés avec leur vraie géométrie
(`AddPolygon`, 3 vrais sommets) - or sur un maillage aussi dense, l'immense majorité d'entre eux
sont plus PETITS qu'un pixel d'écran (c'est tout l'historique du seuil d'aire, plus haut dans ce
fichier, dès le 10/10/2026). GDI+ sans anticrénelage (`SmoothingMode.HighSpeed`, activé pour la
vitesse) ne garantit pas qu'une forme plus petite qu'un pixel soit rasterisée sur le pixel attendu,
même si son centre est dans la bonne cellule - selon la position fractionnaire exacte de ses
sommets, elle peut ne peindre AUCUN pixel ou un pixel voisin, indépendamment d'une sélection par
ailleurs correcte. D'où un nuage de points malgré une couverture "logique" de 100%.

**Correctif** : un triangle déjà assez grand à l'écran (≥ 4 px², fiable à rasteriser) garde sa
vraie géométrie, pour un rendu fidèle sur les grandes zones plates. Un triangle sous-pixel (le cas
qui posait problème) est désormais dessiné comme un petit **carré de taille fixe** (1,6×1,6 px,
centré sur son point projeté) au lieu de son polygone réel - rasterisation garantie quelle que soit
sa taille d'origine, et un léger chevauchement (0,6 px) avec les cellules voisines pour éviter tout
interstice visible entre deux points adjacents.

**Limite assumée** : contrairement aux tentatives précédentes, celle-ci ne peut pas être validée
par un test purement mathématique (la garantie dépend du comportement réel de rasterisation de
GDI+, indisponible sous Linux - `System.Drawing` lève une exception à l'instanciation ici,
vérifié). Le raisonnement (un carré de 1,6 px ne peut pas "rater" son pixel, contrairement à un
triangle sous-pixel dont la position fractionnaire est imprévisible) est solide, mais **reste à
confirmer par Tomyn** - si toujours insuffisant, le paramètre à ajuster est `$DEMI_TAILLE_CARRE`
(actuellement 0,8, soit des carrés de 1,6 px) : l'augmenter légèrement comblerait plus largement
les interstices, au prix d'un rendu un peu moins net sur les détails fins.

---

## Correctif : bug "nuage de points" - 3e tentative, approche par grille d'écran (22/10/2026, soir)

La 2e tentative (sous-échantillonnage uniforme par index, voir entrée ci-dessous) était **encore
pire** - confirmé par capture d'écran réelle de Tomyn ("eug=h comment dire cest pire lol"), plus
épars que la 1ère tentative. En rouvrant un commentaire déjà présent dans le code (10/10/2026) :
un essai quasiment identique ("un triangle sur deux, au hasard") avait déjà été testé et **rejeté**
avant même la toute première version de cet outil, pour la même raison (trous visibles) - erreur
répétée faute d'avoir relu ce commentaire avant d'implémenter la 2e tentative.

**Cause racine, cette fois correctement identifiée** : aucun sous-échantillonnage par INDICE (par
aire écran OU uniforme) ne peut fonctionner, parce que l'ordre des indices (trié par profondeur Z
pour l'affichage peintre) n'a strictement aucun rapport avec la position 2D réelle à l'écran d'un
triangle - "un sur N" en index peut laisser des zones entières de l'image sans aucun représentant,
par pur hasard géométrique, quelle que soit la proportion conservée.

**Correctif (3e tentative)** : sélection par **grille de pixels d'écran** au lieu d'un critère
indirect. Chaque triangle est projeté à son centre, assigné à la cellule de grille (1 pixel
d'aperçu) correspondante, et un seul triangle "représentant" est gardé par cellule déjà occupée
(`HashSet` de clés de cellule). Résultat garanti **par construction**, pas par probabilité : tout
pixel que le maillage touche reste couvert, puisque le triangle retenu est ensuite dessiné avec sa
géométrie COMPLÈTE (3 vrais sommets, via `AddPolygon`/`FillPath` comme avant) et non comme un point
- un gros triangle plat remplit toujours toute sa vraie surface, pas juste 1 pixel. Bonus : le
coût de dessin est maintenant borné par la RÉSOLUTION de l'image (au plus largeur × hauteur
triangles dessinés), plus par la densité du maillage d'origine.

**Validé par un test réel avant envoi** (pas seulement une relecture de code, après deux échecs
d'affilée) : simulation d'un disque dense de 1,4 million de points aléatoires projetés sur une
image 300×260 - vérifié que les 29 837 pixels intérieurs de la silhouette simulée sont TOUS
couverts après dédoublonnage par grille (100%, zéro trou), avec seulement 31 739 triangles
représentants retenus (moins que les ~105-112k des tentatives précédentes - donc plus rapide
aussi, pas seulement plus correct). Toujours pas de rendu Windows réel possible depuis cette
session Linux - **à confirmer par Tomyn sur son vrai fichier**, mais cette fois la garantie de
couverture est mathématique (démontrée sur le même ordre de grandeur de densité que son fichier
réel), pas une approximation statistique comme les deux tentatives précédentes.

---

## Correctif : bug "nuage de points" - 2e tentative, cause réelle trouvée (22/10/2026, soir)

Le 1er correctif du jour (plancher de 15% de triangles conservés, voir entrée ci-dessous) était
**insuffisant** - confirmé par capture d'écran réelle de Tomyn (aperçu toujours "très troué") sur
`IMG_0250_colorise...tripo_convert...3mf`. En y repensant : le problème n'était pas le NOMBRE de
triangles conservés, mais LESQUELS. Le seuil par aire écran favorise mécaniquement les zones
PLATES vues de face (grands triangles projetés) et élimine en priorité les zones de forte courbure
ou vues de profil (triangles mécaniquement petits à l'écran, même géométriquement normaux) - sur
un maillage dense, ça concentre les triangles conservés sur quelques zones plates et vide presque
tout le reste, donnant l'aspect "nuage de points" **quel que soit le nombre total conservé** (le
1er correctif en gardait pourtant 3x plus que l'original, sans effet visuel - la quantité n'était
pas le problème).

**Correctif réel** : remplacement du seuil par aire (sélection biaisée) par un sous-échantillonnage
UNIFORME (un triangle sur N, réparti sur l'ordre des indices d'origine) - garantit une couverture
homogène de TOUTE la surface quelle que soit sa courbure, au lieu d'une sélection concentrée sur
les zones plates. Le budget de triangles dessinés est calé sur le ratio triangles/pixel déjà
observé et accepté par Tomyn sur un maillage normal (Water_Weird : 111717 dessinés pour une image
300x260, soit ~1,43 triangle/pixel) - donc pas de régression de vitesse attendue par rapport au
comportement actuel sur les maillages normaux (vérifié : la formule reproduit quasi exactement ce
chiffre, 111540 contre 111717 réels, à 0,2% près). Testé sur données simulées : maillage normal
inchangé (toujours ~33% conservés, régulièrement), maillage Tripo dense passe à un échantillonnage
parfaitement régulier (1 triangle sur 13, soit ~7,7%, réparti uniformément au lieu d'être concentré).

**Toujours pas de rendu Windows possible depuis cette session Linux pour vérifier visuellement** -
cette 2e tentative est mieux fondée (corrige le vrai défaut : la sélection biaisée, pas juste la
quantité), mais reste **à confirmer par Tomyn**. Si encore insuffisant après ce correctif, le
budget de triangles (`$RATIO_TRIANGLES_PAR_PIXEL`, actuellement 1,43/pixel) est le paramètre à
augmenter - au prix d'un temps de dessin plus long.

---

## Améliorations du Mélangeur après le correctif de vitesse (22/10/2026)

Suite du correctif précédent (moteur C#) : Tomyn a signalé que l'appli "propose toujours le même
trio" quel que soit le fichier. Vérifié par un test réel (exécution directe de l'algorithme de
sélection sur les vrais chiffres loggés par Tomyn pour 4 fichiers) : **pas un bug** - 3 gagnants
différents sur 4 fichiers (`PINK + GOLD + BLACK`, `ORANGE + BEIGE + BLACK`, `BEIGE + BLACK +
Corail`), le trio `ORANGE + BEIGE + BLACK` gagnant simplement 2 fois sur 4 parce qu'il a
réellement le moins de couleurs mal rendues sur ces fichiers. Cause de la confusion identifiée : le
panneau "Avancement" liste les 124 candidats testés (triés), jamais le trio réellement appliqué -
cette info n'existait QUE dans la popup "Trio suggéré", jamais journalisée. Cinq améliorations
demandées par Tomyn suite à cette investigation :

1. **Trio réellement appliqué désormais journalisé.** `Ecrire-Journal` logge maintenant
   explicitement quel trio a été appliqué (`"Trio applique (meilleur de tes trios sauvegardes) :
   ..."`, et si une meilleure combinaison du stock personnel est acceptée, une seconde ligne le
   confirme). Un doute comme celui-ci se vérifie maintenant en 10 secondes dans l'historique.
2. **Précision du dosage - testé et borné pour rester sûr.** Un pas plus fin (5, 2) appliqué à TOUT
   le classement a été chronométré réellement : pas=5 multiplie par ~4 le pire cas (20 couleurs
   personnelles, 1140 combinaisons), pas=2 dépasse largement la minute - inacceptable, risque de
   recréer le problème de lenteur d'origine. À la place : un pas plus fin (2 au lieu de 10) est
   appliqué en UN seul appel supplémentaire, uniquement sur le trio déjà sélectionné (dont le choix
   reste décidé à pas=10, déjà vérifié exact) - affine juste le chiffre d'écart affiché/journalisé,
   sans aucun risque de changer quel trio est choisi.
3. **Recherche dans le stock personnel désormais systématique.** Avant, cette recherche ne se
   lançait que si le meilleur trio sauvegardé laissait au moins une couleur mal rendue. Avec le
   moteur rapide, elle est quasi gratuite (quelques secondes pour un stock normal) - elle se lance
   maintenant toujours (si le stock a au moins 3 couleurs), pour pouvoir trouver mieux même quand
   le trio sauvegardé est déjà correct.
4. **Popup "Trio suggéré" affiche maintenant le top 3**, pas seulement le gagnant - pour trancher
   soi-même entre deux trios proches plutôt que de toujours suivre la règle stricte de l'algo.
5. **Bug "nuage de points" sur les maillages denses (Tripo) corrigé.** Cause identifiée : le seuil
   de culling des petits triangles (nécessaire pour la vitesse) était mis à l'échelle de la TAILLE
   de l'image d'aperçu, mais pas de la DENSITÉ du maillage - sur un maillage très dense (1,4M
   triangles), chaque triangle est mécaniquement plus petit à l'écran pour couvrir la même surface,
   donc une bien plus grande proportion tombe sous le seuil. Vérifié sur un vrai log Tomyn : 37% de
   triangles dessinés sur un maillage normal (305k triangles) contre seulement 4,6% sur un maillage
   Tripo dense (1,4M triangles) - d'où l'aspect "nuage de points". Correctif : le seuil est
   maintenant borné pour garantir qu'au moins 15% des triangles survivent (plafonné à 250 000 dans
   l'absolu, pour garder un temps de dessin raisonnable), sans toucher au comportement existant sur
   les maillages normaux (déjà bien au-dessus de ce plancher, donc strictement inchangés). Testé
   avec des données simulées reproduisant les deux cas réels : maillage normal inchangé (37% →
   37%), maillage dense Tripo nettement amélioré (4,6% → 15%, soit ~3,3x plus de triangles
   dessinés). Pas de rendu Windows possible pour vérifier visuellement depuis cette session
   (`System.Drawing` n'existe pas sous Linux) - **à confirmer visuellement par Tomyn**, le seuil de
   15%/250 000 est ajustable si encore insuffisant.

---

## Correctif : "Suggérer un trio pour ce fichier..." prenait 20 à 30 minutes réelles (22/10/2026)

Tomyn : clic sur "Suggérer un trio pour ce fichier..." avec un .3mf issu du pipeline Tripo de
Coloriser-STL -> le Mélangeur se bloque, Windows marque la fenêtre "ne répond plus". Confirmé par
Tomyn comme NON reproductible avec des .3mf Meshy, seulement avec des .3mf Tripo. Enquête en
plusieurs étapes, chacune invalidée par un test réel avant de trouver la vraie cause :

1. **1er correctif (insuffisant)** : traité d'abord comme un problème de réactivité - triple
   boucle sur les combinaisons de couleurs personnelles tournant sur le thread UI sans aucun
   `[System.Windows.Forms.Application]::DoEvents()`, d'où le "ne répond plus" (fenêtre gelée, pas
   forcément un plantage). Corrigé en ajoutant un pompage régulier. Tomyn a testé en conditions
   réelles et objecté, à raison : *"ca fais au moin 10 minutes que jai cliquer sur le bouton et
   rien ne se passe meme si cet pas geler cest extreme,nt long et ca ca ne va pas"* - rendre la
   fenêtre réactive ne change rien au fait que le calcul lui-même met 10+ minutes à finir.
2. **2e correctif (insuffisant)** : passage grossier du pas de dosage (25 au lieu de 10, ~3x moins
   de dosages testés par couleur), avec un recalcul précis final sur le seul gagnant. Testé
   réellement (synthétique, n=30 couleurs -> 4060 combinaisons) : toujours plus de 4 minutes
   d'exécution même avec ce pas grossier. Preuve que la précision du dosage n'était pas le facteur
   dominant.
3. **Vraie cause trouvée** : `Filament-Mixer-Lerp` (le modèle de mélange de filaments, port du
   vrai modèle C++ de Bambu Studio `filament_mixer::lerp`) évalue un **polynôme à 330 termes à
   CHAQUE appel**, et cette fonction est appelée des centaines de milliers de fois pour une seule
   suggestion (une fois par dosage testé × par couleur du fichier × par trio/combinaison
   candidate) - ni le nombre de combinaisons ni le pas du dosage n'étaient le vrai goulot, c'est
   ce polynôme évalué en PowerShell interprété, répété des centaines de milliers de fois, qui
   dominait le temps réel. Tomyn a aussi précisé que le vrai stock concerné est les couleurs
   personnelles individuelles (~10 chez lui), pas les ~200 trios sauvegardés testés en premier
   (boucle linéaire, rapide en soi) - les deux boucles souffraient du même coût par appel.
4. **Correctif final (celui-ci)** : le même calcul (mêmes formules, même ordre d'opérations) est
   maintenant porté en **C# compilé** (chargé via `Add-Type` au démarrage), un code compilé
   exécutant ce genre de boucle numérique des dizaines à des centaines de fois plus vite qu'un
   script PowerShell interprété - et ce indépendamment de la version de PowerShell utilisée (le
   lanceur `Lancer-Melange-Couleurs.vbs` utilise `pwsh.exe` (PowerShell 7) automatiquement s'il est
   installé, sinon `powershell.exe` (5.1) comme avant - mais la compilation C# profite aux deux
   moteurs de façon comparable, donc ce n'est plus une dépendance critique). En cas d'échec de
   compilation (rare), retombe automatiquement sur l'ancien chemin PowerShell pur - aucun risque de
   casser l'appli chez quelqu'un où ça ne compilerait pas. En plus, le plafond de 18 "couleurs
   candidates" (introduit puis affiné dans ce même correctif pour les très gros stocks) n'est
   appliqué que si le stock dépasse 20 couleurs personnelles - en dessous de ce seuil (le cas de
   Tomyn), la recherche reste **exhaustive et garantie optimale**, aucun compromis.
   - Un bug a été trouvé et corrigé pendant la vérification : le cast `[int]` de PowerShell
     *arrondit* au plus proche, alors que le cast `(int)` de C# *tronque* - sans correction, ça
     produisait des écarts de 1 unité RGB sur certains mélanges. Corrigé avec `Convert.ToInt32`
     côté C#, et reconfirmé par un test numérique direct contre l'ancien code PowerShell (0 écart
     sur 500 couleurs et 200 mélanges aléatoires).
   - Un second bug a été trouvé : la réduction à 18 "couleurs candidates" pouvait, dans de rares
     cas, écarter une couleur qui s'avérait utile seulement EN COMBINAISON - produisant un trio
     objectivement moins bon qu'une recherche complète (repéré par un test de non-régression
     dédié, pas par Tomyn). Corrigé par le seuil de 20 couleurs décrit ci-dessus : la réduction ne
     s'applique plus du tout pour un stock de taille normale.
   - Mesuré (synthétique, scénario proche de celui de Tomyn - 200 trios sauvegardés + 10 couleurs
     personnelles, palette fichier à 16 couleurs) : environ 6 secondes au total avec le correctif,
     contre 4+ minutes déjà pour un cas bien plus petit avec le 2e correctif (pas=25) seul - et les
     20 à 30 minutes réelles signalées par Tomyn avant tout correctif.
   - Vérifié par comparaison numérique directe (le nouveau moteur C# donne un résultat identique,
     chiffre par chiffre, à l'ancien code PowerShell pur sur plusieurs dizaines de cas) et par
     comparaison contre une recherche brute-force complète (sans aucune optimisation) sur plusieurs
     scénarios - jamais de résultat moins bon.
   - `Obtenir-SuggestionsTriosDiversifiees` (bouton "Suggérer 5 trios différents...") a la même
     structure de boucle O(n³) sur les couleurs personnelles, non corrigée ici (pas le bouton
     remonté par Tomyn) - a surveiller si le même symptôme se reproduit sur ce bouton-là.
   - **Pas encore reconfirmé par Tomyn en conditions réelles sur sa machine.**

## Correctif (superseded, détail ci-dessus) : première tentative "ne répond plus" (22/10/2026)

Première analyse, traitée comme un problème de réactivité de fenêtre uniquement (pompage
`DoEvents`) - confirmée insuffisante par Tomyn en conditions réelles, voir le correctif complet
ci-dessus pour la vraie cause et le correctif final.

## Correctif : plantage silencieux sur un fichier qui n'est pas un vrai .3mf (21/10/2026)

Bug remonté par Tomyn en conditions réelles : en essayant d'utiliser "Suggérer un trio pour ce
fichier..." sur un `.obj` généré par Tripo (format de sortie Tripo, pas un `.3mf` — voir
Coloriser-STL), l'outil restait bloqué puis ne faisait plus rien, sans aucun message d'erreur.

- Cause trouvée : `Obtenir-CouleursFichier3MF` et `Obtenir-NombreCouleursDetectees` appelaient
  `ExtractToDirectory` **en dehors** de leur `try/catch` — sur un fichier qui n'est pas un ZIP
  valide (un `.obj` texte brut, un `.3mf` tronqué/corrompu, ou n'importe quel fichier mal
  renommé), l'exception ("Central Directory corrupt" / "End of Central Directory introuvable")
  remontait sans filet. Le bouton "Suggérer un trio pour ce fichier..." n'avait lui-même qu'un
  `try/finally`, **sans `catch`** — l'exception se perdait purement et simplement, d'où le
  plantage silencieux.
- Corrigé dans les deux fonctions : l'extraction est maintenant À L'INTÉRIEUR du `try`, traitée
  comme n'importe quel autre échec de lecture (retourne un résultat vide/0 plutôt que de
  planter) — le message déjà existant côté bouton ("pas un .3mf Bambu Studio avec des couleurs
  enregistrées ?") s'affiche alors normalement au lieu de rien du tout.
- Ajouté un vrai `catch` sur le bouton "Suggérer un trio pour ce fichier..." en plus (défense en
  profondeur, pour toute autre erreur imprévue dans ce bloc).
- Vérifié par analyse syntaxique PowerShell réelle (0 erreur) et par une exécution PowerShell
  réelle REPRODUISANT le bug exact (un vrai `.obj` Wavefront texte brut, un `.3mf` tronqué à 6
  octets, un fichier texte avec extension `.3mf`) : confirmé que l'ancien code plantait bien avec
  le même message que celui remonté par Tomyn, et que le code corrigé ne plante plus sur aucun
  des trois cas (6 assertions, plus 2 assertions de non-régression sur un vrai `.3mf` valide).

## Bouton "Tout appliquer" après la suggestion par dossier (21/10/2026, deuxième idée en passant)

Ferme la boucle ouverte par la fonctionnalité précédente : "Suggérer des trios pour un dossier..."
analysait et proposait, mais il fallait ensuite relancer "Lancer le lot" à la main, fichier par
fichier ou en regroupant soi-même ceux qui partagent la même suggestion.

- Nouveau bouton "Tout appliquer..." dans la fenêtre de résultats de la suggestion par dossier.
  Traite chaque fichier valide (hors échecs d'analyse) avec SA PROPRE combinaison suggérée — pas un
  seul trio choisi pour tout le lot comme le fait "Lot : un dossier..." (`Lancer-LotDepuisDossier`).
  Fonctionne aussi bien avec un trio déjà sauvegardé qu'avec une combinaison inédite non encore
  nommée (prévient si des combinaisons inédites seront utilisées sans être enregistrées).
- Nouvelle fonction `Traiter-LotAvecSuggestions`, volontairement séparée de `Traiter-LotDeFichiers`
  plutôt qu'une généralisation de celle-ci : cette dernière alimente `$script:dernierLotTrioMelange`
  pour "Relancer les échecs..." (un seul trio attendu) — avec un trio différent par fichier, cette
  mécanique de reprise n'a plus de sens telle quelle. Simplification assumée pour cette première
  version : pas de "Relancer les échecs..." sur ce chemin (pas demandé par Tomyn, facile à ajouter
  plus tard en mémorisant les couples fichier/trio si le besoin se confirme).
- Vérifié par analyse syntaxique PowerShell réelle du script entier (0 erreur) et par une exécution
  PowerShell réelle du filtrage et de l'assignation par-fichier (7 assertions, dont la vérification
  explicite qu'aucun fichier ne reçoit la combinaison d'un autre — bug classique de ce genre de
  refactor).

## Suggestion de trios pour tout un dossier d'un coup (21/10/2026)

Idée en passant proposée et validée par Tomyn ("2-4") : son collègue dessinateur lui envoie des
dossiers de 250 fichiers .3mf, chacun avec son propre personnage/sa propre palette — "Suggérer un
trio pour ce fichier..." un par un était exactement la friction à supprimer sur un lot de cette
taille.

- Nouveau bouton **"Suggérer des trios pour un dossier..."** (sous "Relancer les échecs...") :
  choisit un dossier, analyse tous les .3mf qu'il contient (même filtrage que "Lot : un dossier...",
  non récursif, `*_melange.3mf` exclus), et affiche pour chacun le trio déjà sauvegardé qui lui
  convient le mieux — ou, si aucun ne convient bien, la meilleure combinaison inédite trouvée dans
  le stock de couleurs individuelles ("Gérer mes couleurs..."). Même moteur de comparaison que le
  bouton fichier-par-fichier existant (le nombre de couleurs mal rendues gagne d'abord, l'écart Lab
  moyen ne départage qu'à égalité — même correctif que le bug du cyan "zappé" du 18/10).
- Bouton **"Sauvegarder les nouvelles combinaisons..."** dans la fenêtre de résultat : enregistre
  en un clic toutes les combinaisons inédites détectées, avec déduplication par ensemble de teintes
  — plusieurs personnages du même collègue partagent souvent la même palette, pas la peine de
  redemander un nom pour exactement la même combinaison plusieurs fois.
- Vérifié par exécution PowerShell réelle (17 assertions, avec de vrais fichiers .3mf fabriqués
  pour le test — zip réels contenant les couleurs Bambu Studio) : retrouve le bon trio existant,
  détecte une vraie combinaison inédite, capture proprement un fichier corrompu sans planter le
  reste du lot, déduplique deux palettes identiques. Toutes passent. Script entier revérifié sans
  erreur de syntaxe (`[System.Management.Automation.Language.Parser]::ParseFile`).

---

## Raccourcis clavier, vérif mise à jour, file d'attente de lots ("tu peux toutes les faire", 16/10/2026, deuxième série)

Trois nouveautés portées depuis Coloriser-STL (même raisonnement, même code dans l'esprit) ;
la quatrième idée proposée ce jour-là (graphique de consommation de crédits) ne s'applique pas
ici — Melange-Couleurs-3MF ne consomme aucun crédit d'API, c'est un calcul de dosage purement
local, contrairement à la colorisation via Meshy/Tripo :

1. **Raccourcis clavier** - `Ctrl+Entrée` lance le mélange du fichier courant (équivalent au
   bouton "Lancer"), `Échap` annule un lot en cours — fonctionne depuis la fenêtre principale et
   depuis l'overlay de progression (focus séparé pendant un lot).
2. **Vérification de mise à jour** - nouveau bouton "Verifier mise a jour" qui compare la date de
   cette copie locale à la date du dernier commit GitHub touchant ce fichier précis. Déclenché
   uniquement par le bouton, jamais automatiquement au démarrage.
3. **File d'attente de plusieurs lots** - depuis la fenêtre de confirmation d'un lot (celle qui
   liste les fichiers avec une case à cocher chacun), un nouveau bouton "Ajouter a la file" empile
   le lot (fichiers déjà filtrés + trio choisi) au lieu de le lancer tout de suite. "Lancer la file
   d'attente" (fenêtre principale) les enchaîne ensuite automatiquement l'un après l'autre.

## Pause/Reprendre, recherche dans l'historique, vérif espace disque, mode sombre ("tu peux toutes les faire", 16/10/2026)

Quatre nouveautés portées depuis Coloriser-STL (même raisonnement, même code dans l'esprit) :

1. **Pause/Reprendre sur un lot** - bouton sur l'overlay de progression, à côté d'Annuler. Le
   fichier en cours va à son terme, puis la boucle attend avant de passer au suivant.
2. **"Rechercher dans l'historique..."** - nouvelle fenêtre qui analyse `historique-lots.log`
   (déjà alimenté, jusqu'ici consultable seulement en l'ouvrant dans Notepad via "Voir
   l'historique...") et affiche les lignes dans une liste filtrable en direct par date, trio,
   fichier ou résultat.
3. **Vérification de l'espace disque avant un gros lot** - la somme des tailles des fichiers
   d'entrée sert d'estimation du besoin (le résultat est écrit juste à côté, taille comparable),
   comparée à l'espace libre du disque - avertissement non bloquant si ça semble juste.
4. **Mode sombre** - bouton dans la bannière, préférence retenue d'un lancement à l'autre. Même
   limite assumée que Coloriser-STL : scope "basique", la couleur de survol exacte des boutons
   n'est pas re-coloriée.

Comme pour le reste de ce fichier, non testé en conditions réelles faute de Windows disponible ici.

---

## Bouton "Relancer les echecs..." et notification Windows en fin de lot ("TOUS", 16/10/2026)

Deux idées d'amélioration que Coloriser-STL avait déjà et qui manquaient encore ici :

**Bouton "Relancer les echecs..."**, à côté des boutons de lot - reprend uniquement les fichiers
qui n'ont pas abouti a un succes lors du dernier lot (vrais echecs OU fichiers jamais atteints si
le lot a ete annule en cours de route), sans avoir a re-choisir le dossier/les fichiers a la main.
Meme principe que le bouton equivalent de Coloriser-STL.

**Notification Windows (zone de notification) a la fin d'un lot**, en plus du son deja joue -
pratique pour un lot lance puis laisse de cote. Meme mecanisme (`NotifyIcon`/`ShowBalloonTip`) que
Coloriser-STL, qui l'avait deja.

Comme pour le reste de ce fichier, non teste en conditions reelles faute de Windows disponible ici.

---

## Galerie de tous les resultats d'un lot, et temps restant estime (ETA) ("Ok pour tout", 16/10/2026)

**Galerie montrant TOUS les resultats reussis d'un lot, pas seulement le dernier.** Jusqu'ici, a la
fin d'un lot, seul l'apercu "apres" principal etait mis a jour, avec le DERNIER fichier traite -
aucune vue d'ensemble des autres resultats. Une nouvelle fenetre s'ouvre maintenant automatiquement
a la fin d'un lot reussi (au moins un fichier OK), avec une carte par fichier : nom, bouton "Ouvrir
le dossier" et bouton "Afficher l'apercu" qui charge le rendu 3D a la demande plutot que pour
chaque resultat d'un coup - le rendu maison (meme fonction que l'apercu avant/apres principal) est
deja signale lent par Tomyn sur un seul fichier, le charger automatiquement pour chaque resultat
d'un gros lot aurait fige la fenetre inutilement si seuls quelques fichiers interessent. L'apercu
"apres" principal continue par ailleurs d'afficher le dernier fichier comme avant, sans changement.

**Temps restant estime (ETA) pendant un lot**, meme principe que Coloriser-STL : moyenne glissante
(temps ecoule / fichiers faits x fichiers restants), affiche a la fois sous la liste de fichiers et
dans le titre de l'overlay de progression bloquant.

Comme pour le reste de ce fichier, non teste en conditions reelles faute de Windows disponible ici
(calcul de l'ETA verifie isolement par un petit script PowerShell de test, mais pas l'affichage
reel ni le rendu de la nouvelle fenetre, System.Drawing/GDI+ n'etant pas disponible dans ce
bac a sable Linux) : a valider par Tomyn a l'usage.

---

## Trois ameliorations validees d'un coup ("tu peux tout faire", 16/10/2026) : bouton Annuler sur
## le lot, indicateur de couverture en direct sur le vrai fichier

**Bouton "Annuler" ajoute sur le lot (et sur un fichier seul).** Jusqu'ici, contrairement a
Coloriser-STL, il n'existait aucun moyen d'interrompre un lot en cours - il fallait attendre la
fin ou fermer l'appli. Le bouton Annuler vit sur l'overlay de progression lui-meme (seul endroit
accessible pendant le traitement, l'overlay etant au-dessus de tout) : un clic marque l'annulation,
verifiee a chaque point de passage deja existant de Traiter-Fichier3MF (memes points que la barre
de progression - lecture, dosages, ecriture config, remappage, reconstruction), donc aucune
instrumentation supplementaire necessaire dans la boucle de remappage. Sur un lot, le fichier en
cours est abandonne et le lot s'arrete la (pas de reprise automatique du fichier interrompu - a
relancer a la main si besoin, comme pour un echec classique) ; le resume final indique "Lot annule"
plutot que "Lot termine".

**Indicateur de couverture en direct, sur le VRAI fichier charge, pas juste sur le trio en
theorie.** Le petit texte "Couverture : etroite/large" sous le trio choisi ne regardait jusqu'ici
que l'ecartement theorique des 3 couleurs du trio entre elles, sans tenir compte des couleurs
reelles du fichier .3mf ouvert - il fallait cliquer "Verifier la couverture du fichier..." pour
avoir une vraie reponse sur CE fichier. Desormais, dès qu'un fichier est charge (ouverture,
glisser-deposer, ou rechargement automatique du dernier fichier au demarrage), ce texte affiche le
VRAI resultat ("Couverture sur ce fichier : X/Y couleur(s) a risque") et se met a jour tout seul a
chaque changement de trio dans le menu - plus besoin de cliquer sur le bouton de verification a
chaque trio teste. Repli silencieux sur l'ancien score theorique si aucun fichier n'est charge ou
si la lecture echoue.

---

## L'overlay de progression ne passe plus devant les avertissements qu'il faut encore valider
## (16/10/2026, Tomyn : "la barre de progression se met devant l'avertissement de la couverture
## donc chiant parce qu'on peut pas bien cliquer sur le bouton pour accepter")

L'overlay (toujours affiché au premier plan, TopMost) s'affichait trop tôt dans le lancement d'un
fichier seul : avant l'avertissement "Couverture à surveiller" et avant la confirmation
d'écrasement d'un fichier déjà existant, qui sont des boîtes modales mais SANS TopMost - l'overlay
passait devant et empêchait de cliquer sur leurs boutons Oui/Non/OK. Il ne s'affiche désormais
qu'une fois ces confirmations validées, juste avant le vrai traitement - et il est aussi masqué
avant d'afficher la boîte d'erreur en cas d'échec, pour la même raison.

---

## La barre de progression disparaît maintenant seule, quelques secondes après 100% (16/10/2026,
## Tomyn : "la barre de progression quand elle est arrivée à 100% elle reste, il faut que je
## reclique de l'application pour qu'elle disparaisse, il faudrait qu'elle disparaisse au bout
## d'un certain moment ... au bout de 5 ou 6 secondes dès qu'elle est à 100% elle disparaît
## d'elle-même")

Jusqu'ici l'overlay restait affiché jusqu'au clic sur la boîte de dialogue de fin qui suit, aussi
bien pour un fichier seul que pour un lot. Nouvelle fonction Masquer-OverlayProgressionApresDelai
(boucle non-bloquante avec DoEvents(), pas un simple Start-Sleep, pour garder l'IHM réactive
pendant l'attente) : une fois le traitement terminé, la barre est forcée à 100% puis l'overlay se
referme tout seul 5 secondes plus tard, sans que Tomyn ait besoin de cliquer sur quoi que ce soit
avant.

---

## Correctif urgent : la barre bloquante ralentissait vraiment le traitement (16/10/2026, Tomyn :
## "ça bloque complètement la prix ça fait 5 minutes que j'attends, d'habitude ça se trouve pas si
## longtemps")

$form.Enabled = $false (ajouté juste avant pour bloquer les clics pendant l'overlay) ralentissait
réellement le remappage du maillage, pas juste visuellement - très probablement un conflit de
focus/activation entre la fenêtre principale désactivée et l'overlay TopMost au-dessus, qui
ralentit la boucle de messages Windows pendant les DoEvents() fréquents de cette étape. Retiré :
l'overlay reste affiché par-dessus (toujours visible, toujours dans le style de l'appli) mais la
fenêtre principale n'est plus désactivée - les boutons d'action restent désactivés individuellement
comme avant, donc rien de nouveau n'est déclenchable pendant le traitement, juste sans le
ralentissement.

---

## Vraie barre de progression bloquante, par-dessus l'appli (16/10/2026, Tomyn : "trop discrete, il
## faudrait un vrai barre de progression qui se mete au dessus de l'appli et qui bloque toutes
## action sur les appli tant qu'elle n'est pas finie, style comme sur les photo que je viens de
## t'envoyer, bien sur dans le style de l'application")

La barre au-dessus du journal (entrée juste en dessous) ne suffisait pas. Nouvelle fenêtre sans
bordure, toujours au premier plan, aux couleurs de l'appli (violet foncé + remplissage orange),
affichée centrée par-dessus la fenêtre principale pendant tout le traitement (lancement simple
fichier ou lot) - la fenêtre principale est désactivée en dessous le temps du traitement. Pilotée
par le même callback de progression ajouté à Traiter-Fichier3MF ci-dessous (en lot, la progression
globale combine fichier courant/total ET avancement à l'intérieur du fichier en cours).

---

## Barre de progression visuelle pour "Lancer le mélange" (16/10/2026, Tomyn : "le texte
## d'avancement c'est bien mais c'est abstrait, faudrait plutot une barre de progression en plus,
## c'est plus visuel")

Jusqu'ici, seul le traitement en lot affichait une barre de progression - un lancement simple
fichier n'avait que le texte défilant dans "Avancement". Traiter-Fichier3MF accepte maintenant un
callback de progression optionnel, appelé à quelques étapes repérées (lecture config, calcul des
dosages, extension des réglages, remappage du maillage, reconstruction du .3mf) - pas une mesure
exacte (le remappage n'a pas de total de triangles connu à l'avance, donc avance par paliers), mais
assez pour qu'elle bouge du début à la fin au lieu de rester figée. Réutilise la barre déjà en place
au-dessus du journal (jusque-là réservée au lot).

---

## Diagnostic : le fichier initial de la passerelle n'arrivait toujours pas (16/10/2026, Tomyn :
## "toujours pas il prend pas le bon il prend celui [non] genere par colorisation")

Après avoir corrigé le lancement côté Coloriser-STL (`wscript.exe` direct au lieu de passer par
l'association de fichier .vbs), le souci persistait. Sans machine Windows pour reproduire, ajouté
une trace explicite dans le journal au démarrage : "Fichier initial reçu de Coloriser-STL : ..."
ou "Aucun fichier initial reçu..." - ça dira d'un coup d'œil si `-FichierInitial` arrive vraiment
jusqu'ici ou pas, pour savoir si le problème est encore côté transmission (Coloriser-STL /
`Lancer-Melange-Couleurs.vbs`) ou ici. Titre de la fenêtre aussi mis à jour (`[build 16/10 08h50]`)
pour vérifier facilement que c'est bien le nouveau fichier qui tourne.

---

## Correction de lenteur : "Suggérer un trio pour ce fichier..." (16/10/2026, Tomyn : "quand j'ai
## beaucoup de trio perso et que je clique suggerer un trio pour ce fichier c'est ultra long c'est
## chiant")

Le vrai coût n'était pas le calcul de couleur (rapide), c'était `Obtenir-CouleursFichier3MF` qui
**dézippe le .3mf sur le disque** (extraction + nettoyage) à chaque appel - et
`Verifier-CouvertureFichier` l'appelait une fois PAR TRIO testé. Avec beaucoup de trios
personnalisés (et pire : la recherche de secours dans "mes couleurs", qui teste toutes les
combinaisons de 3 possibles - des centaines avec un stock un peu fourni), ça redézippait le même
fichier inchangé encore et encore. Séparé en deux fonctions : `Verifier-CouvertureAvecCouleurs`
fait le calcul à partir d'une liste de couleurs déjà extraite, et `Verifier-CouvertureFichier`
devient un simple raccourci (extrait puis délègue) pour les rares endroits qui ne testent qu'un
seul trio. Les trois boutons de suggestion ("Suggérer un trio...", "Suggérer 5 trios...", et la
recherche dans le stock de couleurs) extraient maintenant le fichier UNE SEULE fois et réutilisent
cette liste pour tous les trios/combinaisons testés.

---

## Passerelle depuis Coloriser-STL : -FichierInitial (16/10/2026)

Côté Coloriser-STL, chaque résultat .3mf a maintenant un bouton "Analyser les couleurs..." qui
lance cet outil directement sur ce fichier (voir le changelog de Coloriser-STL). Pour que ça
marche : `Lancer-Melange-Couleurs.vbs` accepte un argument optionnel (le chemin du .3mf) qu'il
transmet à `Melange-Couleurs-GUI.ps1` via un nouveau paramètre `-FichierInitial`. Au démarrage,
s'il est fourni et que le fichier existe toujours, il passe devant le "dernier fichier utilisé"
habituel (plus pertinent : c'est le résultat que Tomyn vient d'obtenir), et devient lui-même le
nouveau "dernier fichier" pour la prochaine fois. Sans argument (double-clic normal), rien ne
change.

---

## Sauvegarde/restauration : couleurs individuelles et trios favoris ajoutés (16/10/2026)

Tomyn a demandé un export/import de "config (couleurs + trios favoris)" pour pouvoir sauvegarder ou
transférer ça sur un autre PC. En vérifiant avant de coder quoi que ce soit (comme convenu), ce
bouton existait déjà — "Sauvegarder ma config..." / "Restaurer ma config..." zippe déjà les trios
personnalisés, le dernier trio, les trios récents, l'historique des lots et les angles de
référence. Mais `couleurs-personnalisees.json` ("mon stock" de couleurs individuelles) et
`trios-favoris.json` n'étaient PAS dans la liste — exactement les deux fichiers que Tomyn a
nommés. Ajoutés à `Obtenir-FichiersConfigConnus` (la liste centrale utilisée par les deux boutons),
et la restauration recharge maintenant aussi `$script:MesCouleurs` et `$script:TriosFavoris` en
mémoire (même raisonnement que pour les trios personnalisés : sans ça, le fichier serait bien
écrit sur le disque mais l'appli continuerait d'afficher les anciennes valeurs jusqu'au prochain
lancement).

---

Projet séparé de **Coloriser-STL** — pas de lien de code entre les deux, juste un enchaînement
naturel dans le flux de travail (coloriser avec Meshy, *puis* passer le résultat dans cet outil
avant de l'ouvrir dans Bambu Studio).

## Le problème (10/10/2026, idée de Tomyn)

Les couleurs que Meshy choisit (jusqu'à 16 par modèle) ne correspondent pas aux bobines que Tomyn a
réellement. Jusqu'ici, il devait ouvrir Bambu Studio et utiliser sa fenêtre "Décomposer la
couleur" **à la main, une fois par couleur**, pour trouver un dosage de ses filaments primaires qui
s'en approche — long et pénible pour un modèle à plusieurs couleurs.

## Ce que fait l'outil

1. Tu lui donnes un `.3mf` colorisé (sortie de Coloriser-STL, ou n'importe quel projet Bambu Studio
   avec des couleurs peintes dessus).
2. Il te demande quel quatuor de primaires utiliser : **CMYW** (cyan/magenta/jaune/blanc) ou
   **RYBW** (rouge/jaune/bleu/blanc) — les deux mêmes quatuors que propose Bambu Studio.
3. Il calcule automatiquement le meilleur dosage pour **chacune** des couleurs détectées (ou pour
   des groupes de couleurs proches, voir ci-dessous).
4. Il ressort un `.3mf` où tout est déjà mélangé, prêt à ouvrir et trancher directement dans Bambu
   Studio — plus besoin de repasser par la fenêtre de Bambu Studio à la main. L'explorateur Windows
   s'ouvre directement sur le fichier créé, sélectionné — plus besoin d'aller le chercher à la main.

## Nombre de mélanges réglable (10/10/2026, demandé par Tomyn)

L'AMS (et le fichier Bambu Studio) a une limite de 32 emplacements de filament au total. 4 sont
toujours réservés aux primaires, ce qui laisse **jusqu'à 28 mélanges**. Un sélecteur dans la
fenêtre (pré-rempli automatiquement avec le nombre de couleurs détectées dans le fichier, plafonné
à 28) permet de demander **moins** de mélanges que de couleurs détectées :

- Si on demande autant de mélanges que de couleurs détectées (ou plus) : comportement d'origine,
  un mélange par couleur.
- Si on en demande moins : les couleurs les plus proches visuellement (distance Lab, la même
  mesure que pour le choix du dosage) sont regroupées automatiquement et traitées comme un seul
  mélange — son dosage est calculé sur leur moyenne. Plus on demande de mélanges, plus le résultat
  est fidèle aux couleurs d'origine du modèle ; moins on en demande, plus certaines couleurs
  voisines se retrouvent fondues ensemble. Le journal détaille toujours quelles couleurs ont été
  regroupées dans quel mélange.
- Le regroupement est déterministe (pas de hasard) : le même fichier avec le même nombre de
  mélanges donne toujours exactement le même résultat.

Vérifié ici (PowerShell 7, logique uniquement — pas de différence avec la vraie machine Windows
sur cette partie, aucun `System.Drawing`/WinForms en jeu) : regroupement correct sur un jeu de
couleurs synthétique (les paires quasi identiques se retrouvent bien dans le même groupe), et sur
le vrai fichier de Tomyn réduit à 2 mélanges pour 6 couleurs détectées — fichier de sortie valide,
`flush_volumes_matrix`, `filament_mixed_components/ratios`, `filament_self_index` et les codes
`paint_color` du maillage tous corrects face à ce regroupement.

## Aperçu avant / après (10/10/2026, demandé par Tomyn)

La fenêtre affiche maintenant, à droite du journal, un aperçu en image fixe du modèle 3D (pas un vrai
visualiseur 3D qu'on peut tourner à la souris - juste une image statique, demandé pour pouvoir juger
d'un coup d'œil sans ouvrir Bambu Studio) :
- **"Couleurs détectées"** dès qu'un fichier est choisi, avec les couleurs Meshy telles quelles.
- **"Après mélange"** une fois le traitement terminé, avec les couleurs réellement obtenues par le
  dosage calculé (pas les couleurs Meshy d'origine - le résultat visuel approximatif du mélange).

Technique : projection isométrique maison (pas une vraie librairie 3D) + tri peintre (les triangles
les plus loin dessinés en premier) + un ombrage simple selon l'orientation de chaque triangle, dessiné
avec les outils de dessin standards de Windows (`System.Drawing`).

**Partie non testée** : cette fonctionnalité a été développée et vérifiée ici sans machine Windows
disponible - toute la partie "lecture du maillage et des couleurs" a été testée pour de vrai (avec
PowerShell 7, sur le fichier de test de Tomyn, 199 000 triangles, couleurs correctement retrouvées
aussi bien avant qu'après mélange), mais le dessin à l'écran lui-même (`System.Drawing`, qui n'existe
que sous Windows) n'a **jamais pu être exécuté** avant l'envoi - contrairement au reste de l'outil. Si
l'aperçu est vide, déformé, ou fait planter/ralentir la fenêtre, c'est la première chose à signaler.

### Correctif du 10/10/2026 : "l'appli ne répond pas" sur le gros fichier

Tomyn a signalé que la fenêtre se figeait ("ne répond pas", Windows) avec la version ci-dessus sur
son gros fichier. Cause trouvée en comparant le calcul de l'aperçu à ce qui avait déjà fait grimper
le mélange des couleurs à 2 minutes avant son propre correctif (voir plus bas) : le calcul de
l'aperçu (lecture du maillage puis rendu de l'image) tournait **entièrement sur le thread de la
fenêtre**, qui ne pouvait donc plus traiter aucun message (redessiner, déplacer, etc.) pendant tout
ce temps - assez longtemps sur un gros maillage pour que Windows affiche "ne répond pas", même si le
calcul se terminait tout seul au bout d'un moment.

Deux correctifs combinés :
1. **Calcul remis en arrière-plan.** L'aperçu tourne maintenant dans un second interpréteur
   PowerShell (un "Runspace"), sur un autre thread, et la fenêtre reste utilisable pendant le
   calcul - un petit minuteur vérifie régulièrement si c'est fini pour venir poser l'image une fois
   prête.
2. **Calcul lui-même accéléré.** Le code utilisait `Add-Member` et `Sort-Object` sur un objet par
   triangle - deux opérations très coûteuses par élément en PowerShell sur un gros volume (déjà vu
   avec le mélange des couleurs). Remplacé par des tableaux de nombres classiques et
   `[System.Array]::Sort`. Vérifié ici avec PowerShell 7 : même résultat exact (zéro différence sur
   3000 triangles de test), mais sur 150 000 triangles, **37 secondes → 1,3 seconde**. Sur le vrai
   fichier de Tomyn (199 251 triangles), la lecture du fichier prend ~6,5 s et ce calcul ~1,8 s -
   seul le dessin à l'écran (`System.Drawing`, non testable ici) n'a pas pu être chronométré, mais
   il tourne maintenant en arrière-plan de toute façon, donc même s'il reste lent, il ne bloquera
   plus la fenêtre.

Toujours pas testé pour de vrai sous Windows (seule la partie calcul, sans le dessin, a pu être
vérifiée ici) : si "ne répond pas" revient, ou si l'aperçu met plus d'une poignée de secondes à
apparaître sans jamais arriver, c'est le prochain point à signaler.

## Comment lancer

Double-clic sur `Lancer-Melange-Couleurs.vbs` — même interface graphique (mêmes couleurs, même
bannière, mêmes boutons) que Coloriser-STL, juste un autre projet : aucune fenêtre console ne
s'affiche, tu choisis le fichier avec un bouton "Parcourir..." (ou glisser-déposer), le quatuor dans
une liste déroulante, et tu cliques sur "Lancer le mélange". L'avancement s'affiche dans le journal
de la fenêtre.

## Comment ça marche côté technique

Un `.3mf` de Bambu Studio est juste une archive zip avec du JSON dedans
(`Metadata/project_settings.config`) et un fichier de maillage XML
(`3D/3dmodel.model`). Tomyn a envoyé un exemple de fichier où il avait fait un mélange à la main
dans Bambu Studio, ce qui a permis de retrouver le format exact utilisé pour stocker un mélange :
- `filament_is_mixed`, `filament_mixed_components`, `filament_mixed_sublayer_ratios` dans
  `project_settings.config` (quels filaments de base, et dans quelle proportion)
- `paint_color="NC"` sur chaque triangle du maillage dans `3dmodel.model` (N = numéro du filament
  utilisé à cet endroit)

Le script ajoute les 4 primaires choisies comme nouveaux filaments (emplacements 1 à 4), et pour
chaque couleur Meshy détectée crée un filament "mélangé" virtuel avec le dosage calculé
(emplacements 5 et suivants). Il réécrit aussi tous les réglages "par filament" du projet (une
centaine de champs au total : température, vitesse, etc.) pour la nouvelle liste de filaments, en
dupliquant des valeurs raisonnables (du premier filament d'origine) plutôt que de deviner un par un
ce que chaque champ signifie individuellement.

## Grosse réserve à avoir en tête

La formule utilisée pour calculer le dosage est une approximation maison (mélange en "lumière
linéaire", comparaison perceptuelle dans l'espace Lab — la méthode la plus défendable sans données
de calibration réelles des filaments), **pas** la formule de Bambu Studio. En comparant plusieurs
captures d'écran envoyées par Tomyn (même couleur cible, décomposée par Bambu Studio en CMYW et en
RYBW), aucune formule RGB simple testée ne retombe sur ce que Bambu Studio affiche comme résultat —
Bambu Studio se base très probablement sur des données de calibration physique de ses filaments,
qu'on n'a pas. Donc le dosage calculé ici peut être différent de celui de Bambu Studio, sans qu'on
sache lequel des deux est le plus fidèle à la réalité imprimée.

**Testé pour de vrai le 10/10/2026** (PowerShell 7 installé spécialement pour l'occasion, faute
d'accès à un Windows ici) sur le fichier de test de Tomyn, après trois aller-retours sur des bugs
remontés par ses propres essais sur sa machine :
- `filament_colour_type` (et les autres champs ajoutés au fichier) provoquaient une erreur
  PowerShell ("propriété introuvable") quand ce champ n'existait pas déjà dans le `.3mf` d'origine —
  corrigé en créant la propriété si besoin, ou en l'écrivant normalement si elle existe déjà.
- Le `.3mf` généré s'ouvrait avec une erreur Bambu Studio ("le fichier ne contient pas de données
  géométriques"). Deux causes cumulées : (1) le zip était reconstruit avec des antislashs dans les
  noms d'entrée (`3D\3dmodel.model` au lieu de `3D/3dmodel.model`) à cause d'un comportement de
  .NET Framework sur Windows, invalide pour le format ZIP/3MF — corrigé en reconstruisant le zip
  entrée par entrée avec des slashs forcés ; (2) le maillage et les `paint_color` n'étaient pas
  forcément dans `3D/3dmodel.model` mais dans un fichier séparé sous `3D/Objects/` (Bambu Studio
  éclate souvent chaque objet dans son propre fichier) — l'ancienne version ne regardait que
  `3dmodel.model` et ne remappait donc rien du tout sur ce genre de fichier ; corrigé en parcourant
  tous les `.model` sous `3D/`.
- Bambu Studio plantait ensuite avec "Out of Memory" à l'ouverture, **à deux reprises** (deux
  correctifs insuffisants avant de trouver la vraie cause). Confirmé en installant PowerShell 7 ici
  (faute de Windows) et en rejouant le script sur le vrai fichier de Tomyn pour comparer :
  **n'importe quel champ tableau réaffecté par le script** (pas seulement ceux qu'on ajoute — même
  ceux dupliqués par la boucle générique, déjà présents dans le fichier d'origine) ressortait, sur
  Windows PowerShell 5.1 uniquement, en JSON sous la forme `{"value":[...], "Count":N}` au lieu d'un
  tableau tout simple — un bug de `ConvertTo-Json` propre à cette version (le même code rejoué sur
  PowerShell 7 produit un tableau correct). Bambu Studio lisait cette structure malformée de travers
  et partait sur une allocation mémoire démesurée. Plutôt que de chercher un énième contournement de
  `ConvertTo-Json`, le script ne l'utilise plus du tout pour réécrire le fichier : il modifie
  directement le texte JSON d'origine (recherche/remplacement ciblé, un champ à la fois), donc tout
  le reste du fichier (~500 autres réglages) reste identique à l'original au caractère près. Au
  passage, deux pièges à éviter avec cette méthode (trouvés en testant, pas par chance) : il faut
  rééchapper les caractères spéciaux (retour à la ligne, etc.) des valeurs relues depuis le JSON
  avant de les réécrire — un champ comme le G-code de début de filament en contient — et le motif de
  recherche doit reconnaître correctement une suite de chaînes entre guillemets plutôt que de
  s'arrêter au premier crochet `[`/`]` rencontré, ce même G-code contenant des crochets dans son
  texte (`bed_temperature[current_extruder]`).

Avec ce fichier-là corrigé, Bambu Studio plantait encore, mais cette fois sans aucun message
d'erreur (plantage silencieux). Cause trouvée en comparant les valeurs du fichier de Tomyn à ce
qu'elles auraient dû être : `filament_mixed_sublayer_ratios` contenait des **virgules à la place des
points décimaux** (`"0,3000,0,1500,0,5500,0,0000"` au lieu de `"0.3000,0.1500,0.5500,0.0000"`) — 4
ratios valides transformés en 8 fragments illisibles pour Bambu Studio. En cause : le formatage
`"{0:0.0000}" -f (...)` utilise par défaut la langue régionale de Windows pour le séparateur
décimal, et la machine de Tomyn est configurée en français. Confirmé en forçant PowerShell 7 (ici)
en culture française : le même bug se reproduit à l'identique, et disparaît en forçant une culture
"invariante" (point décimal, indépendant de la langue de Windows) pour cette conversion précise -
c'est ce que fait maintenant le script, peu importe la langue régionale de la machine qui l'exécute.

Avec ce fichier-là aussi corrigé, Bambu Studio replantait en "Out of Memory" — mais cette fois la
vraie cause s'est trouvée dans le fichier de test de Tomyn lui-même : il contenait, sans qu'on le
sache au début, un **vrai mélange fait par Tomyn à la main dans Bambu Studio** (3 primaires sur un
quatuor de 4, le 4e - le blanc - à 0%). Comparer ce que Bambu Studio avait lui-même écrit pour ce
mélange a révélé la dernière différence : Bambu Studio enregistre `filament_mixed_components` et
`filament_mixed_sublayer_ratios` avec **seulement les primaires réellement utilisées** (ex. `"1,2,3"`
et `"0.2000,0.4500,0.3500"`, 3 valeurs chacun) - jamais une primaire à 0%. Le script, lui, écrivait
systématiquement les 4 primaires du quatuor, y compris celles à 0% (ex. `"1,2,3,4"` avec un 4e ratio
à `"0.0000"`) - un format que Bambu Studio n'écrit jamais lui-même, très probablement responsable du
plantage (une longueur de tableau inattendue peut facilement déclencher une mauvaise allocation
mémoire côté C++, d'où l'écran "Out of Memory"). Corrigé : seules les primaires avec un dosage non
nul sont désormais écrites, exactement comme le fait Bambu Studio.

Vérifié de bout en bout, **y compris en forçant la culture française pour reproduire exactement les
conditions de la machine de Tomyn**, sur son fichier de test (6 couleurs Meshy, maillage dans
`3D/Objects/object_1.model`, ~199 000 triangles peints, 103 réglages par filament) : zip valide
(bons slashs), maillage correctement remappé, JSON de configuration valide avec des points décimaux
partout où il faut et des listes de primaires au même format que celles de Bambu Studio lui-même,
sans doublon de champ, sans aucun champ corrompu, et le reste du fichier identique octet pour octet
à l'original. Reste à confirmer que Bambu Studio l'ouvre et tranche correctement sur sa machine —
c'est le test qui compte vraiment, celui-ci n'a jamais pu être fait ici faute de Bambu Studio
disponible.

**Encore un "Out of Memory" après tout ça (10/10/2026)**, cette fois sur le vrai fichier de Tomyn
(199 000 triangles, acheté sur un pack - **pas** un fichier simplifié par lui, et le `.3mf` d'origine
s'ouvre très bien dans Bambu Studio à cette même taille, donc la taille du fichier n'était pas la
cause). En comparant les couleurs détectées dans son fichier : 3 des 6 couleurs Meshy correspondaient
déjà à 100% à l'une des 4 primaires choisies (écart Lab de 0.0 - correspondance exacte). Le script
créait quand même, pour ces 3 couleurs, un filament "mélangé" virtuel avec... un seul ingrédient à
100% (`filament_is_mixed="1"`, un seul composant, un seul ratio "1.0000") - une forme que Bambu
Studio ne produit jamais lui-même (un "mélange" à un seul ingrédient n'est juste pas un mélange).
Ça créait aussi deux filaments avec exactement la même couleur hexadécimale dans la liste
(la primaire, et son double "mélangé"). Corrigé : quand le dosage calculé ne retient qu'une seule
primaire (0 ou 1 composant non nul), le filament correspondant est maintenant écrit comme un
filament normal, non mélangé (`filament_is_mixed="0"`, composants et ratios vides) - exactement le
même format qu'une primaire ordinaire. Revérifié de bout en bout (zip, XML, JSON, décimales, pas de
doublon de champ) sur le vrai fichier de Tomyn, culture française forcée incluse : les 3 couleurs à
correspondance exacte sortent maintenant bien en filament simple, les 3 autres couleurs (vrais
mélanges à 2 ou 3 primaires) sortent toujours avec leurs composants/ratios corrects.

**Nouveau plantage silencieux signalé (10/10/2026), cette fois sur un autre modèle ("ninja")**, avec
un fichier généré bien plus court que la normale (2,5 Ko au lieu de plusieurs dizaines de Ko). En
comparant systématiquement la taille de CHAQUE champ tableau du fichier d'origine à un multiple exact
du nombre de couleurs Meshy détectées (plutôt que d'attendre un nouveau message d'erreur précis, qui
ne venait pas), deux familles de champs se sont révélées mal gérées :

- **`flush_volumes_matrix`** : ce n'est pas un simple réglage "par filament" mais une vraie matrice
  (volume de purge entre chaque PAIRE de filaments), de taille (nombre de filaments)². Le script ne
  la touchait pas du tout - elle restait à sa taille d'origine (ex. 36 = 6×6 pour 6 couleurs) alors
  que le fichier final en compte 10 (devrait être 100 = 10×10). Bambu Studio indexe cette matrice
  directement avec le numéro de filament : une matrice trop petite veut dire une lecture en dehors du
  tableau côté C++ - très probablement la vraie cause de tous les plantages "Out of Memory" précédents,
  avant même d'arriver aux autres champs. Corrigé : la matrice est maintenant reconstruite à la bonne
  taille, les cases entre deux couleurs d'origine gardant leur valeur calibrée exacte, les cases
  touchant une nouvelle primaire recevant la valeur la plus fréquente hors diagonale de la matrice
  d'origine (la valeur "par défaut" que Bambu Studio lui-même utilise entre deux filaments sans
  calibration particulière).
- **~49 autres réglages "par filament"** (vitesses de retrait, températures, etc.) stockent en réalité
  **plusieurs valeurs consécutives par filament** (le plus souvent 2, parfois 4) et non une seule -
  leur longueur ne tombait donc jamais exactement sur le nombre de couleurs détectées, et la boucle
  d'extension (qui ne cherchait que les tableaux de longueur exactement égale à ce nombre) les
  ignorait complètement, les laissant eux aussi trop courts pour le nouveau total de filaments. Corrigé
  avec la même logique que les champs simples, mais bloc par bloc.
- Cas particulier dans ce deuxième groupe : **`filament_self_index`**, qui ne stocke pas une propriété
  du filament mais son PROPRE numéro. Le dupliquer comme les autres aurait donné des numéros faux (les
  nouvelles primaires auraient toutes porté le numéro 1, et les couleurs d'origine auraient gardé leur
  ancien numéro au lieu de leur nouvelle place). Corrigé en le recalculant entièrement à partir de la
  nouvelle position de chaque filament.

Revérifié de bout en bout sur le vrai fichier de test de Tomyn (toujours zip valide, maillage XML
valide, JSON sans doublon ni champ corrompu, décimales à points partout, matrice de purge et champs
"par bloc" maintenant à la bonne taille, numérotation `filament_self_index` correcte).

**Trouvé LE vrai bug (10/10/2026)**, très probablement la cause de TOUS les plantages silencieux
depuis le début, en comparant un fichier généré par ce script à deux fichiers où Tomyn a refait le
même mélange **à la main dans Bambu Studio** (une fois en RYBW, une fois en CMYW, mêmes couleurs
Meshy) - une comparaison bien plus parlante que n'importe quel message d'erreur.

L'attribut `paint_color` du maillage n'est **pas un numéro de filament écrit en décimal**, contrairement
à ce que tout le reste de ce document a supposé jusqu'ici. C'est un format propre à PrusaSlicer/Bambu
Studio pour la "peinture multi-matière" : une chaîne de chiffres hexadécimaux qui encode, bit par bit,
un petit arbre - *"ce triangle est-il subdivisé (pour un dégradé de couleur sur son bord), et si oui en
combien de sous-triangles, sinon quel est son numéro de filament"* - rangé à l'envers (le dernier
caractère de la chaîne est lu en premier). Le script ajoutait 4 au nombre décimal trouvé en tête de la
chaîne - ce qui tombait juste par **pur hasard** pour certaines couleurs et cassait complètement les
autres. Exemple concret trouvé en comparant : la valeur `"8"` (qui encode en réalité le filament n°2)
devenait `"12"` après le décalage naïf - un code qui ne veut rien dire dans ce format (il dit "ce
triangle est divisé en 3 sous-triangles" sans fournir les données de ces 3 sous-triangles). Avec des
milliers de triangles corrompus de cette façon d'un coup à chaque fichier, c'est très probablement la
vraie explication de tous les "Out of Memory" et plantages silencieux précédents, malgré tous les
correctifs déjà faits sur la configuration JSON.

Corrigé en décodant vraiment ce petit arbre (même algorithme que celui utilisé par Bambu Studio/
PrusaSlicer, retrouvé dans leur code source), en décalant uniquement les numéros de filament qu'il
contient - jamais sa structure de subdivision - puis en le réencodant à l'identique. Vérifié caractère
par caractère contre les deux fichiers où Tomyn a fait le même mélange à la main (RYBW et CMYW, mêmes
4 couleurs Meshy, mêmes résultats dans les deux cas), et sur la totalité des 199 000+ triangles de son
fichier de test (un passage sans aucun décalage redonne exactement la chaîne de départ, partout, aucune
anomalie).

Revers de la médaille signalé par Tomyn au premier essai : ce décodage correct est bien plus lent que
le simple remplacement de texte d'avant - environ 2 minutes sur son fichier de 199 000 triangles.
Cause : le script décodait/réencodait CHAQUE triangle individuellement, alors qu'un maillage peint n'a
en pratique que 3 ou 4 codes `paint_color` *différents* au total (chaque zone d'une même couleur
partage le même code, même répété sur des centaines de milliers de triangles). Corrigé en ne calculant
le résultat qu'une fois par code réellement différent rencontré, et en réutilisant ce résultat pour
toutes les répétitions suivantes (un simple cache) : même fichier de test, même résultat caractère
pour caractère, mais **5 secondes au lieu de 2 minutes**.

**À faire avant de faire confiance au résultat** : tester d'abord sur un petit fichier simple,
vérifier que ça s'ouvre bien dans Bambu Studio sans erreur, et idéalement confirmer par une
impression test avant de lancer un mélange sur un gros modèle.

## Couleurs primaires utilisées (à corriger si besoin)

Récupérées par échantillonnage des captures d'écran de la fenêtre "Décomposer la couleur" de Bambu
Studio envoyées par Tomyn, recoupées avec les couleurs trouvées dans son fichier de test `.3mf` :

| Couleur | Hex |
|---|---|
| Cyan | `#0086D6` |
| Magenta | `#EC008C` |
| Jaune | `#F4EE2A` |
| Rouge | `#C12E1F` |
| Bleu | `#0A2989` |
| Blanc | `#FFFFFF` (supposé pur — à corriger si la bobine blanche réelle est teintée) |

## 11/10/2026 au 13/10/2026 : passage aux trios + grosse série de fonctionnalités

**Bascule "quatuor" (4 primaires) -> "trio" (3 primaires)** : vérifié directement dans Bambu
Studio que l'AMS ne mélange que 3 couleurs à la fois, pas 4 — toute la logique de dosage et les
primaires prédéfinies (devenues Pastel/Néon) sont passées en trios pour coller à cette vraie
limite.

**Corrigé un bug d'affichage récurrent** sur plusieurs fenêtres secondaires ("Trios suggérés
depuis mes couleurs" notamment) qui n'affichaient qu'une partie de leur contenu quel que soit le
contrôle WinForms utilisé — cause : usage de `Dock`/redimensionnement automatique sur des popups,
remplacé par un layout entièrement figé (`FormBorderStyle = FixedDialog`, `ClientSize` et
`Location`/`Size` fixes sur chaque contrôle), calqué sur la fenêtre "Gérer mes couleurs" qui
n'avait jamais eu ce problème.

**Stock de couleurs personnel + suggestion de trios** : nouvelle fenêtre "Gérer mes couleurs"
(liste de couleurs indépendante des trios), et "Suggérer des trios depuis mes couleurs" qui teste
toutes les combinaisons de 3 couleurs du stock et propose les meilleures par couverture Lab sur le
fichier choisi.

**Petite série de fonctionnalités ajoutées au fil des demandes, chacune validée avant d'être
codée :**
- Pastilles de couleur + marqueur favori dans le menu déroulant des trios
- Avertissement si une couleur ajoutée/modifiée est quasi-identique à une déjà en stock (distance
  Lab)
- Mémorisation du dernier fichier `.3mf` utilisé, rechargé seul au démarrage
- Suppression en cascade : supprimer une couleur supprime les trios personnalisés qui s'en
  servaient
- Sélection multiple (Ctrl/Shift-clic, "Tout sélectionner", touche Suppr) dans "Gérer mes
  couleurs", "Gérer mes trios" et "Suggérer des trios depuis mes couleurs"
- Rappel "déjà mélangé le [date] avec le trio [nom]" basé sur l'historique, affiché à côté de
  "Lancer le mélange"
- Trios favoris (étoile), remontés en haut du menu déroulant
- Bouton "Ouvrir le dossier contenant" à côté du fichier `.3mf` sélectionné
- Vérification automatique de la couverture du fichier **avant** de lancer un mélange pour de vrai
  (pas seulement via le contrôle à la demande existant), avec confirmation si le trio choisi rend
  mal certaines couleurs
- "Annuler la dernière suppression" (couleur ou trio), un seul niveau
- Compteur "utilisé X fois" par trio dans "Gérer mes trios", basé sur l'historique des lots

Vérifié à chaque étape par analyse syntaxique PowerShell (AST) et, pour la logique non triviale
(détection de quasi-doublon, suppression en cascade, ordre favoris/récents), par des scripts de
test isolés avant application au fichier principal. Jamais testé sur une vraie machine Windows
pendant cette série — comme pour les étapes précédentes, le premier retour réel reste à confirmer
par Tomyn.

## 13/10/2026, build 10h00

**"Suggérer des trios depuis mes couleurs" ne reproposait pas les trios déjà sauvegardés.**
Ajouter une couleur au stock puis relancer la suggestion pouvait ressortir une combinaison déjà
enregistrée (prédéfinie ou perso) dans la liste des trios. La recherche de combinaisons compare
maintenant chaque trio candidat (ensemble de ses 3 teintes, peu importe l'ordre) à tous les trios
déjà existants, et ignore ceux qui correspondent exactement.

## 13/10/2026, build 11h00

**Avertissement si le mélange ne peut pas tout traiter** (13/10/2026, Tomyn : constaté en
remarquant qu'un fichier déjà mélangé, repassé une deuxième fois dans l'outil, donnait un
meilleur résultat). Certains fichiers (export Meshy/Bambu Studio) peuvent contenir des zones
peintes sur le maillage, ou un objet entier, dont le numéro de couleur ne correspond à AUCUNE des
couleurs listées dans le fichier (`filament_colour`) — ces zones restaient alors silencieusement
non mélangées, sans aucun message. L'outil scanne maintenant le vrai maillage avant de traiter le
fichier et prévient clairement si un tel écart existe, avec le nombre de zones concernées,
plutôt que de laisser découvrir le problème par hasard en relançant le fichier une deuxième fois
(qui "marchait" par coïncidence, sans garantie que la teinte retrouvée soit la bonne).

## 13/10/2026, build 11h15

**Détail par couleur dans le rapport de couverture.** Jusqu'ici, "Vérifier la couverture du
fichier..." ne donnait qu'un total ("X couleur(s) risquent d'être mal rendues"), impossible à
vérifier sans deviner (Tomyn, sur un trio BEIGE/WHITE/BLACK proche des couleurs réelles d'un
modèle : "2 sur 4 mal rendues, ton calcul doit être un peu trop agressif non ?"). Le rapport
(popup et export .txt) liste maintenant les couleurs précises (code hex + écart Lab) qui posent
souci, triées par écart décroissant, pour juger sur pièces plutôt que sur un chiffre seul.

## 13/10/2026, build 11h25

**Seuil de couverture plus tolérant pour les tons très sombres.** Grâce au détail ajouté
ci-dessus, un cas concret est ressorti : un quasi-noir (#2A2424, légèrement chaud) marqué "mal
rendu" à côté d'un trio contenant du noir (Tomyn : "noir chaud ou noir froid, c'est noir, y'a
plus d'espoir"). L'écart Lab mesuré était géométriquement correct, mais l'œil distingue très mal
une nuance de teinte quand la luminosité est déjà très basse. Plutôt que de relever le seuil
général à l'aveugle (risque de aussi laisser passer de vrais écarts visibles sur des couleurs
claires), le seuil de détection grimpe maintenant progressivement pour les couleurs cibles très
sombres (L\* Lab < 25) : jusqu'à 32 pour du noir pur, dégressif jusqu'au seuil normal de 12 à
L\*=25 et au-dessus. Le dosage réellement choisi pour le mélange, lui, reste calculé avec toute
la précision Lab habituelle - seul le seuil d'AVERTISSEMENT change.

## 13/10/2026, build 11h35

**Fix urgent : le vrai mélange semblait bloqué plusieurs minutes.** Le scan ajouté au build
11h00 (avertissement sur les couleurs orphelines) relisait et redécodait TOUT le maillage dans
un passage séparé, EN PLUS du remappage normal, sans rien afficher à l'écran pendant ce temps -
sur un fichier avec beaucoup de triangles, ça doublait le temps de traitement en silence total,
ce qui donnait l'impression d'un blocage (signalé par Tomyn : 5 minutes d'attente sur "4
couleur(s) detectee(s)." sans suite). Le suivi des zones orphelines se fait maintenant PENDANT
le remappage déjà existant (un seul passage, coût additionnel quasi nul) au lieu d'un scan à
part - le message d'avertissement s'affiche toujours, mais sans ralentir le traitement.

## 13/10/2026, build 11h50

**Fix : la fenêtre passait "Ne répond pas" (Windows) sur un gros fichier, même après le build
11h35.** Sur un fichier de plus d'1 million de triangles, Tomyn a vu Windows marquer la fenêtre
"Ne répond pas" pendant 15 minutes à l'étape "Remappage des couleurs sur le maillage". Le build
11h35 avait bien ajouté un message de progression tous les 200 000 triangles, mais ce message
(et le `DoEvents()` qui va avec, nécessaire pour que Windows considère la fenêtre comme
réactive) ne sortait donc, lui aussi, que tous les 200 000 triangles - soit toutes les 2 à 3
minutes sur ce fichier, bien au-delà des ~5 secondes que Windows tolère avant d'afficher "Ne
répond pas". Un `DoEvents()` séparé, indépendant du message de journal, est maintenant appelé
tous les 2 000 triangles (sans rien afficher, pour ne pas spammer le journal) : la fenêtre reste
réactive en continu, le message de progression ne change pas de fréquence. Ça ne réduit PAS le
temps de calcul en lui-même (toujours proportionnel au nombre de triangles) - seulement
l'impression de blocage. Non testé en conditions réelles sur un fichier d'1 million de
triangles (pas de fichier de cette taille disponible ici).
