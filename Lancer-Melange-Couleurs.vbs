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

' 16/10/2026 : accepte maintenant un argument optionnel - le chemin d'un .3mf a charger
' automatiquement au demarrage (passerelle depuis Coloriser-STL, bouton "Analyser les couleurs"
' sur un resultat de galerie). Sans argument, comportement inchange (double-clic normal).

' 22/10/2026, suite au bug "ca prend 20-30 minutes" sur "Suggerer un trio pour ce fichier..." -
' meme apres avoir reduit le nombre de combinaisons testees (voir le commentaire dans
' Obtenir-MeilleureComboDepuisCouleursPourFichier), l'ecart entre mes estimations (quelques
' secondes a quelques minutes, testees sous PowerShell 7 "pwsh") et le temps reel chez Tomyn
' (20-30 minutes) restait trop grand pour s'expliquer par le nombre de combinaisons seul. Ce
' lanceur demarrait toujours avec "powershell.exe" - Windows PowerShell 5.1, le moteur historique
' integre a Windows, connu pour etre nettement plus lent que PowerShell 7 sur du code avec
' beaucoup de petits appels de fonction/calculs numeriques repetes (exactement le profil de
' Trouver-MeilleurDosage/Convertir-RGBVersLab, appeles des centaines de milliers de fois pour une
' seule suggestion). On essaie maintenant d'abord "pwsh.exe" (PowerShell 7, si installe) et on ne
' retombe sur l'ancien "powershell.exe" que s'il est absent - aucun risque de casser quoi que ce
' soit chez quelqu'un qui n'a pas PowerShell 7, juste un gain potentiel important chez qui l'a (ou
' l'installe).
Dim objFSO, objShell, strDossier, strCheminScript, strCommande, strFichierInitial, strMoteur

Set objFSO = CreateObject("Scripting.FileSystemObject")
strDossier = objFSO.GetParentFolderName(WScript.ScriptFullName)
strCheminScript = strDossier & "\Melange-Couleurs-GUI.ps1"

Set objShell = CreateObject("WScript.Shell")

' Detection de pwsh.exe (PowerShell 7) sans fenetre visible et sans arreter le script si absent -
' "where.exe" renvoie un code de sortie non nul (capte via On Error Resume Next + Err.Clear) quand
' la commande n'est pas trouvee, plutot que de lever une exception VBScript.
strMoteur = "powershell.exe"
On Error Resume Next
Dim objExec
Set objExec = objShell.Exec("where.exe pwsh.exe")
If Err.Number = 0 Then
    Do While objExec.Status = 0
        WScript.Sleep 50
    Loop
    If objExec.ExitCode = 0 Then
        strMoteur = "pwsh.exe"
    End If
End If
Err.Clear
On Error Goto 0

strCommande = strMoteur & " -NoProfile -ExecutionPolicy Bypass -File """ & strCheminScript & """"
If WScript.Arguments.Count > 0 Then
    strFichierInitial = WScript.Arguments(0)
    strCommande = strCommande & " -FichierInitial """ & strFichierInitial & """"
End If
objShell.Run strCommande, 0, False
