' Lance l'interface graphique sans aucune fenetre de console visible.
' Le "0" dans Run masque deja completement la fenetre PowerShell sous-jacente - pas besoin
' de "-WindowStyle Hidden" en plus sur powershell.exe lui-meme.
'
' 12/10/2026 : "-WindowStyle Hidden" RETIRE de la ligne de commande powershell.exe. Suspecte
' d'etre la cause du bug d'affichage signale par Tomyn (fenetres qui n'affichent qu'une partie
' de leur contenu, quel que soit le controle WinForms utilise, sur plusieurs versions de code
' tres differentes) - "-WindowStyle Hidden" est connu pour perturber le rendu de fenetres
' WinForms creees ensuite par le meme processus PowerShell, meme si la console elle-meme reste
' bien cachee par le "0" ci-dessous (redondant avec "-WindowStyle Hidden", donc rien n'est perdu
' en le retirant - la fenetre PowerShell reste masquee de la meme facon).
' -ExecutionPolicy Bypass evite toute configuration manuelle, pour cette seule execution (rien
' n'est modifie de facon permanente sur la machine).

Dim objFSO, objShell, strDossier, strCheminScript, strCommande

Set objFSO = CreateObject("Scripting.FileSystemObject")
strDossier = objFSO.GetParentFolderName(WScript.ScriptFullName)
strCheminScript = strDossier & "\Melange-Couleurs-GUI.ps1"

Set objShell = CreateObject("WScript.Shell")
strCommande = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & strCheminScript & """"
objShell.Run strCommande, 0, False
