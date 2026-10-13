# MelangeCouleurs3MF

Interface graphique PowerShell/WinForms pour Windows qui prend un `.3mf` déjà colorisé (par
exemple la sortie de [ColoriseurSTL](https://github.com/Retrofall59/ColoriseurSTL)) et calcule
automatiquement, pour chaque couleur détectée, le dosage à faire avec **3 filaments primaires**
(mélange AMS) pour s'en approcher — au lieu de le faire à la main, couleur par couleur, dans la
fenêtre "Décomposer la couleur" de Bambu Studio.

Projet séparé de ColoriseurSTL : pas de lien de code entre les deux, juste un enchaînement naturel
dans le flux de travail (coloriser avec Meshy/Tripo, *puis* passer le résultat dans cet outil avant
de l'ouvrir dans Bambu Studio).

## Pourquoi un trio de 3 couleurs, pas 4

Les premières versions visaient des "quatuors" de 4 primaires (CMYW ou RYBW, comme les deux
réglages proposés par Bambu Studio). En vérifiant directement dans Bambu Studio, il s'est avéré que
l'AMS ne mélange que **3 couleurs à la fois**, pas 4 — l'outil est passé aux trios pour coller à
cette vraie limite. Voir le CHANGELOG pour le détail de cette bascule.

## Ce que fait l'outil

1. Tu lui donnes un `.3mf` colorisé (sortie de ColoriseurSTL, ou n'importe quel projet Bambu
   Studio avec des couleurs peintes dessus).
2. Tu choisis un trio de primaires — un des deux trios prédéfinis (Pastel / Néon), un de tes trios
   personnalisés, ou un trio créé à partir de ton propre stock de couleurs.
3. Il calcule automatiquement le meilleur dosage (espace de couleur Lab, pas du RGB moyenné
   naïvement) pour chacune des couleurs détectées, et fusionne celles qui ressortent avec un
   dosage rigoureusement identique.
4. Il ressort un `.3mf` où tout est déjà mélangé, prêt à ouvrir et trancher directement dans Bambu
   Studio.

## Fonctionnalités

**Trios de primaires**
- Trios prédéfinis (Pastel, Néon) + trios personnalisés illimités, avec éditeur (code hex tapable
  ou sélecteur Windows, case "Verrou" par couleur, suggestion automatique de la 3ᵉ couleur)
- Dupliquer un trio existant comme point de départ d'une variante
- Export/Import des trios personnalisés en JSON (transfert entre postes, sauvegarde à part)
- Trios "favoris" (étoile) qui remontent en haut du menu, avec un compteur "utilisé X fois" basé
  sur l'historique pour savoir objectivement lesquels favoriser
- Pastilles de couleur directement dans le menu déroulant, pour reconnaître un trio sans deviner

**Stock de couleurs personnelles**
- Liste de couleurs indépendante des trios ("Gérer mes couleurs"), qui sert de réservoir pour se
  faire suggérer automatiquement les meilleurs trios possibles à partir de son propre stock
- Avertissement si une couleur ajoutée/modifiée est quasi-identique à une déjà en stock
- Sélection multiple (Ctrl/Shift-clic, "Tout sélectionner", touche Suppr) partout où ça a du sens :
  couleurs, trios personnalisés, suggestions de trios
- Supprimer une couleur supprime automatiquement les trios personnalisés qui s'en servaient
- Un seul niveau d'annulation ("Annuler la dernière suppression") pour les couleurs et les trios

**Couverture et fiabilité**
- Vérification automatique de la couverture du fichier **avant de lancer un mélange pour de vrai**
  (avertit si le trio choisi va mal rendre certaines couleurs), en plus d'un contrôle à la demande
  avec rapport exporté en `.txt`
- Comparaison de deux trios sur le même fichier
- Rappel "déjà mélangé le [date] avec le trio [nom]" si le même fichier est repassé par erreur

**Confort**
- Traitement en lot (dossier entier ou sélection de fichiers), avec confirmation listant les
  fichiers déjà traités (décochés par défaut)
- Historique de tous les mélanges effectués
- Mémorise le dernier fichier `.3mf` utilisé et le recharge seul au démarrage
- Aperçu avant/après en image 3D statique (projection isométrique maison, pas un vrai visualiseur)
- Mode "test rapide" pour essayer un trio sans rien enregistrer sur le disque
- Bouton "Ouvrir le dossier contenant" pour retrouver le fichier généré sans fouiller
  l'explorateur Windows

## Installation / utilisation

- Nécessite Windows + PowerShell (inclus par défaut) + Bambu Studio pour trancher le résultat.
- Double-clic sur `Lancer-Melange-Couleurs.vbs` pour ouvrir l'interface sans fenêtre de console
  visible, ou lancer directement `Melange-Couleurs-GUI.ps1` depuis PowerShell.
- Les données personnelles (couleurs, trios, favoris, dernier fichier, historique) sont stockées
  dans de petits fichiers JSON/log à côté du script, créés automatiquement au premier usage — voir
  `.gitignore`, ils ne sont pas versionnés.

## Précaution

**Le dosage calculé est une approximation maison, pas garantie identique à celle de Bambu
Studio** — à vérifier avant de lancer une pièce de plusieurs heures d'impression, pas après.

## Historique

Voir [CHANGELOG.md](CHANGELOG.md) pour le détail du développement, session par session.
