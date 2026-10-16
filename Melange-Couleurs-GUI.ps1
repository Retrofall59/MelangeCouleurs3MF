#requires -Version 5.1
<#
=================================================================================================
 Melange-Couleurs-GUI.ps1
=================================================================================================
Meme principe que la version console (Melange-Couleurs-3MF.ps1), mais avec une interface
graphique reprenant le meme habillage que Coloriser-STL-GUI (10/10/2026, demande de Tomyn : "tu
utilises le meme la meme interface graphique que l'autre... tu prends le meme interface graphique
a part que c'est un autre projet"). Projet totalement separe de Coloriser-STL (pas de dependance
de code entre les deux), juste le meme theme visuel copie/colle pour que ca se ressemble.

Prend en entree un .3mf colorise (sortie de Coloriser-STL, ou n'importe quel projet Bambu Studio
avec des couleurs peintes dessus), calcule pour chaque couleur detectee le meilleur dosage possible
avec un trio de 3 primaires au choix (CMY ou RYB) - passe de 4 a 3 primaires le 11/10/2026, Tomyn
ayant verifie que Bambu Studio ne melange que 3 couleurs a la fois - et ressort un .3mf ou tout est
deja melange, pret a ouvrir dans Bambu Studio.

RESERVES IMPORTANTES (les memes que la version console - voir le README du dossier pour le detail) :
- Le format d'ecriture du melange dans le fichier a ete retrouve en inspectant un vrai fichier
  .3mf exporte par Tomyn depuis Bambu Studio, donc ce format-la est fiable.
- La formule de calcul du dosage est une approximation maison (lumiere lineaire + comparaison Lab),
  PAS celle de Bambu Studio - en comparant plusieurs captures d'ecran envoyees par Tomyn, aucune
  formule RGB simple testee ne retombe sur ce que Bambu Studio affiche. Donc le dosage calcule ici
  peut differer de celui de Bambu Studio, sans certitude sur lequel est le plus fidele a la realite
  imprimee.
- NON TESTE sur un vrai Bambu Studio (aucun Windows disponible ici). Le fichier d'exemple utilise
  pour retrouver le format etait un test manuel a 3 couleurs de Tomyn, pas un vrai export Meshy a
  16 couleurs.
=================================================================================================
#>

# -FichierInitial (16/10/2026, passerelle depuis Coloriser-STL : "Analyser les couleurs" sur un
# resultat de galerie) - chemin d'un .3mf a charger automatiquement au demarrage, a la place du
# dernier fichier utilise, pour eviter a Tomyn de devoir rouvrir/re-selectionner a la main le
# fichier qu'il vient juste de coloriser dans l'autre outil. Facultatif : sans cet argument,
# comportement inchange (reprend le dernier fichier utilise comme avant).
param(
    [string]$FichierInitial
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

# 12/10/2026 : piste trouvee pour le bug "du contenu existe (confirme par compteur) mais seule une
# partie se peint a l'ecran, le reste de la fenetre reste un vide etire" signale par Tomyn sur
# plusieurs fenetres differentes (pastilles seules, texte manquant, puis seulement 2 lignes sur 4
# dans un ListBox dont le compteur dit pourtant 4) : powershell.exe n'est PAS declare "DPI-aware"
# par defaut. Si l'affichage Windows de Tomyn est en zoom >100% (125%/150%, tres courant), Windows
# AGRANDIT VISUELLEMENT toute la fenetre en l'etirant (bitmap stretching) alors que WinForms continue
# de calculer/peindre en interne a la taille NON agrandie - donc seule une fraction (haut-gauche) du
# contenu reel est peinte, le reste de la zone visuellement agrandie est du vide. Ca expliquerait
# TOUS les symptomes vus aujourd'hui, pas juste celui du ListBox. Fix : declarer le process DPI-aware
# AVANT de creer le moindre Form, pour que Windows n'etire plus rien et laisse WinForms dessiner a la
# vraie resolution. SetHighDpiMode existe depuis .NET Framework 4.7 - si absent (version plus
# ancienne), on retombe sur l'API Win32 SetProcessDPIAware (DPI-aware "system", moins fin mais evite
# le bitmap stretching, ce qui est le vrai probleme ici).
try {
    [void][System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2)
} catch {
    try {
        Add-Type -Name NativeDpi -Namespace MelangeCouleurs -MemberDefinition '
            [System.Runtime.InteropServices.DllImport("user32.dll")]
            public static extern bool SetProcessDPIAware();
        '
        [void][MelangeCouleurs.NativeDpi]::SetProcessDPIAware()
    } catch { }
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================== THEME (identique a Coloriser-STL-GUI) ==============================

$THEME = @{
    FondApp            = [System.Drawing.Color]::FromArgb(0xEE, 0xF1, 0xF3)
    FondBanniere       = [System.Drawing.Color]::FromArgb(0x45, 0x27, 0xA0)
    Surface            = [System.Drawing.Color]::White
    AccentPrincipal    = [System.Drawing.Color]::FromArgb(0x7C, 0x4D, 0xFF)
    AccentPrincipalTxt = [System.Drawing.Color]::White
    AccentDanger       = [System.Drawing.Color]::FromArgb(0xD3, 0x2F, 0x2F)
    AccentChaud        = [System.Drawing.Color]::FromArgb(0xFF, 0x5A, 0x1F)
    Texte              = [System.Drawing.Color]::FromArgb(0x1A, 0x1A, 0x1A)
    TexteSecondaire    = [System.Drawing.Color]::FromArgb(0x5C, 0x5C, 0x5C)
    Bordure            = [System.Drawing.Color]::FromArgb(0xD8, 0xDA, 0xDD)
    HauteurBanniere    = 56
}

function Rendre-BoutonPlat($bouton, [string]$role = "secondaire") {
    $bouton.FlatStyle = "Flat"
    $bouton.Cursor = "Hand"
    $bouton.FlatAppearance.BorderSize = 1
    switch ($role) {
        "principal" {
            $bouton.BackColor = $THEME.AccentPrincipal
            $bouton.ForeColor = $THEME.AccentPrincipalTxt
            $bouton.FlatAppearance.BorderColor = $THEME.AccentPrincipal
            $bouton.FlatAppearance.MouseOverBackColor = $THEME.FondBanniere
            $bouton.Font = New-Object System.Drawing.Font($bouton.Font.FontFamily, $bouton.Font.Size, [System.Drawing.FontStyle]::Bold)
        }
        "chaud" {
            $bouton.BackColor = $THEME.AccentChaud
            $bouton.ForeColor = [System.Drawing.Color]::White
            $bouton.FlatAppearance.BorderColor = $THEME.AccentChaud
            $bouton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xCC, 0x48, 0x18)
        }
        "danger" {
            $bouton.BackColor = $THEME.Surface
            $bouton.ForeColor = $THEME.AccentDanger
            $bouton.FlatAppearance.BorderColor = $THEME.AccentDanger
            $bouton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xFD, 0xEC, 0xEC)
        }
        "discret" {
            $bouton.BackColor = $THEME.FondApp
            $bouton.ForeColor = $THEME.TexteSecondaire
            $bouton.FlatAppearance.BorderSize = 0
            $bouton.FlatAppearance.MouseOverBackColor = $THEME.Bordure
        }
        default {
            $bouton.BackColor = $THEME.Surface
            $bouton.ForeColor = $THEME.AccentPrincipal
            $bouton.FlatAppearance.BorderColor = $THEME.AccentPrincipal
            $bouton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(0xF1, 0xEC, 0xFF)
        }
    }
}

function Rendre-ComboBoxPlate($combo, [bool]$avecPastillesTrio = $false) {
    $combo.BackColor = $THEME.Surface
    $combo.ForeColor = $THEME.Texte
    $combo.DrawMode = "OwnerDrawFixed"
    $combo.ItemHeight = 20
    $combo.Add_DrawItem({
        param($sender, $e)
        $estZoneAffichage = $e.Index -lt 0
        $texte = if ($estZoneAffichage) { $sender.Text } else { $sender.Items[$e.Index].ToString() }
        $survol = (-not $estZoneAffichage) -and (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
        $fond = if ($survol) { $THEME.AccentPrincipal } else { $THEME.Surface }
        $couleurTexte = if ($survol) { [System.Drawing.Color]::White } else { $THEME.Texte }
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($fond)), $e.Bounds)
        $decalageTexte = 4
        # 12/10/2026, idee d'amelioration validee "vaut le coup" : petites pastilles de couleur
        # directement dans le menu "Trio de primaires a utiliser" (texte + liste deroulante), pour
        # voir les 3 couleurs d'un trio sans cliquer "Gerer mes trios...". $avecPastillesTrio reste
        # a $false par defaut pour ne rien changer aux autres ComboBox eventuelles qui reutiliseraient
        # cette meme fonction plus tard. $TRIOS est un Hashtable mute EN PLACE (jamais reassigne
        # ailleurs dans le fichier), donc la reference capturee ici par GetNewClosure() reste valide
        # meme apres l'ajout/suppression d'un trio personnalise - meme raisonnement deja applique a
        # $THEME ci-dessous, qui fonctionne sans souci depuis le debut dans cette meme fonction.
        if ($avecPastillesTrio -and -not $estZoneAffichage -and $TRIOS.ContainsKey($texte)) {
            $trioAffiche = @($TRIOS[$texte])
            $taillePastille = $e.Bounds.Height - 6
            $xPastille = $e.Bounds.X + 4
            $yPastille = $e.Bounds.Y + 3
            foreach ($couleurTrio in $trioAffiche) {
                try {
                    $couleurGdi = [System.Drawing.ColorTranslator]::FromHtml($couleurTrio.Hex)
                    $pinceauPastille = New-Object System.Drawing.SolidBrush($couleurGdi)
                    $e.Graphics.FillRectangle($pinceauPastille, $xPastille, $yPastille, $taillePastille, $taillePastille)
                    $e.Graphics.DrawRectangle([System.Drawing.Pens]::Gray, $xPastille, $yPastille, $taillePastille, $taillePastille)
                } catch { }
                $xPastille += $taillePastille + 2
            }
            $decalageTexte = ($xPastille - $e.Bounds.X) + 4
        }
        # 12/10/2026, idee d'amelioration validee "vaut le coup" : marque les trios favoris d'une
        # "*" devant le nom, dans le texte ET dans la liste deroulante - marqueur ASCII simple (pas
        # un caractere etoile Unicode) pour rester dans le meme esprit que le reste du fichier,
        # ecrit volontairement sans accents pour eviter tout souci d'encodage cote Windows.
        # $script:TriosFavoris est une List[string] mutee EN PLACE (Add/Remove, jamais reassignee),
        # donc la reference capturee ici par GetNewClosure() reste valide meme apres un basculement
        # favori/non-favori - meme raisonnement que $TRIOS juste au-dessus.
        $texteAffiche = $texte
        if ($avecPastillesTrio -and $texte -and ($script:TriosFavoris -contains $texte)) {
            $texteAffiche = "* $texte"
        }
        $zoneTexte = New-Object System.Drawing.Rectangle(($e.Bounds.X + $decalageTexte), $e.Bounds.Y, ($e.Bounds.Width - $decalageTexte), $e.Bounds.Height)
        $drapeaux = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $texteAffiche, $sender.Font, $zoneTexte, $couleurTexte, $drapeaux)
        if (-not $estZoneAffichage) { $e.DrawFocusRectangle() }
    }.GetNewClosure())
}

function Creer-ImageSpool([int]$taille, [System.Drawing.Color]$couleurFond) {
    $bmp = New-Object System.Drawing.Bitmap($taille, $taille)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $pinceauAccent = New-Object System.Drawing.SolidBrush($THEME.AccentPrincipal)
    $pinceauFond = New-Object System.Drawing.SolidBrush($couleurFond)
    $stylo = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, [System.Drawing.Color]::White), [Math]::Max(1, $taille * 0.03))
    $marge = [int]($taille * 0.06)
    $g.FillEllipse($pinceauAccent, $marge, $marge, $taille - 2 * $marge, $taille - 2 * $marge)
    for ($i = 0; $i -lt 3; $i++) {
        $r = [int]($taille * (0.30 + $i * 0.11))
        $d = ($taille - $r) / 2.0
        $g.DrawArc($stylo, $d, $d, $r, $r, 20, 220)
    }
    $trou = [int]($taille * 0.30)
    $d2 = ($taille - $trou) / 2.0
    $g.FillEllipse($pinceauFond, $d2, $d2, $trou, $trou)
    $g.Dispose()
    return $bmp
}

function Afficher-Boite([string]$message, [string]$titre = "", [string]$boutons = "OK", [string]$icone = "Info") {
    $fenetre = New-Object System.Windows.Forms.Form
    $fenetre.FormBorderStyle = "None"
    $fenetre.StartPosition = "CenterParent"
    $fenetre.BackColor = $THEME.Surface
    $fenetre.Width = 420
    $fenetre.KeyPreview = $true

    $couleurBandeau = switch ($icone) {
        "Error" { $THEME.AccentDanger }
        "Warning" { $THEME.AccentChaud }
        "Question" { $THEME.AccentPrincipal }
        default { $THEME.AccentPrincipal }
    }

    $bandeau = New-Object System.Windows.Forms.Panel
    $bandeau.Dock = "Top"
    $bandeau.Height = 40
    $bandeau.BackColor = $couleurBandeau
    $fenetre.Controls.Add($bandeau)

    $labelTitre = New-Object System.Windows.Forms.Label
    $labelTitre.Text = $titre
    $labelTitre.ForeColor = [System.Drawing.Color]::White
    $labelTitre.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $labelTitre.Dock = "Fill"
    $labelTitre.TextAlign = "MiddleLeft"
    $labelTitre.Padding = New-Object System.Windows.Forms.Padding(15, 0, 0, 0)
    $bandeau.Controls.Add($labelTitre)

    $labelMessage = New-Object System.Windows.Forms.Label
    $labelMessage.Text = $message
    $labelMessage.ForeColor = $THEME.Texte
    $labelMessage.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $labelMessage.Location = New-Object System.Drawing.Point(18, 55)
    $labelMessage.MaximumSize = New-Object System.Drawing.Size(384, 0)
    $labelMessage.AutoSize = $true
    $fenetre.Controls.Add($labelMessage)

    $yBoutons = $labelMessage.Bottom + 22
    $largeurBouton = 160
    $hauteurBouton = 34

    # Mode "YesNo" (10/10/2026, ajoute pour la confirmation de suppression d'un trio personnalise)
    # - deux boutons Oui/Non cote a cote plutot que le bouton OK unique d'origine ; tous les appels
    # existants passent "OK" (valeur par defaut du parametre) et ne sont donc pas affectes.
    if ($boutons -eq "YesNo") {
        $btnNon = New-Object System.Windows.Forms.Button
        $btnNon.Text = "Non"
        $btnNon.Size = New-Object System.Drawing.Size($largeurBouton, $hauteurBouton)
        $btnNon.Location = New-Object System.Drawing.Point((420 - $largeurBouton - 18), $yBoutons)
        $btnNon.DialogResult = "No"
        Rendre-BoutonPlat $btnNon "discret"
        $fenetre.Controls.Add($btnNon)

        $btnOui = New-Object System.Windows.Forms.Button
        $btnOui.Text = "Oui"
        $btnOui.Size = New-Object System.Drawing.Size($largeurBouton, $hauteurBouton)
        $btnOui.Location = New-Object System.Drawing.Point((420 - (2 * $largeurBouton) - 28), $yBoutons)
        $btnOui.DialogResult = "Yes"
        Rendre-BoutonPlat $btnOui "danger"
        $fenetre.Controls.Add($btnOui)

        $fenetre.AcceptButton = $btnNon
        $fenetre.CancelButton = $btnNon
        $fenetre.Width = [Math]::Max(420, (2 * $largeurBouton) + 46)
        $fenetre.Height = $yBoutons + $hauteurBouton + 28
        return $fenetre.ShowDialog($form)
    }

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Size = New-Object System.Drawing.Size($largeurBouton, $hauteurBouton)
    $btnOk.Location = New-Object System.Drawing.Point((420 - $largeurBouton - 18), $yBoutons)
    $btnOk.DialogResult = "OK"
    $roleBoutonOk = if ($icone -eq "Error") { "danger" } else { "principal" }
    Rendre-BoutonPlat $btnOk $roleBoutonOk
    $fenetre.Controls.Add($btnOk)
    $fenetre.AcceptButton = $btnOk
    $fenetre.CancelButton = $btnOk

    $fenetre.Height = $yBoutons + $hauteurBouton + 28
    return $fenetre.ShowDialog($form)
}

# ============================== COULEUR : MEME MOTEUR QUE LA VERSION CONSOLE ==============================

function ConvertTo-Lineaire([double]$octetSRGB) {
    $c = $octetSRGB / 255.0
    if ($c -le 0.04045) { return $c / 12.92 }
    return [Math]::Pow((($c + 0.055) / 1.055), 2.4)
}

function ConvertTo-OctetSRGB([double]$lineaire) {
    if ($lineaire -lt 0) { $lineaire = 0 }
    if ($lineaire -gt 1) { $lineaire = 1 }
    $c = if ($lineaire -le 0.0031308) { $lineaire * 12.92 } else { 1.055 * [Math]::Pow($lineaire, 1 / 2.4) - 0.055 }
    $octet = [Math]::Round($c * 255)
    if ($octet -lt 0) { $octet = 0 }
    if ($octet -gt 255) { $octet = 255 }
    return [int]$octet
}

function Obtenir-RGBDepuisHex([string]$hex) {
    $h = $hex.TrimStart('#')
    return @{
        R = [Convert]::ToInt32($h.Substring(0, 2), 16)
        G = [Convert]::ToInt32($h.Substring(2, 2), 16)
        B = [Convert]::ToInt32($h.Substring(4, 2), 16)
    }
}

function Obtenir-HexDepuisRGB([int]$r, [int]$g, [int]$b) {
    return "#{0:X2}{1:X2}{2:X2}" -f $r, $g, $b
}

function Convertir-RGBVersLab([double]$r, [double]$g, [double]$b) {
    $rl = ConvertTo-Lineaire $r
    $gl = ConvertTo-Lineaire $g
    $bl = ConvertTo-Lineaire $b
    $x = $rl * 0.4124564 + $gl * 0.3575761 + $bl * 0.1804375
    $y = $rl * 0.2126729 + $gl * 0.7151522 + $bl * 0.0721750
    $z = $rl * 0.0193339 + $gl * 0.1191920 + $bl * 0.9503041
    $xn = $x / 0.95047
    $yn = $y / 1.00000
    $zn = $z / 1.08883
    $f = {
        param($t)
        if ($t -gt 0.008856) { return [Math]::Pow($t, 1.0 / 3.0) }
        return (7.787 * $t) + (16.0 / 116.0)
    }
    $fx = & $f $xn
    $fy = & $f $yn
    $fz = & $f $zn
    return @{ L = (116 * $fy) - 16; a = 500 * ($fx - $fy); b = 200 * ($fy - $fz) }
}

function Obtenir-DistanceLab($lab1, $lab2) {
    $dl = $lab1.L - $lab2.L
    $da = $lab1.a - $lab2.a
    $db = $lab1.b - $lab2.b
    return [Math]::Sqrt($dl * $dl + $da * $da + $db * $db)
}

function Melanger-EnLumiereLineaire($primairesRGB, [double[]]$ratios) {
    $rl = 0.0; $gl = 0.0; $bl = 0.0
    for ($i = 0; $i -lt $primairesRGB.Count; $i++) {
        $poids = $ratios[$i] / 100.0
        if ($poids -le 0) { continue }
        $rl += $poids * (ConvertTo-Lineaire $primairesRGB[$i].R)
        $gl += $poids * (ConvertTo-Lineaire $primairesRGB[$i].G)
        $bl += $poids * (ConvertTo-Lineaire $primairesRGB[$i].B)
    }
    return @{ R = ConvertTo-OctetSRGB $rl; G = ConvertTo-OctetSRGB $gl; B = ConvertTo-OctetSRGB $bl }
}

function Trouver-MeilleurDosage($cibleRGB, $primairesRGB, [int]$pas) {
    $labCible = Convertir-RGBVersLab $cibleRGB.R $cibleRGB.G $cibleRGB.B
    $meilleureDistance = [double]::MaxValue
    $meilleurDosage = @(100, 0, 0)
    $meilleurResultat = $primairesRGB[0]
    # Trio = 3 primaires (11/10/2026, Tomyn a verifie que le melange de couleurs dans Bambu Studio
    # ne prend que 3 emplacements, pas 4 - l'outil est passe de "quatuor" a "trio" partout). Avec
    # seulement 3 inconnues dont la somme fait 100, 2 boucles imbriquees suffisent (la 3e se deduit
    # par soustraction), contre 3 boucles avant pour 4 primaires.
    for ($a = 0; $a -le 100; $a += $pas) {
        for ($b = 0; $b -le (100 - $a); $b += $pas) {
            $c = 100 - $a - $b
            $dosage = @($a, $b, $c)
            $resultat = Melanger-EnLumiereLineaire $primairesRGB $dosage
            $labResultat = Convertir-RGBVersLab $resultat.R $resultat.G $resultat.B
            $distance = Obtenir-DistanceLab $labCible $labResultat
            if ($distance -lt $meilleureDistance) {
                $meilleureDistance = $distance
                $meilleurDosage = $dosage
                $meilleurResultat = $resultat
            }
        }
    }
    return @{ Dosage = $meilleurDosage; Resultat = $meilleurResultat; Distance = $meilleureDistance }
}

# Regroupement automatique des couleurs detectees en au plus K "melanges" (10/10/2026, demande
# par Tomyn) : quand le modele a plus de couleurs que de melanges souhaites, les couleurs les plus
# proches visuellement (distance Lab) sont regroupees et traitees comme une seule, avec un dosage
# calcule sur leur moyenne plutot qu'individuellement. Deterministe (pas de hasard) pour que le
# meme fichier donne toujours le meme regroupement : les centres de depart sont choisis par
# "farthest-point sampling" (toujours la couleur la plus eloignee des centres deja choisis), puis
# quelques passes de reajustement classiques (type k-means), le tout en reutilisant les fonctions
# de distance/melange deja ecrites plus haut plutot que d'en refaire une version a part.
function Regrouper-CouleursParProximite([string[]]$couleursHex, [int]$k) {
    $n = $couleursHex.Count
    $rgb = @($couleursHex | ForEach-Object { Obtenir-RGBDepuisHex $_ })
    $lab = @($rgb | ForEach-Object { Convertir-RGBVersLab $_.R $_.G $_.B })

    if ($k -ge $n) {
        # Pas de regroupement necessaire : chaque couleur reste son propre groupe (comportement
        # d'origine, 1 melange par couleur detectee).
        return [int[]]@(0..($n - 1))
    }
    if ($k -le 1) {
        return [int[]]@(0..($n - 1) | ForEach-Object { 0 })
    }

    $indicesCentres = New-Object System.Collections.Generic.List[int]
    $indicesCentres.Add(0)
    $distanceAuPlusProcheCentre = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $distanceAuPlusProcheCentre[$i] = Obtenir-DistanceLab $lab[$i] $lab[0] }
    while ($indicesCentres.Count -lt $k) {
        $meilleurIndex = -1
        $meilleureDistance = -1
        for ($i = 0; $i -lt $n; $i++) {
            if ($distanceAuPlusProcheCentre[$i] -gt $meilleureDistance) {
                $meilleureDistance = $distanceAuPlusProcheCentre[$i]
                $meilleurIndex = $i
            }
        }
        $indicesCentres.Add($meilleurIndex)
        for ($i = 0; $i -lt $n; $i++) {
            $d = Obtenir-DistanceLab $lab[$i] $lab[$meilleurIndex]
            if ($d -lt $distanceAuPlusProcheCentre[$i]) { $distanceAuPlusProcheCentre[$i] = $d }
        }
    }
    $centresLab = @($indicesCentres | ForEach-Object { $lab[$_] })

    $groupeDe = New-Object int[] $n
    for ($iter = 0; $iter -lt 8; $iter++) {
        $changement = $false
        for ($i = 0; $i -lt $n; $i++) {
            $meilleurGroupe = 0
            $meilleureDistance = [double]::MaxValue
            for ($g = 0; $g -lt $k; $g++) {
                $d = Obtenir-DistanceLab $lab[$i] $centresLab[$g]
                if ($d -lt $meilleureDistance) { $meilleureDistance = $d; $meilleurGroupe = $g }
            }
            if ($groupeDe[$i] -ne $meilleurGroupe) { $changement = $true }
            $groupeDe[$i] = $meilleurGroupe
        }

        # Groupe vide ? On lui affecte la couleur la moins bien representee par son groupe actuel
        # (la plus eloignee de son propre centre) plutot que de laisser un emplacement de melange
        # totalement inutilise.
        for ($g = 0; $g -lt $k; $g++) {
            if (-not (@($groupeDe) -contains $g)) {
                $pireIndex = -1; $pireDistance = -1
                for ($i = 0; $i -lt $n; $i++) {
                    $d = Obtenir-DistanceLab $lab[$i] $centresLab[$groupeDe[$i]]
                    if ($d -gt $pireDistance) { $pireDistance = $d; $pireIndex = $i }
                }
                if ($pireIndex -ge 0) { $groupeDe[$pireIndex] = $g; $changement = $true }
            }
        }

        if (-not $changement -and $iter -gt 0) { break }

        for ($g = 0; $g -lt $k; $g++) {
            $membres = @(0..($n - 1) | Where-Object { $groupeDe[$_] -eq $g })
            if ($membres.Count -eq 0) { continue }
            $rgbMembres = @($membres | ForEach-Object { $rgb[$_] })
            $ratiosEgaux = @($membres | ForEach-Object { 100.0 / $membres.Count })
            $centreRGB = Melanger-EnLumiereLineaire $rgbMembres $ratiosEgaux
            $centresLab[$g] = Convertir-RGBVersLab $centreRGB.R $centreRGB.G $centreRGB.B
        }
    }

    return $groupeDe
}

$TRIOS = @{
    # 11/10/2026, Tomyn a verifie dans Bambu Studio que le melange de couleurs ne prend que 3
    # emplacements, pas 4 - l'outil entier est passe de "quatuor" (4 primaires) a "trio" (3
    # primaires).
    # 12/10/2026, Tomyn : les presets CMY et RYB ci-dessous (qui existaient a ce stade) ont ete
    # retires a sa demande - il n'a pas ces couleurs precises en stock, et ne veut plus qu'ils
    # "perturbent" le menu ni les boutons de suggestion : il veut que l'outil s'appuie uniquement
    # sur ses propres trios personnalises et sur les couleurs qu'il a reellement ("Gerer mes
    # couleurs..."). Pastel/Neon restent (jamais utilises non plus, mais deja exclus des
    # suggestions via $script:NomsPresetsExclusDeLaSuggestion plus bas - pas demande de les
    # supprimer du menu, seulement CMY/RYB).
    "Pastel" = @(
        @{ Nom = "Rose pastel";   Hex = "#E05A8C" }
        @{ Nom = "Jaune pastel";  Hex = "#E0B65A" }
        @{ Nom = "Bleu pastel";   Hex = "#5A8EE0" }
    )
    "Neon" = @(
        @{ Nom = "Rose neon";  Hex = "#FF6EC7" }
        @{ Nom = "Jaune neon"; Hex = "#CCFF00" }
        @{ Nom = "Cyan neon";  Hex = "#00F0FF" }
    )
}

# Trios personnalises (10/10/2026, Tomyn : "toutes stp"; passe de 4 a 3 couleurs le 11/10/2026,
# Tomyn ayant verifie que Bambu Studio ne melange que 3 couleurs a la fois) - en plus des quatre
# trios predefinis ci-dessus, permet de creer ses propres combinaisons de 3 couleurs primaires et de
# les retrouver aux lancements suivants. Un trio (predefini ou personnalise) est toujours un tableau
# de 3 @{Nom; Hex} - le reste du script (Traiter-Fichier3MF, le lot, etc.) ne fait AUCUNE difference
# entre les deux une fois que c'est dans $TRIOS, donc rien d'autre a adapter ailleurs dans le
# fichier. Stockes dans un troisieme fichier JSON, meme principe que les deux precedents (reference
# d'angle / angle par fichier) : lu au demarrage, ecrit a chaque modification, jamais bloquant si
# l'ecriture echoue.
function Obtenir-CheminConfigTrios {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "trios-personnalises.json" } else { Join-Path (Get-Location) "trios-personnalises.json" }
}

function Charger-TriosPersonnalises {
    $chemin = Obtenir-CheminConfigTrios
    if (-not (Test-Path $chemin)) { return @{} }
    try {
        $contenu = Get-Content -Path $chemin -Raw -ErrorAction Stop
        $objet = $contenu | ConvertFrom-Json -ErrorAction Stop
        $table = @{}
        foreach ($prop in $objet.PSObject.Properties) {
            $table[$prop.Name] = @($prop.Value | ForEach-Object { @{ Nom = $_.Nom; Hex = $_.Hex } })
        }
        return $table
    } catch { return @{} }
}

function Sauvegarder-TriosPersonnalises($table) {
    $chemin = Obtenir-CheminConfigTrios
    try {
        if ($table.Count -eq 0) {
            if (Test-Path $chemin) { Remove-Item -Path $chemin -Force -ErrorAction Stop }
        } else {
            ($table | ConvertTo-Json -Depth 5) | Set-Content -Path $chemin -Encoding UTF8 -ErrorAction Stop
        }
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer les trios personnalises sur le disque : $_)"
    }
}

# Couleurs individuelles ("mon stock", 12/10/2026, Tomyn : reprend a la main l'exercice qu'on a
# fait ensemble en conversation - lister ses couleurs de filament une par une puis se faire
# suggerer de bons trios dedans) - contrairement a $TRIOS (toujours des GROUPES de 3 deja formes),
# ceci est une simple liste plate de @{Nom; Hex}, dans laquelle "Suggerer des trios depuis mes
# couleurs..." (voir plus bas) teste ensuite toutes les combinaisons de 3 possibles. Meme principe
# de fichier JSON a cote du script que trios-personnalises.json ci-dessus, memes garanties
# (jamais bloquant si l'ecriture echoue).
function Obtenir-CheminConfigCouleurs {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "couleurs-personnalisees.json" } else { Join-Path (Get-Location) "couleurs-personnalisees.json" }
}

function Charger-MesCouleurs {
    $chemin = Obtenir-CheminConfigCouleurs
    if (-not (Test-Path $chemin)) { return @() }
    try {
        $objet = Get-Content -Path $chemin -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        # 12/10/2026 : filtre les entrees sans Nom ou sans Hex (Tomyn a vu un tiret "-" tout seul
        # dans la liste "Gerer mes couleurs..." - une entree vide a du se glisser sur le disque
        # pendant les tests du bug Ajouter avant sa correction) - on ne les recharge plus, et elles
        # disparaissent definitivement du fichier des la prochaine sauvegarde (Ajouter/Modifier/
        # Supprimer, qui reecrit toujours la liste complete).
        return @($objet | ForEach-Object { @{ Nom = $_.Nom; Hex = $_.Hex } } | Where-Object { $_.Nom -and $_.Hex })
    } catch { return @() }
}

function Sauvegarder-MesCouleurs($liste) {
    $chemin = Obtenir-CheminConfigCouleurs
    try {
        if ($liste.Count -eq 0) {
            if (Test-Path $chemin) { Remove-Item -Path $chemin -Force -ErrorAction Stop }
        } else {
            ($liste | ConvertTo-Json -Depth 5) | Set-Content -Path $chemin -Encoding UTF8 -ErrorAction Stop
        }
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer la liste de couleurs sur le disque : $_)"
    }
}

# Memorise le DERNIER trio selectionne entre deux lancements (11/10/2026, Tomyn : "toutes stp")
# - meme principe (petit fichier JSON a cote du script) que reference-angle.json plus bas dans le
# fichier pour l'angle de reference. Juste un nom de trio ; si ce nom n'existe plus au prochain
# demarrage (supprime, ou JSON corrompu), on retombe silencieusement sur le premier de la liste
# (voir l'appel au moment de peupler $menuTrio, section FENETRE).
function Obtenir-CheminDernierTrio {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "dernier-trio.json" } else { Join-Path (Get-Location) "dernier-trio.json" }
}

function Charger-DernierTrio {
    $chemin = Obtenir-CheminDernierTrio
    if (-not (Test-Path $chemin)) { return $null }
    try {
        $objet = Get-Content -Path $chemin -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($objet.Nom) { return [string]$objet.Nom }
    } catch { }
    return $null
}

function Sauvegarder-DernierTrio([string]$nom) {
    try {
        (@{ Nom = $nom } | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminDernierTrio) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer le dernier trio utilise sur le disque : $_)"
    }
}

# Memorise le DERNIER fichier .3mf charge entre deux lancements (12/10/2026, Tomyn : idee
# d'amelioration validee "vaut le coup") - meme principe exact que dernier-trio.json ci-dessus.
# Rempli a chaque selection reussie d'un fichier (Parcourir..., glisser-depose), relu au demarrage
# pour pre-remplir $txtFichier et l'apercu "avant" - si le fichier a ete deplace/supprime depuis,
# on verifie Test-Path avant de s'en servir (voir l'appel juste avant $form.ShowDialog()) et on ne
# fait simplement rien si il n'existe plus, sans message d'erreur.
function Obtenir-CheminDernierFichier {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "dernier-fichier.json" } else { Join-Path (Get-Location) "dernier-fichier.json" }
}

function Charger-DernierFichier {
    $chemin = Obtenir-CheminDernierFichier
    if (-not (Test-Path $chemin)) { return $null }
    try {
        $objet = Get-Content -Path $chemin -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($objet.Chemin) { return [string]$objet.Chemin }
    } catch { }
    return $null
}

function Sauvegarder-DernierFichier([string]$chemin) {
    try {
        (@{ Chemin = $chemin } | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminDernierFichier) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer le dernier fichier utilise sur le disque : $_)"
    }
}

# Liste des trios RECEMMENT utilises (11/10/2026, Tomyn : "1-2-3-4") - complement du "dernier
# trio" ci-dessus : utile si Tomyn alterne regulierement entre 2-3 trios plutot qu'un seul
# fixe. Les 5 derniers noms distincts, le plus recent en premier ; un nom supprime depuis (trio
# efface) est simplement ignore au moment d'en faire la liste affichee, pas purge du fichier
# lui-meme (pas la peine de complexifier pour un fichier aussi petit).
function Obtenir-CheminTriosRecents {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "trios-recents.json" } else { Join-Path (Get-Location) "trios-recents.json" }
}

function Charger-TriosRecents {
    $chemin = Obtenir-CheminTriosRecents
    if (-not (Test-Path $chemin)) { return @() }
    try {
        $objet = Get-Content -Path $chemin -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return @($objet.Noms | ForEach-Object { [string]$_ })
    } catch { return @() }
}

function Ajouter-TrioRecent([string]$nom) {
    $liste = @(Charger-TriosRecents | Where-Object { $_ -ne $nom })
    $liste = @($nom) + $liste
    if ($liste.Count -gt 5) { $liste = $liste[0..4] }
    try {
        (@{ Noms = $liste } | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminTriosRecents) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer les trios recents sur le disque : $_)"
    }
}

# Trios FAVORIS (12/10/2026, idee d'amelioration validee "vaut le coup" - Tomyn : "a soupeser,
# peut-etre redondant" avec les trios recents ci-dessus, mais demande quand meme) - contrairement
# aux "recents" (automatique, change tout seul), un favori est un choix EXPLICITE de Tomyn qui ne
# bouge pas tant qu'il ne le retire pas lui-meme. Toujours affiches tout en haut du menu principal
# (voir Obtenir-NomsTriosOrdonnes plus bas), marques d'une etoile dans ce meme menu (voir
# Rendre-ComboBoxPlate). Meme principe de petit fichier JSON a cote du script que les autres listes
# ci-dessus.
function Obtenir-CheminTriosFavoris {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "trios-favoris.json" } else { Join-Path (Get-Location) "trios-favoris.json" }
}

function Charger-TriosFavoris {
    $chemin = Obtenir-CheminTriosFavoris
    if (-not (Test-Path $chemin)) { return @() }
    try {
        $objet = Get-Content -Path $chemin -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return @($objet.Noms | ForEach-Object { [string]$_ })
    } catch { return @() }
}

function Sauvegarder-TriosFavoris([array]$liste) {
    try {
        (@{ Noms = @($liste) } | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminTriosFavoris) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer les trios favoris sur le disque : $_)"
    }
}

# Historique des lots (11/10/2026, Tomyn : "toutes stp") - un fichier texte CUMULATIF (jamais
# ecrase, une ligne ajoutee a chaque fichier traite, en lot ou tout seul) qui retrace quel trio a
# ete utilise sur quel fichier et quand - different du .log par lot deja exporte par
# Traiter-LotDeFichiers (celui-la ne couvre qu'UN lot et n'est pas cumulatif d'un lot a l'autre, ni
# rempli du tout pour un fichier traite seul via "Lancer le melange"). Jamais bloquant si
# l'ecriture echoue (meme principe que partout ailleurs dans ce fichier pour les ecritures sur
# disque qui ne sont pas le resultat principal demande).
function Obtenir-CheminHistoriqueLots {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "historique-lots.log" } else { Join-Path (Get-Location) "historique-lots.log" }
}

function Ajouter-LigneHistorique([string]$nomTrio, [string]$cheminEntree, [string]$resultat) {
    try {
        $horodatage = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $ligne = "$horodatage | Trio : $nomTrio | Fichier : $cheminEntree | $resultat"
        Add-Content -Path (Obtenir-CheminHistoriqueLots) -Value $ligne -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

# Relit historique-lots.log pour retrouver la DERNIERE fois qu'un fichier precis a deja ete traite
# (12/10/2026, idee d'amelioration validee "vaut le coup" : "deja melange le 10/10 avec le trio
# Pastel" a cote de "Lancer le melange" - evite de refaire deux fois le meme fichier sans s'en
# rendre compte). Comparaison de chemin EXACTE (apres Trim), pas insensible a la casse - le meme
# chemin ecrit par Ajouter-LigneHistorique est toujours obtenu de la meme facon ($txtFichier.Text
# ou equivalent), donc pas de souci de casse attendu en pratique sur un usage normal. Le fichier est
# CUMULATIF (jamais ecrase, une ligne ajoutee a chaque traitement) donc la DERNIERE ligne
# correspondante dans l'ordre du fichier est la plus recente - la boucle garde la derniere
# correspondance trouvee en avancant, sans avoir besoin de trier par date.
function Obtenir-DerniereUtilisationHistorique([string]$cheminFichier) {
    $chemin = Obtenir-CheminHistoriqueLots
    if (-not (Test-Path $chemin)) { return $null }
    try {
        $lignes = Get-Content -Path $chemin -Encoding UTF8 -ErrorAction Stop
    } catch { return $null }
    $cheminNormalise = $cheminFichier.Trim('"').Trim()
    $derniereCorrespondance = $null
    foreach ($ligne in $lignes) {
        if ($ligne -match '^(?<date>[\d-]+ [\d:]+) \| Trio : (?<trio>[^|]+) \| Fichier : (?<fichier>[^|]+) \|') {
            if ($matches.fichier.Trim() -eq $cheminNormalise) {
                $derniereCorrespondance = @{ Date = $matches.date.Trim(); Trio = $matches.trio.Trim() }
            }
        }
    }
    return $derniereCorrespondance
}

# Compte, pour chaque trio, le nombre de fois qu'il apparait dans historique-lots.log (13/10/2026,
# idee "vaut le coup" validee par Tomyn : "OK POUR 'VAUT LE COUP'") - affiche dans "Gerer mes
# trios..." pour aider a decider objectivement lesquels marquer favoris, au lieu de deviner. Compte
# TOUTES les lignes correspondantes (succes ou echec, test rapide non inclus car jamais loguee) -
# pas seulement la derniere comme Obtenir-DerniereUtilisationHistorique ci-dessus. Renvoie une
# hashtable nom de trio -> nombre (les trios jamais utilises n'ont simplement pas de cle).
function Obtenir-ComptesUtilisationTrios {
    $comptes = @{}
    $chemin = Obtenir-CheminHistoriqueLots
    if (-not (Test-Path $chemin)) { return $comptes }
    try {
        $lignes = Get-Content -Path $chemin -Encoding UTF8 -ErrorAction Stop
    } catch { return $comptes }
    foreach ($ligne in $lignes) {
        if ($ligne -match '^(?<date>[\d-]+ [\d:]+) \| Trio : (?<trio>[^|]+) \| Fichier :') {
            $nomTrio = $matches.trio.Trim()
            if ($comptes.ContainsKey($nomTrio)) { $comptes[$nomTrio]++ } else { $comptes[$nomTrio] = 1 }
        }
    }
    return $comptes
}

# Noms des trios predefinis (non modifiables / non supprimables depuis "Gerer mes trios...") -
# capture avant de fusionner les trios personnalises charges depuis le disque dans $TRIOS.
$script:NomsTriosPredefinis = @($TRIOS.Keys)

$triosPersonnalisesCharges = Charger-TriosPersonnalises
foreach ($nomCharge in $triosPersonnalisesCharges.Keys) {
    $TRIOS[$nomCharge] = $triosPersonnalisesCharges[$nomCharge]
}

# Liste plate des couleurs individuelles ("mon stock") - voir Charger-MesCouleurs/
# Sauvegarder-MesCouleurs plus haut. $script: pour etre modifiable depuis l'interieur des
# fonctions/popups de gestion plus bas sans avoir a la faire remonter par valeur de retour partout.
# 12/10/2026 : LE vrai bug derriere "ca ajoute la 1ere couleur mais pas la 2eme, erreur 'Nom'
# deja ajoute" (reproduit et confirme en isolant exactement ce chemin de code). Charger-MesCouleurs
# fait "return @()" quand le fichier n'existe pas encore - mais en PowerShell, un tableau VIDE
# renvoye via return/pipeline n'ecrit RIEN dans le flux de sortie, donc "$x = Fonction-Qui-Return-@()"
# donne $x = $null, PAS un tableau vide ! Consequence en cascade : "$null += @{Nom=...; Hex=...}"
# ne cree PAS un tableau a 1 element - il affecte DIRECTEMENT le hashtable lui-meme a la variable
# (donc la 1ere couleur "marchait" par coincidence, $rafraichirListe traitant ce hashtable seul comme
# UN element). Puis au 2eme ajout, "hashtable += hashtable" tente une FUSION des deux par cle au lieu
# d'un ajout dans un tableau - plante des que les deux ont une cle en commun (ici "Nom", present dans
# les deux), d'ou le message .NET "L'element a deja ete ajoute. Cle du dictionnaire : 'Nom'". Le
# "@(...)" ci-dessous force un vrai tableau (eventuellement vide) des le depart, meme motif deja
# utilise ailleurs dans ce fichier (ex: "$candidats = @(Obtenir-CandidatsSuggestionTrio)") - juste
# oublie ici au tout premier jet de cette fonctionnalite.
$script:MesCouleurs = @(Charger-MesCouleurs)

# Charge les trios favoris en memoire une seule fois au demarrage (meme principe que
# $script:MesCouleurs juste au-dessus) - mute directement en place (Add/Remove sur la liste, pas de
# reassignation complete sauf au tout premier chargement ici), donc visible partout sans souci de
# GetNewClosure() (meme raisonnement deja applique a $TRIOS pour les pastilles du menu).
$script:TriosFavoris = New-Object System.Collections.Generic.List[string]
foreach ($nom in (Charger-TriosFavoris)) { [void]$script:TriosFavoris.Add($nom) }

# Annulation de la derniere suppression (13/10/2026, idee "vaut le coup" validee par Tomyn : "OK
# POUR 'VAUT LE COUP'") - un seul niveau d'annulation (pas un historique complet empile), qui couvre
# aussi bien la derniere suppression de couleur(s) (et ses trios lies supprimes en cascade avec
# elles) que la derniere suppression de trio(s), peu importe laquelle des deux fenetres de gestion
# ("Gerer mes couleurs..." / "Gerer mes trios...") l'a declenchee - un bouton "Annuler" identique
# est propose dans les deux. $script:DerniereSuppression est REMPLACE (pas empile) a chaque nouvelle
# suppression et remis a $null apres une annulation (pas ré-annulable une seconde fois).
$script:DerniereSuppression = $null

# Restaure l'etat sauvegarde juste avant la derniere suppression, si elle existe encore. $TRIOS est
# toujours entierement reconstruit a partir du clone pris avant la suppression (meme pour une
# suppression de trios seule) : plus simple et plus sur que de ne re-ajouter que les entrees
# enlevees, et n'affecte pas les trios predefinis (jamais supprimables, donc toujours identiques
# dans le clone). Renvoie $true si une annulation a bien eu lieu, $false si rien a annuler.
function Annuler-DerniereSuppression {
    if (-not $script:DerniereSuppression) { return $false }
    $sauvegarde = $script:DerniereSuppression
    if ($sauvegarde.Type -eq "Couleurs") {
        $script:MesCouleurs = $sauvegarde.Couleurs
        Sauvegarder-MesCouleurs $script:MesCouleurs
    }
    $TRIOS.Clear()
    foreach ($cle in $sauvegarde.Trios.Keys) { $TRIOS[$cle] = $sauvegarde.Trios[$cle] }
    $personnalisesActuels = @{}
    foreach ($nom in $TRIOS.Keys) {
        if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
    }
    Sauvegarder-TriosPersonnalises $personnalisesActuels
    RafraichirListeTrios
    $script:DerniereSuppression = $null
    return $true
}

# Avertissement de "couverture" sur un trio personnalise (11/10/2026, Tomyn a teste un trio
# bleu/violet/orange/rose et observe que le melange ne ressort quasiment qu'avec 2 couleurs
# dominantes au lieu des 3) - CMY/RYB marchent bien parce que leurs 3 primaires sont ecartees sur
# toute la roue chromatique : l'"aire" du triangle qu'elles forment en Lab (L, a, b - meme espace de
# couleur deja utilise partout dans ce fichier pour comparer des couleurs) est donc grande, et la
# plupart des couleurs d'un modele tombent PRES de ce triangle (vrai melange des 3). Un trio aux
# teintes groupees forme un triangle plat/etroit (aire petite) : les couleurs du modele tombent alors
# plus loin, et le meilleur dosage trouve se retrouve sur un BORD du triangle (un segment), qui ne
# depend que de 2 des 3 sommets - d'ou l'effet observe.
# (11/10/2026, Tomyn a verifie que Bambu Studio ne melange que 3 couleurs a la fois - l'outil est
# passe de "quatuor"/tetraedre a "trio"/triangle partout. L'aire d'un triangle a 3 sommets A,B,C se
# calcule par la moitie de la norme du produit vectoriel (B-A)x(C-A) - formule standard, rien de
# specifique a la couleur.)
function Obtenir-AireCouvertureTrio($trio) {
    $labs = @($trio | ForEach-Object {
        $rgb = Obtenir-RGBDepuisHex $_.Hex
        Convertir-RGBVersLab $rgb.R $rgb.G $rgb.B
    })
    $A = $labs[0]; $B = $labs[1]; $C = $labs[2]
    $ux = $B.L - $A.L; $uy = $B.a - $A.a; $uz = $B.b - $A.b
    $vx = $C.L - $A.L; $vy = $C.a - $A.a; $vz = $C.b - $A.b
    $cx = $uy * $vz - $uz * $vy
    $cy = $uz * $vx - $ux * $vz
    $cz = $ux * $vy - $uy * $vx
    $norme = [Math]::Sqrt(($cx * $cx) + ($cy * $cy) + ($cz * $cz))
    return $norme / 2.0
}

# Detecte une paire de couleurs trop proches DANS un meme trio (11/10/2026, Tomyn : "1-2-3-4")
# - distinct de l'avertissement de couverture ci-dessous (qui regarde l'aire GLOBALE des 3) :
# ici, deux couleurs peuvent tres bien laisser une aire correcte tout en etant quasi identiques
# entre elles, ce qui gaspille un emplacement d'AMS pour un melange qui n'apportera presque rien de
# nouveau. Seuil de 15 (meme echelle Lab que partout ailleurs dans ce fichier) calibre en sandbox :
# les paires les plus proches de CMY/RYB/Pastel/Neon sont toutes au-dessus de 48,
# un vrai "quasi-doublon" (ex: deux bleus l'un a cote de l'autre sur la roue chromatique) tombe
# autour de 7-8 - large marge entre les deux. Retourne la liste des paires (index 0-based) trop
# proches, vide si tout va bien.
function Obtenir-PairesTropProches($trio) {
    $seuilProximite = 15.0
    $labs = @($trio | ForEach-Object {
        $rgb = Obtenir-RGBDepuisHex $_.Hex
        Convertir-RGBVersLab $rgb.R $rgb.G $rgb.B
    })
    $paires = @()
    for ($i = 0; $i -lt 3; $i++) {
        for ($j = $i + 1; $j -lt 3; $j++) {
            $distance = Obtenir-DistanceLab $labs[$i] $labs[$j]
            if ($distance -lt $seuilProximite) {
                $paires += @{ I = $i; J = $j; Distance = $distance }
            }
        }
    }
    # L'operateur virgule unaire est INDISPENSABLE ici (11/10/2026, verifie en sandbox) : sans lui,
    # PowerShell "deballe" un tableau d'un seul element au moment du retour de fonction - avec
    # exactement UNE paire trop proche, l'appelant recevrait directement le hashtable au lieu d'un
    # tableau d'un hashtable, et $resultat.Count renverrait le nombre de CLES du hashtable (3 :
    # I/J/Distance) au lieu du nombre de paires (1), avec en prime une erreur d'indexation plus
    # loin. Avec 0 ou 2+ paires, le probleme ne se voit pas - piege facile a manquer sans test cible.
    return ,$paires
}

# Detecte si une couleur (hex) est quasi-identique a une couleur DEJA dans "mon stock" ("Gerer mes
# couleurs...") - 12/10/2026, idee d'amelioration validee "vaut le coup" : evite d'empiler des
# quasi-doublons sans s'en rendre compte, ce qui gaspille un emplacement de stock et fausse un peu
# "Suggerer des trios depuis mes couleurs...". Meme seuil (15.0, meme echelle Lab) et meme logique
# que Obtenir-PairesTropProches ci-dessus, juste applique a UNE couleur candidate contre toute une
# liste au lieu d'un trio de 3. $indexAExclure sert pour "Modifier..." (ne pas se comparer a
# soi-meme) ; -1 pour "Ajouter..." (compare a tout le stock). Retourne la couleur existante la plus
# proche si sous le seuil, sinon $null.
function Obtenir-CouleurProcheDansStock([array]$couleurs, [string]$hex, [int]$indexAExclure = -1) {
    $seuilProximite = 15.0
    try {
        $rgbCandidat = Obtenir-RGBDepuisHex $hex
        $labCandidat = Convertir-RGBVersLab $rgbCandidat.R $rgbCandidat.G $rgbCandidat.B
    } catch { return $null }
    $plusProche = $null
    $plusPetiteDistance = [double]::MaxValue
    for ($i = 0; $i -lt $couleurs.Count; $i++) {
        if ($i -eq $indexAExclure) { continue }
        try {
            $rgbExistant = Obtenir-RGBDepuisHex $couleurs[$i].Hex
            $labExistant = Convertir-RGBVersLab $rgbExistant.R $rgbExistant.G $rgbExistant.B
            $distance = Obtenir-DistanceLab $labCandidat $labExistant
            if ($distance -lt $seuilProximite -and $distance -lt $plusPetiteDistance) {
                $plusPetiteDistance = $distance
                $plusProche = @{ Couleur = $couleurs[$i]; Distance = $distance }
            }
        } catch { continue }
    }
    return $plusProche
}

# Seuil d'avertissement calcule DYNAMIQUEMENT a partir des trios PREDEFINIS (CMY/RYB/Pastel/Neon)
# plutot qu'une valeur figee dans le code - si jamais leurs couleurs changent un jour, le seuil suit
# tout seul. 25% de leur aire moyenne (11/10/2026, le seuil a ete recalibre pour l'aire de triangle
# depuis le passage de l'outil en mode trio - l'ancienne valeur en volume de tetraedre n'avait plus
# le meme ordre de grandeur).
function Obtenir-SeuilAvertissementCouverture {
    $aires = @($script:NomsTriosPredefinis | ForEach-Object { Obtenir-AireCouvertureTrio $TRIOS[$_] })
    if ($aires.Count -eq 0) { return 0 }
    $moyenne = ($aires | Measure-Object -Average).Average
    return $moyenne * 0.25
}

# Suggestion automatique de la "meilleure" couleur pour un emplacement donne (11/10/2026, Tomyn :
# "d'autres idees ?" -> "toutes") - les 2 AUTRES couleurs du trio restent fixes, et on balaye
# l'espace RGB (pas de 17, soit 16 valeurs par canal -> 16^3 = 4096 candidats, suffisant pour une
# suggestion sans etre trop lent dans l'editeur) a la recherche du candidat qui MAXIMISE l'aire
# de couverture (voir Obtenir-AireCouvertureTrio) une fois mis a la place de l'emplacement
# $indice. Concretement : "si tu dois changer cette couleur-la pour elargir le trio, voici la
# plus efficace". Retourne juste un code hex ("#RRGGBB"), jamais un objet.
function Suggerer-MeilleureCouleur($composantsActuels, [int]$indice) {
    $pas = 17
    $meilleureAire = -1.0
    $meilleurHex = $composantsActuels[$indice].Hex
    for ($r = 0; $r -le 255; $r += $pas) {
        for ($g = 0; $g -le 255; $g += $pas) {
            for ($b = 0; $b -le 255; $b += $pas) {
                $hexCandidat = Obtenir-HexDepuisRGB $r $g $b
                $candidats = @()
                for ($i = 0; $i -lt 3; $i++) {
                    if ($i -eq $indice) {
                        $candidats += @{ Nom = $composantsActuels[$i].Nom; Hex = $hexCandidat }
                    } else {
                        $candidats += $composantsActuels[$i]
                    }
                }
                $aire = Obtenir-AireCouvertureTrio $candidats
                if ($aire -gt $meilleureAire) {
                    $meilleureAire = $aire
                    $meilleurHex = $hexCandidat
                }
            }
        }
    }
    return $meilleurHex
}

# Aperçu du trio selectionne dans le menu deroulant principal (11/10/2026, Tomyn : "toutes stp")
# - 3 pastilles de couleur + un score de couverture, pour voir d'un coup d'oeil si le trio choisi
# est large ou etroit SANS avoir a lancer un melange ni ouvrir "Gerer mes trios...". Les controles
# references ici ($panneauxPastilles, $labelCouvertureTrio, $menuTrio) sont crees PLUS BAS dans
# le fichier (section FENETRE) - resolus seulement au moment de l'APPEL de cette fonction, jamais a
# sa definition (meme principe deja utilise par RafraichirListeTrios un peu plus bas, qui
# reference $menuTrio avant meme qu'il existe textuellement dans le fichier).
function Mettre-A-Jour-ApercuTrioSelectionne {
    if (-not $menuTrio.SelectedItem) { return }
    $nom = $menuTrio.SelectedItem.ToString()
    $trioSelectionne = $TRIOS[$nom]
    if (-not $trioSelectionne) { return }

    # Memorise ce choix comme "dernier trio utilise" (11/10/2026, Tomyn : "toutes stp") - ce
    # point est le seul endroit appele a CHAQUE changement de selection effectif (clic dans le
    # menu, RafraichirListeTrios apres creation/modification/suppression, et l'appel initial au
    # demarrage), donc le choix le plus simple pour ecrire sur le disque sans dupliquer la logique
    # ailleurs.
    Sauvegarder-DernierTrio $nom
    # Meme point d'ancrage pour la liste des "recents" (11/10/2026, Tomyn : "1-2-3-4").
    Ajouter-TrioRecent $nom

    for ($i = 0; $i -lt 3; $i++) {
        try {
            $panneauxPastilles[$i].BackColor = [System.Drawing.ColorTranslator]::FromHtml($trioSelectionne[$i].Hex)
        } catch {
            $panneauxPastilles[$i].BackColor = [System.Drawing.Color]::Gray
        }
    }

    try {
        $aire = Obtenir-AireCouvertureTrio $trioSelectionne
        $seuil = Obtenir-SeuilAvertissementCouverture
        if ($seuil -gt 0) {
            $ratio = [Math]::Round($aire / $seuil, 1)
            if ($aire -lt $seuil) {
                $labelCouvertureTrio.Text = "Couverture : etroite (x$ratio du seuil d'alerte) - risque de melanges repetitifs"
                $labelCouvertureTrio.ForeColor = $THEME.AccentChaud
            } else {
                $labelCouvertureTrio.Text = "Couverture : large (x$ratio du seuil d'alerte)"
                $labelCouvertureTrio.ForeColor = $THEME.TexteSecondaire
            }
        } else {
            $labelCouvertureTrio.Text = ""
        }
    } catch {
        $labelCouvertureTrio.Text = ""
    }
}

# Fenetre d'edition d'un trio personnalise (creation ou modification) - 3 emplacements fixes
# (meme contrainte que les trios predefinis : le reste du script suppose toujours exactement 3
# primaires, voir la boucle "for ($i = 0; $i -lt 3; $i++)" dans Traiter-Fichier3MF). Retourne soit
# $null (annule), soit @{ Nom = ...; Composants = @(3x @{Nom;Hex}) }.
function Afficher-EditeurTrio($nomExistant, $composantsExistants) {
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = if ($nomExistant) { "Modifier un trio" } else { "Nouveau trio" }
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox = $false
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(380, 300)

    $labelNom = New-Object System.Windows.Forms.Label
    $labelNom.Text = "Nom du trio :"
    $labelNom.Location = New-Object System.Drawing.Point(10, 12)
    $labelNom.AutoSize = $true
    $popup.Controls.Add($labelNom)

    $zoneNom = New-Object System.Windows.Forms.TextBox
    $zoneNom.Location = New-Object System.Drawing.Point(10, 32)
    $zoneNom.Size = New-Object System.Drawing.Size(360, 24)
    if ($nomExistant) { $zoneNom.Text = $nomExistant }
    $popup.Controls.Add($zoneNom)

    # Couleurs de depart si on cree un nouveau trio (juste des valeurs de depart pratiques a
    # modifier au clic, pas une recommandation) ; si on modifie un trio existant, ses propres
    # couleurs sont reprises telles quelles.
    $couleursParDefaut = @("#C12E1F", "#F4EE2A", "#0A2989")
    $zonesNomComposant = New-Object System.Windows.Forms.TextBox[] 3
    # Champ de code hex tapable (10/10/2026, Tomyn : "la possibilite de mettre des codes hex... tu
    # tapes tes codes hex, ca te met la couleur") - en plus du bouton qui ouvre le selecteur Windows,
    # ce champ permet de taper directement un code (#RRGGBB ou RRGGBB) ; les deux restent synchros
    # dans les deux sens (taper ici met a jour le bouton, choisir via le bouton met a jour ce champ).
    $zonesHex = New-Object System.Windows.Forms.TextBox[] 3
    $boutonsCouleur = New-Object System.Windows.Forms.Button[] 3
    # Cases "Verrouiller" (11/10/2026, Tomyn : "d'autres idees ?" -> "toutes") - pratique pour
    # experimenter sur UNE couleur du trio sans risquer de toucher par erreur aux autres (champ
    # hex + bouton couleur desactives tant que coche). Volontairement PAS persiste sur le disque :
    # juste une securite pendant la session d'edition en cours, qui redemarre neutre a chaque
    # ouverture de cette fenetre.
    $casesVerrou = New-Object System.Windows.Forms.CheckBox[] 3
    $yLigne = 70
    for ($i = 0; $i -lt 3; $i++) {
        $nomDepart = if ($composantsExistants) { $composantsExistants[$i].Nom } else { "Primaire $($i + 1)" }
        $hexDepart = if ($composantsExistants) { $composantsExistants[$i].Hex } else { $couleursParDefaut[$i] }

        $zoneNomComposant = New-Object System.Windows.Forms.TextBox
        $zoneNomComposant.Location = New-Object System.Drawing.Point(10, $yLigne)
        $zoneNomComposant.Size = New-Object System.Drawing.Size(95, 24)
        $zoneNomComposant.Text = $nomDepart
        $popup.Controls.Add($zoneNomComposant)
        $zonesNomComposant[$i] = $zoneNomComposant

        $zoneHex = New-Object System.Windows.Forms.TextBox
        $zoneHex.Location = New-Object System.Drawing.Point(110, $yLigne)
        $zoneHex.Size = New-Object System.Drawing.Size(55, 24)
        $zoneHex.MaxLength = 7
        $zoneHex.Text = $hexDepart
        $popup.Controls.Add($zoneHex)
        $zonesHex[$i] = $zoneHex

        $boutonCouleur = New-Object System.Windows.Forms.Button
        $boutonCouleur.Location = New-Object System.Drawing.Point(170, $yLigne)
        $boutonCouleur.Size = New-Object System.Drawing.Size(115, 24)
        $boutonCouleur.FlatStyle = "Flat"
        $boutonCouleur.Cursor = "Hand"
        $boutonCouleur.Tag = $hexDepart
        $boutonCouleur.Text = $hexDepart
        try {
            $boutonCouleur.BackColor = [System.Drawing.ColorTranslator]::FromHtml($hexDepart)
            $boutonCouleur.ForeColor = if (([int]$boutonCouleur.BackColor.R + [int]$boutonCouleur.BackColor.G + [int]$boutonCouleur.BackColor.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
        } catch { }
        $boutonCouleur.Add_Click({
            $dialogueCouleur = New-Object System.Windows.Forms.ColorDialog
            try { $dialogueCouleur.Color = [System.Drawing.ColorTranslator]::FromHtml($boutonCouleur.Tag) } catch { }
            if ($dialogueCouleur.ShowDialog($popup) -eq [System.Windows.Forms.DialogResult]::OK) {
                $c = $dialogueCouleur.Color
                $hexChoisi = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
                $boutonCouleur.Tag = $hexChoisi
                $boutonCouleur.Text = $hexChoisi
                $boutonCouleur.BackColor = $c
                $boutonCouleur.ForeColor = if (([int]$c.R + [int]$c.G + [int]$c.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
                $zoneHex.Text = $hexChoisi
            }
        }.GetNewClosure())
        $popup.Controls.Add($boutonCouleur)
        $boutonsCouleur[$i] = $boutonCouleur

        # Suggestion automatique (11/10/2026, Tomyn : "d'autres idees ?" -> "toutes") - clic droit
        # sur le bouton couleur plutot qu'un 4eme bouton visible (la rangee est deja tres chargee
        # en largeur). Lit les 3 couleurs ACTUELLES des champs au moment du clic (pas celles de
        # depart), pour que la suggestion tienne compte d'un changement deja fait sur une autre
        # couleur avant de cliquer ici.
        $menuSuggestion = New-Object System.Windows.Forms.ContextMenuStrip
        $itemSuggerer = New-Object System.Windows.Forms.ToolStripMenuItem("Suggerer cette couleur...")
        $itemSuggerer.Add_Click({
            $composantsActuels = @()
            for ($k = 0; $k -lt 3; $k++) {
                $hexActuel = $zonesHex[$k].Text.Trim()
                if (-not $hexActuel.StartsWith('#')) { $hexActuel = '#' + $hexActuel }
                try { [void][System.Drawing.ColorTranslator]::FromHtml($hexActuel) } catch { $hexActuel = $boutonsCouleur[$k].Tag }
                $composantsActuels += @{ Nom = $zonesNomComposant[$k].Text; Hex = $hexActuel }
            }
            $popup.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            try {
                $hexSuggere = Suggerer-MeilleureCouleur $composantsActuels $i
            } finally {
                $popup.Cursor = [System.Windows.Forms.Cursors]::Default
            }
            $c = [System.Drawing.ColorTranslator]::FromHtml($hexSuggere)
            $boutonCouleur.Tag = $hexSuggere
            $boutonCouleur.Text = $hexSuggere
            $boutonCouleur.BackColor = $c
            $boutonCouleur.ForeColor = if (([int]$c.R + [int]$c.G + [int]$c.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
            $zoneHex.Text = $hexSuggere
        }.GetNewClosure())
        [void]$menuSuggestion.Items.Add($itemSuggerer)
        $boutonCouleur.ContextMenuStrip = $menuSuggestion

        $caseVerrou = New-Object System.Windows.Forms.CheckBox
        $caseVerrou.Text = "Verrou"
        $caseVerrou.Location = New-Object System.Drawing.Point(290, ($yLigne + 3))
        $caseVerrou.Size = New-Object System.Drawing.Size(80, 20)
        $caseVerrou.Add_CheckedChanged({
            $zoneHex.ReadOnly = $caseVerrou.Checked
            $boutonCouleur.Enabled = -not $caseVerrou.Checked
        }.GetNewClosure())
        $popup.Controls.Add($caseVerrou)
        $casesVerrou[$i] = $caseVerrou

        # Taper un code hex puis quitter le champ (Tab, clic ailleurs...) met a jour le bouton tout
        # de suite, pour un retour visuel immediat. Un code invalide (faute de frappe en cours) ne
        # bloque rien ici - la validation definitive (avec message d'erreur) se fait au clic sur OK,
        # voir plus bas.
        $zoneHex.Add_Leave({
            $texteHex = $zoneHex.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($texteHex)) { return }
            if (-not $texteHex.StartsWith('#')) { $texteHex = '#' + $texteHex }
            try {
                # [System.Drawing.ColorTranslator]::FromHtml("") renvoie Color.Empty (donc du noir)
                # SANS lever d'exception - d'ou le IsNullOrWhiteSpace juste au-dessus, sinon un champ
                # vide serait silencieusement accepte comme "#000000".
                $c = [System.Drawing.ColorTranslator]::FromHtml($texteHex)
                $hexNormalise = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
                $zoneHex.Text = $hexNormalise
                $boutonCouleur.Tag = $hexNormalise
                $boutonCouleur.Text = $hexNormalise
                $boutonCouleur.BackColor = $c
                $boutonCouleur.ForeColor = if (([int]$c.R + [int]$c.G + [int]$c.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
            } catch { }
        }.GetNewClosure())

        $yLigne += 32
    }

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Location = New-Object System.Drawing.Point(185, 253)
    $btnOK.Size = New-Object System.Drawing.Size(90, 32)
    Rendre-BoutonPlat $btnOK "principal"
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $popup.Controls.Add($btnOK)

    $btnAnnuler = New-Object System.Windows.Forms.Button
    $btnAnnuler.Text = "Annuler"
    $btnAnnuler.Location = New-Object System.Drawing.Point(280, 253)
    $btnAnnuler.Size = New-Object System.Drawing.Size(90, 32)
    Rendre-BoutonPlat $btnAnnuler "discret"
    $btnAnnuler.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnAnnuler)

    $popup.AcceptButton = $btnOK
    $popup.CancelButton = $btnAnnuler

    while ($true) {
        if ($popup.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

        $nomSaisi = $zoneNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nomSaisi)) {
            Afficher-Boite "Le trio doit avoir un nom." "Nom manquant" "OK" "Warning" | Out-Null
            continue
        }
        if ($script:NomsTriosPredefinis -contains $nomSaisi) {
            Afficher-Boite "Ce nom est deja utilise par un trio predefini - choisis-en un autre." "Nom reserve" "OK" "Warning" | Out-Null
            continue
        }
        if ($nomSaisi -ne $nomExistant -and $TRIOS.ContainsKey($nomSaisi)) {
            Afficher-Boite "Un trio personnalise porte deja ce nom." "Nom deja utilise" "OK" "Warning" | Out-Null
            continue
        }

        # Validation finale des 3 codes hex (10/10/2026, Tomyn : "tu tapes tes codes hex") - relue
        # directement depuis les champs tapables plutot que depuis $boutonsCouleur[$i].Tag, au cas
        # ou le Leave n'aurait pas eu l'occasion de se declencher (ex: Entree pressee alors que le
        # focus est encore dans le champ). Un code invalide bloque et redemande la correction au lieu
        # de silencieusement retomber sur l'ancienne couleur.
        $composants = @()
        # Drapeau booleen DEDIE (10/10/2026) - un simple "$hexInvalide = $texte puis if ($hexInvalide)"
        # laisserait passer un champ VIDE sans avertissement (une chaine vide est "fausse" en
        # PowerShell, le if ne se declencherait jamais), d'ou ce drapeau separe du texte lui-meme.
        $uneErreurHex = $false
        $texteHexEnErreur = ""
        for ($i = 0; $i -lt 3; $i++) {
            $texteHex = $zonesHex[$i].Text.Trim()
            if (-not $texteHex.StartsWith('#')) { $texteHex = '#' + $texteHex }
            $c = $null
            # Meme piege que dans le Add_Leave ci-dessus : FromHtml("") ne leve PAS d'exception (elle
            # renvoie Color.Empty, donc du noir) - le IsNullOrWhiteSpace evite d'accepter un champ
            # vide comme "#000000" valide.
            if (-not [string]::IsNullOrWhiteSpace($zonesHex[$i].Text)) {
                try { $c = [System.Drawing.ColorTranslator]::FromHtml($texteHex) } catch { $c = $null }
            }
            if ($null -eq $c) {
                $uneErreurHex = $true
                $texteHexEnErreur = $zonesHex[$i].Text
                break
            }
            $hexValide = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
            $nomComposant = $zonesNomComposant[$i].Text.Trim()
            if ([string]::IsNullOrWhiteSpace($nomComposant)) { $nomComposant = "Primaire $($i + 1)" }
            $composants += @{ Nom = $nomComposant; Hex = $hexValide }
        }
        if ($uneErreurHex) {
            Afficher-Boite "Code couleur invalide : '$texteHexEnErreur'.`r`n`r`nFormat attendu : #RRGGBB (ex: #FF8800) ou RRGGBB sans le #." "Code hex invalide" "OK" "Warning" | Out-Null
            continue
        }

        # Avertissement de proximite (11/10/2026, Tomyn : "1-2-3-4") - juste un avertissement,
        # meme logique de non-blocage que celui de couverture juste en dessous : le trio reste
        # enregistre quand meme. Voir Obtenir-PairesTropProches plus haut.
        try {
            $pairesProches = Obtenir-PairesTropProches $composants
            if ($pairesProches.Count -gt 0) {
                $descriptionsPaires = ($pairesProches | ForEach-Object {
                    "'$($composants[$_.I].Nom)' et '$($composants[$_.J].Nom)' (ecart $([Math]::Round($_.Distance, 1)))"
                }) -join "`r`n"
                Afficher-Boite "Au moins deux couleurs de ce trio sont tres proches l'une de l'autre :`r`n`r`n$descriptionsPaires`r`n`r`nConcretement : le melange risque d'utiliser un emplacement d'AMS entier pour une couleur qui ne se distingue presque pas d'une autre deja presente.`r`n`r`nLe trio est enregistre quand meme - c'est juste un avertissement." "Couleurs trop proches" "OK" "Warning" | Out-Null
            }
        } catch { }

        # Avertissement de couverture (11/10/2026, Tomyn : "tu peux coder l'avertissement") - juste
        # un avertissement, PAS un blocage : le trio reste enregistre tel quel apres le message,
        # certains usages (un theme precis, une piece particuliere) peuvent justifier un choix
        # volontairement "etroit". Voir Obtenir-AireCouvertureTrio plus haut pour le detail du
        # calcul.
        try {
            $aire = Obtenir-AireCouvertureTrio $composants
            $seuil = Obtenir-SeuilAvertissementCouverture
            if ($seuil -gt 0 -and $aire -lt $seuil) {
                Afficher-Boite "Ce trio couvre une zone de couleurs assez etroite (teintes trop proches entre elles).`r`n`r`nConcretement : sur beaucoup de modeles, le melange risque de ne faire ressortir que 1 ou 2 des 3 couleurs au lieu des 3 - verifie l'apercu avant/apres avant un gros lot.`r`n`r`nPour elargir la couverture : ecarte les 3 couleurs le plus possible sur la roue chromatique (et/ou inclus un blanc ou un noir, qui ouvrent le plus de volume en luminosite).`r`n`r`nLe trio est enregistre quand meme - c'est juste un avertissement." "Couverture de couleurs etroite" "OK" "Warning" | Out-Null
            }
        } catch { }

        return @{ Nom = $nomSaisi; Composants = $composants }
    }
}

# Ordre d'affichage des trios (11/10/2026, Tomyn : "1-2-3-4"; 12/10/2026, ajout des FAVORIS) - les
# FAVORIS d'abord (etoile - choix explicite de Tomyn, ne bouge pas tout seul), puis les trios
# RECENTS parmi ceux qui restent (le plus recent en tete), puis le reste de $TRIOS dans son ordre
# habituel, sans doublon. Un nom favori/recent qui n'existe plus (trio supprime depuis) est
# simplement ignore.
function Obtenir-NomsTriosOrdonnes {
    $favoris = @($script:TriosFavoris | Where-Object { $TRIOS.ContainsKey($_) })
    $recents = @(Charger-TriosRecents | Where-Object { $TRIOS.ContainsKey($_) -and ($favoris -notcontains $_) })
    $noms = @($favoris) + @($recents)
    foreach ($nom in $TRIOS.Keys) {
        if ($noms -notcontains $nom) { $noms += $nom }
    }
    return $noms
}

# Reconstruit la liste de la ComboBox principale a partir de $TRIOS (predefinis + personnalises),
# en essayant de conserver la selection actuelle si elle existe toujours.
function RafraichirListeTrios {
    $selectionActuelle = if ($menuTrio.SelectedItem) { $menuTrio.SelectedItem.ToString() } else { $null }
    $menuTrio.Items.Clear()
    foreach ($nom in Obtenir-NomsTriosOrdonnes) { [void]$menuTrio.Items.Add($nom) }
    if ($selectionActuelle -and $menuTrio.Items.Contains($selectionActuelle)) {
        $menuTrio.SelectedItem = $selectionActuelle
    } else {
        $menuTrio.SelectedIndex = 0
    }
    # Appel explicite (11/10/2026) - SelectedIndexChanged ne se declenche PAS si l'index reassigne
    # ci-dessus est deja le meme qu'avant (ex: on vient de MODIFIER le trio deja selectionne,
    # sans changer sa position dans la liste) - sans cet appel, les pastilles/le score resteraient
    # perimes apres une modification.
    Mettre-A-Jour-ApercuTrioSelectionne
}

# Fenetre de gestion ("Gerer mes trios...") - liste uniquement les trios PERSONNALISES (les
# predefinis CMYW/RYBW ne sont ni modifiables ni supprimables depuis ici).
function Afficher-GestionTrios {
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = "Gerer mes trios personnalises"
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox = $false
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(380, 530)

    $liste = New-Object System.Windows.Forms.ListBox
    $liste.Location = New-Object System.Drawing.Point(10, 10)
    $liste.Size = New-Object System.Drawing.Size(360, 240)
    # 12/10/2026, Tomyn : "la possibilite de selectionner plusieurs trio ou meme tous pour
    # supprimer plusieurs ou tous les trios" - MultiExtended permet Ctrl+clic/Shift+clic comme
    # dans l'explorateur Windows, en plus des deux boutons "Tout selectionner"/"Aucune selection"
    # ci-dessous pour aller plus vite avec beaucoup de trios.
    $liste.SelectionMode = "MultiExtended"
    $popup.Controls.Add($liste)

    # Tableau parallele nom reel <-> index affiche (13/10/2026) - necessaire depuis que le texte
    # affiche inclut le compteur d'utilisation ("... (utilise X fois)") : les boutons ne peuvent
    # plus retrouver le nom reel avec un simple .ToString() sur l'item affiche, donc ils passent
    # desormais tous par SelectedIndex/SelectedIndices + ce tableau (meme principe deja utilise par
    # "Gerer mes couleurs..." plus bas, qui indexe directement $script:MesCouleurs). Liste mutee en
    # place (Clear()+Add(), jamais reassignee) pour rester valide dans les closures .GetNewClosure()
    # existantes, meme raisonnement que $script:TriosFavoris.
    $nomsTriosOrdre = New-Object System.Collections.Generic.List[string]

    $rafraichirListePerso = {
        $liste.Items.Clear()
        $nomsTriosOrdre.Clear()
        # Compteur d'utilisation par trio (13/10/2026, idee "vaut le coup" validee par Tomyn) -
        # relit historique-lots.log une seule fois ici plutot qu'une fois par trio.
        $comptesUtilisation = Obtenir-ComptesUtilisationTrios
        foreach ($nom in $TRIOS.Keys) {
            if ($script:NomsTriosPredefinis -notcontains $nom) {
                $nombreUtilisations = if ($comptesUtilisation.ContainsKey($nom)) { $comptesUtilisation[$nom] } else { 0 }
                $texteFois = if ($nombreUtilisations -eq 1) { "1 fois" } else { "$nombreUtilisations fois" }
                [void]$liste.Items.Add("$nom  (utilise $texteFois)")
                [void]$nomsTriosOrdre.Add($nom)
            }
        }
    }
    & $rafraichirListePerso

    $btnToutSelectionner = New-Object System.Windows.Forms.Button
    $btnToutSelectionner.Text = "Tout selectionner"
    $btnToutSelectionner.Location = New-Object System.Drawing.Point(10, 258)
    $btnToutSelectionner.Size = New-Object System.Drawing.Size(175, 26)
    Rendre-BoutonPlat $btnToutSelectionner "secondaire"
    $btnToutSelectionner.Add_Click({
        for ($i = 0; $i -lt $liste.Items.Count; $i++) { $liste.SetSelected($i, $true) }
    }.GetNewClosure())
    $popup.Controls.Add($btnToutSelectionner)

    $btnAucuneSelection = New-Object System.Windows.Forms.Button
    $btnAucuneSelection.Text = "Aucune selection"
    $btnAucuneSelection.Location = New-Object System.Drawing.Point(194, 258)
    $btnAucuneSelection.Size = New-Object System.Drawing.Size(176, 26)
    Rendre-BoutonPlat $btnAucuneSelection "discret"
    $btnAucuneSelection.Add_Click({
        $liste.ClearSelected()
    }.GetNewClosure())
    $popup.Controls.Add($btnAucuneSelection)

    $btnNouveau = New-Object System.Windows.Forms.Button
    $btnNouveau.Text = "Nouveau..."
    $btnNouveau.Location = New-Object System.Drawing.Point(10, 292)
    $btnNouveau.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnNouveau "secondaire"
    $btnNouveau.Add_Click({
        $resultat = Afficher-EditeurTrio $null $null
        if ($resultat) {
            $TRIOS[$resultat.Nom] = $resultat.Composants
            $personnalisesActuels = @{}
            foreach ($nom in $TRIOS.Keys) {
                if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
            }
            Sauvegarder-TriosPersonnalises $personnalisesActuels
            & $rafraichirListePerso
            RafraichirListeTrios
        }
    }.GetNewClosure())
    $popup.Controls.Add($btnNouveau)

    $btnModifier = New-Object System.Windows.Forms.Button
    $btnModifier.Text = "Modifier..."
    $btnModifier.Location = New-Object System.Drawing.Point(132, 292)
    $btnModifier.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnModifier "secondaire"
    $btnModifier.Add_Click({
        # 12/10/2026 : "Modifier..." reste limite a UN SEUL trio a la fois (editer plusieurs trios
        # differents dans la meme fenetre n'aurait pas de sens) - message different de 0 vs 2+
        # selections pour que ce soit clair pourquoi ca ne fait rien.
        if ($liste.SelectedItems.Count -eq 0) {
            Afficher-Boite "Choisis d'abord un trio dans la liste." "Aucune selection" "OK" "Warning" | Out-Null
            return
        }
        if ($liste.SelectedItems.Count -gt 1) {
            Afficher-Boite "Choisis un seul trio a la fois pour le modifier (plusieurs sont selectionnes)." "Plusieurs trios selectionnes" "OK" "Warning" | Out-Null
            return
        }
        $ancienNom = $nomsTriosOrdre[$liste.SelectedIndex]
        $resultat = Afficher-EditeurTrio $ancienNom $TRIOS[$ancienNom]
        if ($resultat) {
            if ($resultat.Nom -ne $ancienNom) { $TRIOS.Remove($ancienNom) }
            $TRIOS[$resultat.Nom] = $resultat.Composants
            $personnalisesActuels = @{}
            foreach ($nom in $TRIOS.Keys) {
                if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
            }
            Sauvegarder-TriosPersonnalises $personnalisesActuels
            & $rafraichirListePerso
            RafraichirListeTrios
        }
    }.GetNewClosure())
    $popup.Controls.Add($btnModifier)

    $btnSupprimer = New-Object System.Windows.Forms.Button
    $btnSupprimer.Text = "Supprimer"
    $btnSupprimer.Location = New-Object System.Drawing.Point(254, 292)
    $btnSupprimer.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnSupprimer "danger"
    # 12/10/2026, Tomyn : "la possibilite de selectionner plusieurs trio ou meme tous pour
    # supprimer plusieurs ou tous les trios" - supprime maintenant TOUS les trios selectionnes
    # d'un coup (un seul comme avant si un seul est selectionne), au lieu de se limiter a
    # $liste.SelectedItem (qui ne renvoie que le premier avec le mode MultiExtended).
    $btnSupprimer.Add_Click({
        if ($liste.SelectedItems.Count -eq 0) {
            Afficher-Boite "Choisis d'abord au moins un trio dans la liste." "Aucune selection" "OK" "Warning" | Out-Null
            return
        }
        $nomsASupprimer = @($liste.SelectedIndices | ForEach-Object { $nomsTriosOrdre[$_] })
        $messageConfirmation = if ($nomsASupprimer.Count -eq 1) {
            "Supprimer definitivement le trio '$($nomsASupprimer[0])' ?"
        } else {
            "Supprimer definitivement ces $($nomsASupprimer.Count) trios ?`r`n`r`n - " + ($nomsASupprimer -join "`r`n - ")
        }
        if ((Afficher-Boite $messageConfirmation "Confirmer la suppression" "YesNo" "Question") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        # Snapshot AVANT suppression pour "Annuler" (13/10/2026) - clone manuel (pas $TRIOS.Clone()
        # directement comme cle de hashtable, meme resultat mais garde le style deja utilise partout
        # ailleurs dans ce fichier pour reconstruire $personnalisesActuels).
        $sauvegardeTriosAvant = @{}
        foreach ($nom in $TRIOS.Keys) { $sauvegardeTriosAvant[$nom] = $TRIOS[$nom] }
        $script:DerniereSuppression = @{ Type = "Trios"; Trios = $sauvegardeTriosAvant }
        foreach ($nomASupprimer in $nomsASupprimer) { $TRIOS.Remove($nomASupprimer) }
        $personnalisesActuels = @{}
        foreach ($nom in $TRIOS.Keys) {
            if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
        }
        Sauvegarder-TriosPersonnalises $personnalisesActuels
        & $rafraichirListePerso
        RafraichirListeTrios
        $btnAnnulerSuppressionTrio.Enabled = $true
    }.GetNewClosure())
    $popup.Controls.Add($btnSupprimer)

    # Touche Suppr (13/10/2026, idee "vaut le coup" validee par Tomyn) - supprime directement au
    # clavier la selection en cours, sans aller cliquer le bouton "Supprimer" ; declenche exactement
    # le meme code (confirmation comprise) en appelant le bouton lui-meme plutot qu'en dupliquant sa
    # logique. SuppressKeyPress evite le "ding" systeme Windows sur la touche Suppr dans une ListBox.
    $liste.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
            $_.SuppressKeyPress = $true
            $btnSupprimer.PerformClick()
        }
    })

    # Bouton "Annuler" (13/10/2026, idee "vaut le coup" validee par Tomyn) - desactive a l'ouverture
    # sauf si une suppression (ici ou dans "Gerer mes couleurs...") est encore annulable ; se
    # desactive lui-meme apres usage (un seul niveau d'annulation, pas re-annulable).
    $btnAnnulerSuppressionTrio = New-Object System.Windows.Forms.Button
    $btnAnnulerSuppressionTrio.Text = "Annuler la derniere suppression"
    $btnAnnulerSuppressionTrio.Location = New-Object System.Drawing.Point(10, 416)
    $btnAnnulerSuppressionTrio.Size = New-Object System.Drawing.Size(360, 26)
    Rendre-BoutonPlat $btnAnnulerSuppressionTrio "secondaire"
    $btnAnnulerSuppressionTrio.Enabled = ($null -ne $script:DerniereSuppression)
    $btnAnnulerSuppressionTrio.Add_Click({
        if (Annuler-DerniereSuppression) {
            & $rafraichirListePerso
            $btnAnnulerSuppressionTrio.Enabled = $false
        }
    }.GetNewClosure())
    $popup.Controls.Add($btnAnnulerSuppressionTrio)

    # 12/10/2026, idee d'amelioration validee "vaut le coup" (Tomyn : "a soupeser, peut-etre
    # redondant" avec les trios recents) - marque/demarque FAVORI chaque trio selectionne (bascule
    # individuellement : un favori selectionne redevient normal, un normal selectionne devient
    # favori - pratique pour en faire plusieurs a la fois sans suivre l'etat de chacun). Les favoris
    # remontent tout en haut du menu principal (Obtenir-NomsTriosOrdonnes) et s'y affichent avec un
    # "*" devant le nom (Rendre-ComboBoxPlate).
    $btnBasculerFavori = New-Object System.Windows.Forms.Button
    $btnBasculerFavori.Text = "Marquer/demarquer favori (*)"
    $btnBasculerFavori.Location = New-Object System.Drawing.Point(10, 330)
    $btnBasculerFavori.Size = New-Object System.Drawing.Size(360, 26)
    Rendre-BoutonPlat $btnBasculerFavori "secondaire"
    $btnBasculerFavori.Add_Click({
        if ($liste.SelectedItems.Count -eq 0) {
            Afficher-Boite "Choisis d'abord au moins un trio dans la liste." "Aucune selection" "OK" "Warning" | Out-Null
            return
        }
        foreach ($nom in @($liste.SelectedIndices | ForEach-Object { $nomsTriosOrdre[$_] })) {
            if ($script:TriosFavoris -contains $nom) {
                [void]$script:TriosFavoris.Remove($nom)
            } else {
                [void]$script:TriosFavoris.Add($nom)
            }
        }
        Sauvegarder-TriosFavoris @($script:TriosFavoris)
        RafraichirListeTrios
    }.GetNewClosure())
    $popup.Controls.Add($btnBasculerFavori)

    # Dupliquer (11/10/2026, Tomyn : "toutes stp") - repartir d'un trio EXISTANT (predefini OU
    # personnalise, d'ou le menu deroulant a part plutot que de reutiliser la liste du dessus qui ne
    # montre que les personnalises) pour en faire une variante, sans retaper les 3 couleurs a la
    # main. Ouvre l'editeur pre-rempli avec les couleurs de la source mais SANS nom (force a en
    # choisir un nouveau, meme validation que "Nouveau...").
    $labelDupliquer = New-Object System.Windows.Forms.Label
    $labelDupliquer.Text = "Dupliquer a partir de :"
    $labelDupliquer.Location = New-Object System.Drawing.Point(10, 364)
    $labelDupliquer.AutoSize = $true
    $popup.Controls.Add($labelDupliquer)

    $menuSourceDuplication = New-Object System.Windows.Forms.ComboBox
    $menuSourceDuplication.Location = New-Object System.Drawing.Point(10, 384)
    $menuSourceDuplication.Size = New-Object System.Drawing.Size(240, 24)
    $menuSourceDuplication.DropDownStyle = "DropDownList"
    foreach ($nom in $TRIOS.Keys) { [void]$menuSourceDuplication.Items.Add($nom) }
    if ($menuSourceDuplication.Items.Count -gt 0) { $menuSourceDuplication.SelectedIndex = 0 }
    $popup.Controls.Add($menuSourceDuplication)

    $btnDupliquer = New-Object System.Windows.Forms.Button
    $btnDupliquer.Text = "Dupliquer..."
    $btnDupliquer.Location = New-Object System.Drawing.Point(254, 383)
    $btnDupliquer.Size = New-Object System.Drawing.Size(115, 26)
    Rendre-BoutonPlat $btnDupliquer "secondaire"
    $btnDupliquer.Add_Click({
        if (-not $menuSourceDuplication.SelectedItem) { return }
        $nomSource = $menuSourceDuplication.SelectedItem.ToString()
        $resultat = Afficher-EditeurTrio $null $TRIOS[$nomSource]
        if ($resultat) {
            $TRIOS[$resultat.Nom] = $resultat.Composants
            $personnalisesActuels = @{}
            foreach ($nom in $TRIOS.Keys) {
                if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
            }
            Sauvegarder-TriosPersonnalises $personnalisesActuels
            & $rafraichirListePerso
            RafraichirListeTrios
            # Nouveau trio ajoute - rafraichit aussi la source de duplication elle-meme, pour
            # pouvoir enchainer une seconde duplication a partir de celui qu'on vient de creer.
            $menuSourceDuplication.Items.Clear()
            foreach ($nom in $TRIOS.Keys) { [void]$menuSourceDuplication.Items.Add($nom) }
            $menuSourceDuplication.SelectedItem = $resultat.Nom
        }
    }.GetNewClosure())
    $popup.Controls.Add($btnDupliquer)

    # Export/Import (11/10/2026, Tomyn : "toutes stp") - sauvegarder ses trios personnalises dans
    # un fichier JSON a part (pour les transferer sur un autre poste, les partager, ou juste en
    # garder une copie ailleurs que dans le fichier local trios-personnalises.json). L'import
    # IGNORE silencieusement une entree qui porte le nom d'un trio PREDEFINI (reserve) ou qui n'a
    # pas exactement 3 composants ; une entree important un nom DEJA utilise par un trio
    # personnalise existant l'ECRASE (import = fusion, le plus recent gagne), meme logique que le
    # chargement au demarrage dans Charger-TriosPersonnalises.
    $btnExporter = New-Object System.Windows.Forms.Button
    $btnExporter.Text = "Exporter..."
    $btnExporter.Location = New-Object System.Drawing.Point(10, 448)
    $btnExporter.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnExporter "secondaire"
    $btnExporter.Add_Click({
        $personnalisesActuels = @{}
        foreach ($nom in $TRIOS.Keys) {
            if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
        }
        if ($personnalisesActuels.Count -eq 0) {
            Afficher-Boite "Aucun trio personnalise a exporter." "Rien a exporter" "OK" "Warning" | Out-Null
            return
        }
        $dialogue = New-Object System.Windows.Forms.SaveFileDialog
        $dialogue.Filter = "Fichier JSON (*.json)|*.json"
        $dialogue.FileName = "trios-personnalises.json"
        if ($dialogue.ShowDialog($popup) -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                ($personnalisesActuels | ConvertTo-Json -Depth 5) | Set-Content -Path $dialogue.FileName -Encoding UTF8 -ErrorAction Stop
                Afficher-Boite "$($personnalisesActuels.Count) trio(s) exporte(s) vers :`r`n$($dialogue.FileName)" "Export reussi" "OK" "Info" | Out-Null
            } catch {
                Afficher-Boite "Echec de l'export : $_" "Erreur" "OK" "Error" | Out-Null
            }
        }
    }.GetNewClosure())
    $popup.Controls.Add($btnExporter)

    $btnImporter = New-Object System.Windows.Forms.Button
    $btnImporter.Text = "Importer..."
    $btnImporter.Location = New-Object System.Drawing.Point(132, 448)
    $btnImporter.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnImporter "secondaire"
    $btnImporter.Add_Click({
        $dialogue = New-Object System.Windows.Forms.OpenFileDialog
        $dialogue.Filter = "Fichier JSON (*.json)|*.json"
        if ($dialogue.ShowDialog($popup) -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $contenu = Get-Content -Path $dialogue.FileName -Raw -ErrorAction Stop
                $objet = $contenu | ConvertFrom-Json -ErrorAction Stop
                $nombreImportes = 0
                $nombreIgnores = 0
                foreach ($prop in $objet.PSObject.Properties) {
                    $nomImporte = $prop.Name
                    if ($script:NomsTriosPredefinis -contains $nomImporte) {
                        $nombreIgnores++
                        continue
                    }
                    $composantsImportes = @($prop.Value | ForEach-Object { @{ Nom = $_.Nom; Hex = $_.Hex } })
                    if ($composantsImportes.Count -ne 3) {
                        $nombreIgnores++
                        continue
                    }
                    $TRIOS[$nomImporte] = $composantsImportes
                    $nombreImportes++
                }
                $personnalisesActuels = @{}
                foreach ($nom in $TRIOS.Keys) {
                    if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
                }
                Sauvegarder-TriosPersonnalises $personnalisesActuels
                & $rafraichirListePerso
                RafraichirListeTrios
                $menuSourceDuplication.Items.Clear()
                foreach ($nom in $TRIOS.Keys) { [void]$menuSourceDuplication.Items.Add($nom) }
                if ($menuSourceDuplication.Items.Count -gt 0) { $menuSourceDuplication.SelectedIndex = 0 }
                $messageImport = "$nombreImportes trio(s) importe(s)."
                if ($nombreIgnores -gt 0) { $messageImport += "`r`n$nombreIgnores entree(s) ignoree(s) (nom reserve ou format invalide)." }
                Afficher-Boite $messageImport "Import termine" "OK" "Info" | Out-Null
            } catch {
                Afficher-Boite "Fichier invalide ou illisible : $_" "Echec de l'import" "OK" "Error" | Out-Null
            }
        }
    }.GetNewClosure())
    $popup.Controls.Add($btnImporter)

    $btnFermer = New-Object System.Windows.Forms.Button
    $btnFermer.Text = "Fermer"
    $btnFermer.Location = New-Object System.Drawing.Point(254, 486)
    $btnFermer.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnFermer "discret"
    $btnFermer.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnFermer)
    $popup.CancelButton = $btnFermer

    [void]$popup.ShowDialog($form)
}

# Petit editeur pour UNE couleur individuelle (12/10/2026) - version simplifiee d'un seul tiers
# de Afficher-EditeurTrio ci-dessus (meme principe : champ hex tapable + bouton qui ouvre le
# selecteur Windows, synchronises dans les deux sens), utilise par "Gerer mes couleurs..." plus
# bas pour l'ajout et la modification d'une entree.
function Afficher-EditeurCouleur([string]$nomExistant, [string]$hexExistant) {
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = if ($nomExistant) { "Modifier une couleur" } else { "Nouvelle couleur" }
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox = $false
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(320, 150)

    $labelNom = New-Object System.Windows.Forms.Label
    $labelNom.Text = "Nom :"
    $labelNom.Location = New-Object System.Drawing.Point(10, 14)
    $labelNom.AutoSize = $true
    $popup.Controls.Add($labelNom)

    $zoneNom = New-Object System.Windows.Forms.TextBox
    $zoneNom.Location = New-Object System.Drawing.Point(10, 34)
    $zoneNom.Size = New-Object System.Drawing.Size(300, 24)
    if ($nomExistant) { $zoneNom.Text = $nomExistant }
    $popup.Controls.Add($zoneNom)

    $labelHex = New-Object System.Windows.Forms.Label
    $labelHex.Text = "Code hex :"
    $labelHex.Location = New-Object System.Drawing.Point(10, 66)
    $labelHex.AutoSize = $true
    $popup.Controls.Add($labelHex)

    $hexDepart = if ($hexExistant) { $hexExistant } else { "#808080" }
    $zoneHex = New-Object System.Windows.Forms.TextBox
    $zoneHex.Location = New-Object System.Drawing.Point(10, 86)
    $zoneHex.Size = New-Object System.Drawing.Size(80, 24)
    $zoneHex.MaxLength = 7
    $zoneHex.Text = $hexDepart
    $popup.Controls.Add($zoneHex)

    $boutonCouleur = New-Object System.Windows.Forms.Button
    $boutonCouleur.Location = New-Object System.Drawing.Point(100, 86)
    $boutonCouleur.Size = New-Object System.Drawing.Size(115, 24)
    $boutonCouleur.FlatStyle = "Flat"
    $boutonCouleur.Cursor = "Hand"
    $boutonCouleur.Tag = $hexDepart
    $boutonCouleur.Text = $hexDepart
    try {
        $boutonCouleur.BackColor = [System.Drawing.ColorTranslator]::FromHtml($hexDepart)
        $boutonCouleur.ForeColor = if (([int]$boutonCouleur.BackColor.R + [int]$boutonCouleur.BackColor.G + [int]$boutonCouleur.BackColor.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
    } catch { }
    $boutonCouleur.Add_Click({
        $dialogueCouleur = New-Object System.Windows.Forms.ColorDialog
        try { $dialogueCouleur.Color = [System.Drawing.ColorTranslator]::FromHtml($boutonCouleur.Tag) } catch { }
        if ($dialogueCouleur.ShowDialog($popup) -eq [System.Windows.Forms.DialogResult]::OK) {
            $c = $dialogueCouleur.Color
            $hexChoisi = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
            $boutonCouleur.Tag = $hexChoisi
            $boutonCouleur.Text = $hexChoisi
            $boutonCouleur.BackColor = $c
            $boutonCouleur.ForeColor = if (([int]$c.R + [int]$c.G + [int]$c.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
            $zoneHex.Text = $hexChoisi
        }
    }.GetNewClosure())
    $popup.Controls.Add($boutonCouleur)

    $zoneHex.Add_Leave({
        $texteHex = $zoneHex.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($texteHex)) { return }
        if (-not $texteHex.StartsWith('#')) { $texteHex = '#' + $texteHex }
        try {
            $c = [System.Drawing.ColorTranslator]::FromHtml($texteHex)
            $hexNormalise = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
            $zoneHex.Text = $hexNormalise
            $boutonCouleur.Tag = $hexNormalise
            $boutonCouleur.Text = $hexNormalise
            $boutonCouleur.BackColor = $c
            $boutonCouleur.ForeColor = if (([int]$c.R + [int]$c.G + [int]$c.B) -lt 380) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black }
        } catch { }
    }.GetNewClosure())

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Location = New-Object System.Drawing.Point(125, 115)
    $btnOK.Size = New-Object System.Drawing.Size(90, 28)
    Rendre-BoutonPlat $btnOK "principal"
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $popup.Controls.Add($btnOK)

    $btnAnnuler = New-Object System.Windows.Forms.Button
    $btnAnnuler.Text = "Annuler"
    $btnAnnuler.Location = New-Object System.Drawing.Point(220, 115)
    $btnAnnuler.Size = New-Object System.Drawing.Size(90, 28)
    Rendre-BoutonPlat $btnAnnuler "discret"
    $btnAnnuler.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnAnnuler)

    $popup.AcceptButton = $btnOK
    $popup.CancelButton = $btnAnnuler

    while ($true) {
        if ($popup.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        $nomSaisi = $zoneNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nomSaisi)) {
            Afficher-Boite "La couleur doit avoir un nom." "Nom manquant" "OK" "Warning" | Out-Null
            continue
        }
        $texteHex = $zoneHex.Text.Trim()
        if (-not $texteHex.StartsWith('#')) { $texteHex = '#' + $texteHex }
        $c = $null
        if (-not [string]::IsNullOrWhiteSpace($zoneHex.Text)) {
            try { $c = [System.Drawing.ColorTranslator]::FromHtml($texteHex) } catch { $c = $null }
        }
        if ($null -eq $c) {
            Afficher-Boite "Code couleur invalide : '$($zoneHex.Text)'.`r`n`r`nFormat attendu : #RRGGBB (ex: #FF8800) ou RRGGBB sans le #." "Code hex invalide" "OK" "Warning" | Out-Null
            continue
        }
        $hexValide = "#{0:X2}{1:X2}{2:X2}" -f $c.R, $c.G, $c.B
        return @{ Nom = $nomSaisi; Hex = $hexValide }
    }
}

# Fenetre de gestion ("Gerer mes couleurs..." 12/10/2026, Tomyn : "mettre a parti de couleur...
# mettre aussi mes trio ca c'est pas un probleme, au pire je ferai au fur et a mesure que je
# rentre des couleurs") - liste plate, independante de $TRIOS : chaque entree est une couleur de
# stock individuelle, pas encore groupee en trio. Sert de reservoir a "Suggerer des trios depuis
# mes couleurs..." juste apres.
function Afficher-GestionCouleurs {
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = "Gerer mes couleurs"
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox = $false
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(380, 428)

    $liste = New-Object System.Windows.Forms.ListBox
    $liste.Location = New-Object System.Drawing.Point(10, 10)
    $liste.Size = New-Object System.Drawing.Size(360, 270)
    # 12/10/2026, Tomyn : "meme principe pour Gerer mes couleurs" - meme multi-selection que deja
    # faite dans "Gerer mes trios..." et "Suggerer des trios depuis mes couleurs...".
    $liste.SelectionMode = "MultiExtended"
    $popup.Controls.Add($liste)

    $rafraichirListe = {
        $liste.Items.Clear()
        foreach ($c in $script:MesCouleurs) { [void]$liste.Items.Add("$($c.Nom)  -  $($c.Hex)") }
    }
    & $rafraichirListe

    $btnToutSelectionnerCouleur = New-Object System.Windows.Forms.Button
    $btnToutSelectionnerCouleur.Text = "Tout selectionner"
    $btnToutSelectionnerCouleur.Location = New-Object System.Drawing.Point(10, 288)
    $btnToutSelectionnerCouleur.Size = New-Object System.Drawing.Size(175, 26)
    Rendre-BoutonPlat $btnToutSelectionnerCouleur "secondaire"
    $btnToutSelectionnerCouleur.Add_Click({
        for ($i = 0; $i -lt $liste.Items.Count; $i++) { $liste.SetSelected($i, $true) }
    }.GetNewClosure())
    $popup.Controls.Add($btnToutSelectionnerCouleur)

    $btnAucuneSelectionCouleur = New-Object System.Windows.Forms.Button
    $btnAucuneSelectionCouleur.Text = "Aucune selection"
    $btnAucuneSelectionCouleur.Location = New-Object System.Drawing.Point(194, 288)
    $btnAucuneSelectionCouleur.Size = New-Object System.Drawing.Size(176, 26)
    Rendre-BoutonPlat $btnAucuneSelectionCouleur "discret"
    $btnAucuneSelectionCouleur.Add_Click({
        $liste.ClearSelected()
    }.GetNewClosure())
    $popup.Controls.Add($btnAucuneSelectionCouleur)

    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "Ajouter..."
    $btnAjouter.Location = New-Object System.Drawing.Point(10, 322)
    $btnAjouter.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnAjouter "secondaire"
    # PAS de .GetNewClosure() ici (12/10/2026, bug trouve suite a un test de Tomyn : le bouton
    # fermait bien la petite fenetre "Nouvelle couleur" mais la couleur ne ressortait jamais dans la
    # liste). GetNewClosure() donne au scriptblock sa PROPRE copie privee de la portee de script :
    # "$script:MesCouleurs += ..." a l'interieur remplace alors la variable dans cette copie privee,
    # invisible du reste du programme (qui continue de voir l'ancienne liste, jamais mise a jour) -
    # un index-assignment (Modifier, plus bas) ou une mutation de hashtable (Demander-
    # NomEtSauvegarderTrio) passent inapercus car ils modifient l'objet en place au lieu de
    # remplacer la variable, d'ou le bug invisible seulement ici. Pas besoin de GetNewClosure() de
    # toute facon : ce bouton n'est pas cree dans une boucle (contrairement aux boutons "Sauvegarder"
    # par ligne plus bas, qui en ont reellement besoin pour capturer LEUR propre combo) - $liste et
    # $rafraichirListe restent resolus normalement tant que ce popup est ouvert.
    $btnAjouter.Add_Click({
        try {
            $resultat = Afficher-EditeurCouleur $null $null
            if ($resultat) {
                # 12/10/2026, idee d'amelioration validee "vaut le coup" : avertit si la couleur
                # saisie est quasi-identique a une deja dans le stock, au lieu de l'empiler sans
                # rien dire - Tomyn garde le dernier mot (Oui = ajoute quand meme).
                $procheExistante = Obtenir-CouleurProcheDansStock $script:MesCouleurs $resultat.Hex
                if ($procheExistante) {
                    $messageProche = "'$($resultat.Nom)' ($($resultat.Hex)) est tres proche de '$($procheExistante.Couleur.Nom)' ($($procheExistante.Couleur.Hex)) deja dans ton stock (ecart $([Math]::Round($procheExistante.Distance, 1))).`r`n`r`nL'ajouter quand meme ?"
                    $reponseProche = Afficher-Boite $messageProche "Couleur tres proche d'une existante" "YesNo" "Warning"
                    if ($reponseProche -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                }
                $script:MesCouleurs += $resultat
                Sauvegarder-MesCouleurs $script:MesCouleurs
                & $rafraichirListe
            }
        } catch {
            # 12/10/2026 : affiche l'erreur reelle au lieu de la laisser disparaitre en silence
            # (Tomyn a vu la fenetre se fermer sans que rien n'apparaisse, sans aucun message) - si
            # ca se reproduit, ce message donnera la vraie cause au lieu d'une supposition.
            Afficher-Boite "Erreur en ajoutant la couleur :`r`n`r`n$_" "Erreur inattendue" "OK" "Error" | Out-Null
        }
    })
    $popup.Controls.Add($btnAjouter)

    $btnModifier = New-Object System.Windows.Forms.Button
    $btnModifier.Text = "Modifier..."
    $btnModifier.Location = New-Object System.Drawing.Point(132, 322)
    $btnModifier.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnModifier "secondaire"
    # 12/10/2026 : ".GetNewClosure()" retire ici aussi (meme famille de bug que sur "Ajouter"/
    # "Supprimer" plus haut, juste moins visible). GetNewClosure() fige une copie PRIVEE du
    # "$script:MesCouleurs" de CE moment-la (ouverture du popup) ; "Ajouter" (plus de closure,
    # corrige plus tot) ecrit maintenant dans la VRAIE variable de script en dehors de cette copie
    # figee - donc si on ajoute une couleur PUIS qu'on clique Modifier dans le MEME popup, cette
    # copie privee de Modifier n'a jamais vu l'ajout (ou pire, reste sur $null si le popup a ete
    # ouvert avant la toute premiere couleur) : "Indexation impossible dans un tableau Null".
    # Comme pour "Ajouter", pas besoin de GetNewClosure() : ce bouton n'est pas cree dans une
    # boucle, $liste/$rafraichirListe restent resolus normalement tant que le popup est ouvert.
    $btnModifier.Add_Click({
        try {
            # 12/10/2026 : "Modifier..." reste limite a UNE SEULE couleur a la fois (meme logique
            # que "Modifier..." dans "Gerer mes trios...") - message different de 0 vs 2+ selections.
            if ($liste.SelectedItems.Count -eq 0) {
                Afficher-Boite "Choisis d'abord une couleur dans la liste." "Aucune selection" "OK" "Warning" | Out-Null
                return
            }
            if ($liste.SelectedItems.Count -gt 1) {
                Afficher-Boite "Choisis une seule couleur a la fois pour la modifier (plusieurs sont selectionnees)." "Plusieurs couleurs selectionnees" "OK" "Warning" | Out-Null
                return
            }
            $index = $liste.SelectedIndex
            $couleurActuelle = $script:MesCouleurs[$index]
            $resultat = Afficher-EditeurCouleur $couleurActuelle.Nom $couleurActuelle.Hex
            if ($resultat) {
                $procheExistante = Obtenir-CouleurProcheDansStock $script:MesCouleurs $resultat.Hex $index
                if ($procheExistante) {
                    $messageProche = "'$($resultat.Nom)' ($($resultat.Hex)) est tres proche de '$($procheExistante.Couleur.Nom)' ($($procheExistante.Couleur.Hex)) deja dans ton stock (ecart $([Math]::Round($procheExistante.Distance, 1))).`r`n`r`nEnregistrer quand meme ?"
                    $reponseProche = Afficher-Boite $messageProche "Couleur tres proche d'une existante" "YesNo" "Warning"
                    if ($reponseProche -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                }
                $script:MesCouleurs[$index] = $resultat
                Sauvegarder-MesCouleurs $script:MesCouleurs
                & $rafraichirListe
            }
        } catch {
            Afficher-Boite "Erreur en modifiant la couleur :`r`n`r`n$_" "Erreur inattendue" "OK" "Error" | Out-Null
        }
    })
    $popup.Controls.Add($btnModifier)

    $btnSupprimer = New-Object System.Windows.Forms.Button
    $btnSupprimer.Text = "Supprimer"
    $btnSupprimer.Location = New-Object System.Drawing.Point(254, 322)
    $btnSupprimer.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnSupprimer "danger"
    # PAS de .GetNewClosure() ici non plus (meme bug, meme raison que sur "Ajouter" ci-dessus :
    # "$script:MesCouleurs = @(...)" remplace la variable - une mutation d'objet en place
    # survivrait a GetNewClosure(), pas un remplacement de variable).
    # 12/10/2026, Tomyn : "meme principe pour Gerer mes couleurs" - supprime maintenant TOUTES les
    # couleurs selectionnees d'un coup (une seule comme avant si une seule est selectionnee), avec
    # tous les trios personnalises lies a N'IMPORTE LAQUELLE d'entre elles repere en une seule
    # passe (pas une recherche separee par couleur, pour ne pas lister un meme trio plusieurs fois
    # s'il utilise 2 couleurs supprimees a la fois).
    $btnSupprimer.Add_Click({
        try {
            if ($liste.SelectedItems.Count -eq 0) {
                Afficher-Boite "Choisis d'abord au moins une couleur dans la liste." "Aucune selection" "OK" "Warning" | Out-Null
                return
            }
            # Indices tries en ordre DECROISSANT - indispensable pour la reconstruction de liste plus
            # bas : supprimer un index eleve d'abord ne decale pas ceux, plus petits, qui restent a
            # traiter (le meme risque que documente a l'origine pour une suppression a un seul index).
            $indicesASupprimer = @($liste.SelectedIndices | Sort-Object -Descending)
            $couleursASupprimer = @($indicesASupprimer | ForEach-Object { $script:MesCouleurs[$_] })
            $hexASupprimerEnMajuscules = @($couleursASupprimer | ForEach-Object { $_.Hex.ToUpper() })

            # 12/10/2026, Tomyn : "des que je supprime une couleur, tous les trios lies a cette
            # couleur se suppriment en meme temps" - uniquement les trios PERSONNALISES (jamais
            # Pastel/Neon, qui ne dependent pas du stock de couleurs). Repere AVANT de demander
            # confirmation, pour que le message liste precisement ce qui va disparaitre. Boucle
            # explicite (pas de Where-Object imbrique) pour eviter toute confusion entre le $_ de la
            # boucle externe (nom de trio) et celui d'une boucle interne (composant du trio).
            $triosLies = New-Object System.Collections.Generic.List[string]
            foreach ($nomTrio in $TRIOS.Keys) {
                if ($script:NomsTriosPredefinis -contains $nomTrio) { continue }
                $contientUneCouleurSupprimee = $false
                foreach ($composant in @($TRIOS[$nomTrio])) {
                    if ($hexASupprimerEnMajuscules -contains $composant.Hex.ToUpper()) { $contientUneCouleurSupprimee = $true; break }
                }
                if ($contientUneCouleurSupprimee) { [void]$triosLies.Add($nomTrio) }
            }
            $triosLies = @($triosLies)

            $nomsASupprimer = @($couleursASupprimer | ForEach-Object { $_.Nom })
            $messageConfirmation = if ($nomsASupprimer.Count -eq 1) {
                "Supprimer definitivement la couleur '$($nomsASupprimer[0])' ?"
            } else {
                "Supprimer definitivement ces $($nomsASupprimer.Count) couleurs ?`r`n`r`n - " + ($nomsASupprimer -join "`r`n - ")
            }
            if ($triosLies.Count -gt 0) {
                $messageConfirmation += "`r`n`r`nCeci supprimera aussi $($triosLies.Count) trio(s) personnalise(s) qui les utilisent :`r`n - " + ($triosLies -join "`r`n - ")
            }
            if ((Afficher-Boite $messageConfirmation "Confirmer la suppression" "YesNo" "Question") -ne [System.Windows.Forms.DialogResult]::Yes) { return }

            # Snapshot AVANT suppression pour "Annuler" (13/10/2026, idee "vaut le coup" validee par
            # Tomyn) - garde a la fois l'etat des couleurs ET de $TRIOS (la cascade peut en supprimer
            # juste apres), pour pouvoir tout restaurer d'un coup quelle que soit la fenetre ou
            # l'annulation est declenchee ensuite.
            $sauvegardeTriosAvant = @{}
            foreach ($nom in $TRIOS.Keys) { $sauvegardeTriosAvant[$nom] = $TRIOS[$nom] }
            $script:DerniereSuppression = @{ Type = "Couleurs"; Couleurs = $script:MesCouleurs.Clone(); Trios = $sauvegardeTriosAvant }

            # Suppression par INDEX, pas par valeur (une comparaison par valeur laisserait passer un
            # doublon exact nom+hex, et en supprimerait potentiellement plusieurs d'un coup) -
            # reconstruction explicite de la liste sans ces index precis.
            $nouvelleListe = New-Object System.Collections.Generic.List[object]
            for ($i = 0; $i -lt $script:MesCouleurs.Count; $i++) {
                if ($indicesASupprimer -notcontains $i) { [void]$nouvelleListe.Add($script:MesCouleurs[$i]) }
            }
            # 12/10/2026 : "@($nouvelleListe)" plantait avec "Les types des arguments ne correspondent
            # pas." (reproduit et confirme) - bug PowerShell ou "New-Object ... List[object]" wrappe
            # dans "@()" directement (sans passer par un pipeline) echoue, meme avec une liste valide
            # et non vide. "| Sort-Object"/"| Select-Object" avant "@()" evitent le probleme ailleurs
            # dans ce fichier (le pipeline enumere deja), mais ici il n'y a rien a trier - .ToArray()
            # contourne le souci proprement (vraie methode .NET, pas de passage par "@()").
            $script:MesCouleurs = $nouvelleListe.ToArray()
            Sauvegarder-MesCouleurs $script:MesCouleurs

            if ($triosLies.Count -gt 0) {
                foreach ($nomTrio in $triosLies) { $TRIOS.Remove($nomTrio) }
                $personnalisesActuels = @{}
                foreach ($nom in $TRIOS.Keys) {
                    if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
                }
                Sauvegarder-TriosPersonnalises $personnalisesActuels
                RafraichirListeTrios
            }

            & $rafraichirListe
            $btnAnnulerSuppressionCouleur.Enabled = $true
        } catch {
            Afficher-Boite "Erreur en supprimant la/les couleur(s) :`r`n`r`n$_" "Erreur inattendue" "OK" "Error" | Out-Null
        }
    })
    $popup.Controls.Add($btnSupprimer)

    # Touche Suppr (13/10/2026, idee "vaut le coup" validee par Tomyn) - meme principe que dans
    # "Gerer mes trios..." : declenche le bouton "Supprimer" lui-meme (confirmation comprise) au
    # lieu de dupliquer sa logique.
    $liste.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
            $_.SuppressKeyPress = $true
            $btnSupprimer.PerformClick()
        }
    })

    # Bouton "Annuler" (13/10/2026) - meme principe que dans "Gerer mes trios..." : desactive a
    # l'ouverture sauf suppression encore annulable, se desactive lui-meme apres usage. PAS de
    # .GetNewClosure() (coherent avec Ajouter/Modifier/Supprimer ci-dessus : $rafraichirListe est
    # un scriptblock reassigne au complet a l'ouverture de CE popup, pas mute en place - une copie
    # figee par GetNewClosure() resterait valide ici en pratique, mais autant garder le meme
    # reflexe partout dans cette fenetre).
    $btnAnnulerSuppressionCouleur = New-Object System.Windows.Forms.Button
    $btnAnnulerSuppressionCouleur.Text = "Annuler la derniere suppression"
    $btnAnnulerSuppressionCouleur.Location = New-Object System.Drawing.Point(10, 356)
    $btnAnnulerSuppressionCouleur.Size = New-Object System.Drawing.Size(360, 26)
    Rendre-BoutonPlat $btnAnnulerSuppressionCouleur "secondaire"
    $btnAnnulerSuppressionCouleur.Enabled = ($null -ne $script:DerniereSuppression)
    $btnAnnulerSuppressionCouleur.Add_Click({
        if (Annuler-DerniereSuppression) {
            & $rafraichirListe
            $btnAnnulerSuppressionCouleur.Enabled = $false
        }
    })
    $popup.Controls.Add($btnAnnulerSuppressionCouleur)

    $btnFermer = New-Object System.Windows.Forms.Button
    $btnFermer.Text = "Fermer"
    $btnFermer.Location = New-Object System.Drawing.Point(254, 390)
    $btnFermer.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnFermer "discret"
    $btnFermer.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnFermer)
    $popup.CancelButton = $btnFermer

    [void]$popup.ShowDialog($form)
}

# Teste TOUTES les combinaisons de 3 couleurs possibles dans une liste plate et renvoie les
# meilleures par aire de couverture Lab decroissante (12/10/2026, Tomyn : reproduit dans l'outil
# l'exercice "fais-moi des trios avec mon stock" fait a la main en conversation). Reutilise
# Obtenir-AireCouvertureTrio deja ecrite pour noter un trio "a vide" (sans fichier precis) - meme
# metrique que partout ailleurs dans l'outil pour rester coherent. $topN limite le nombre de
# resultats renvoyes (pas d'interet a afficher les centaines de combinaisons possibles des qu'on
# a plus de 6-7 couleurs en stock).
#
# 12/10/2026, Tomyn : un classement brut par aire ressort quasiment toujours une combinaison avec du
# blanc en tete (le blanc elargit beaucoup l'aire, cf. Obtenir-TrioEstBlancDominant/le meme souci deja
# traite pour "Suggerer 5 trios differents pour ce fichier...") - gênant car Tomyn a justement du mal
# a reapprovisionner le blanc, donc il ne veut pas que le TOP $topN ne soit que des variantes "avec
# blanc". Meme regle que pour les 5 trios par fichier : un seul resultat "a dominante blanche" (L*
# Lab > 90) est garde dans le classement renvoye, les autres vont aux combinaisons SANS blanc meme si
# elles ont une aire plus petite - toujours triees par aire decroissante a l'interieur de ces deux
# groupes. Ce plafond du blanc s'applique TOUJOURS, meme sans limite de nombre de resultats (12/10/2026,
# Tomyn : "pas de limite... si ça depasse la fenetre, un petit ascenseur" - $topN -le 0 renvoie
# desormais tout ce qui passe le filtre blanc au lieu de renvoyer la liste brute non filtree).
function Obtenir-MeilleuresCombosDepuisCouleurs([array]$couleurs, [int]$topN) {
    # 12/10/2026 : Tomyn a un cas reproductible ou SES 3 COULEURS D'ORIGINE (PURPLE/ORANGE/PINK, deja
    # verifiees valides a la main dans "Gerer mes couleurs") ne proposent plus aucun trio, alors que
    # les memes 3 couleurs + 3 nouvelles fonctionnent. Le "catch { }" plus bas avalait silencieusement
    # toute erreur de calcul par combo - on la garde maintenant dans $script:DerniereErreursCombos
    # pour pouvoir l'afficher dans la fenetre au lieu de deviner.
    $script:DerniereErreursCombos = New-Object System.Collections.Generic.List[string]
    $resultats = New-Object System.Collections.Generic.List[object]
    $n = $couleurs.Count
    if ($n -lt 3) { return @() }
    for ($i = 0; $i -lt $n - 2; $i++) {
        for ($j = $i + 1; $j -lt $n - 1; $j++) {
            for ($k = $j + 1; $k -lt $n; $k++) {
                $combo = @($couleurs[$i], $couleurs[$j], $couleurs[$k])
                try {
                    $aire = Obtenir-AireCouvertureTrio $combo
                    $resultats.Add(@{ Composants = $combo; Aire = $aire })
                } catch {
                    $noms = ($combo | ForEach-Object { "$($_.Nom)=[$($_.Hex)]" }) -join ", "
                    [void]$script:DerniereErreursCombos.Add("$noms -> $_")
                }
            }
        }
    }
    $tries = @($resultats | Sort-Object -Property Aire -Descending)

    # 13/10/2026, Tomyn : "si je rajoute une couleur et qu'ensuite je clique sur suggerer des
    # trios de mes couleurs il faut pas qu'il me repropose les trios deja sauvegardes dans la
    # liste" - un trio deja present dans $TRIOS (predefini ou personnalise) n'a aucun interet a
    # etre re-suggere ici. Comparaison par ENSEMBLE de teintes (les 3 Hex, tries, insensibles a
    # la casse) plutot que par nom, pour reconnaitre la meme combinaison meme dans un ordre
    # different.
    $ensemblesTriosExistants = New-Object System.Collections.Generic.List[string]
    foreach ($nomTrio in $TRIOS.Keys) {
        $hexTrio = @($TRIOS[$nomTrio] | ForEach-Object { $_.Hex.ToUpperInvariant() } | Sort-Object)
        [void]$ensemblesTriosExistants.Add(($hexTrio -join "|"))
    }

    $choisis = New-Object System.Collections.Generic.List[object]
    $blancDejaChoisi = $false
    foreach ($candidat in $tries) {
        if ($topN -gt 0 -and $choisis.Count -ge $topN) { break }
        $hexCombo = @($candidat.Composants | ForEach-Object { $_.Hex.ToUpperInvariant() } | Sort-Object)
        if ($ensemblesTriosExistants -contains ($hexCombo -join "|")) { continue }
        $estBlanc = Obtenir-TrioEstBlancDominant $candidat.Composants
        if ($estBlanc -and $blancDejaChoisi) { continue }
        [void]$choisis.Add($candidat)
        if ($estBlanc) { $blancDejaChoisi = $true }
    }
    # "@($choisis)" plante ici pour la meme raison que dans Supprimer (voir commentaire plus bas) -
    # .ToArray() evite le probleme.
    return $choisis.ToArray()
}

# Meme recherche combinatoire que ci-dessus, mais notee par rapport a un FICHIER precis (ecart Lab
# moyen via Verifier-CouvertureAvecCouleurs, meme metrique que "Suggerer un trio pour ce
# fichier...") plutot que l'aire "a vide" du trio - utilisee quand aucun trio deja sauvegarde ne
# colle bien a ce fichier, pour chercher directement dans le stock de couleurs individuelles une
# meilleure combinaison (12/10/2026, Tomyn : "s'il trouve pas le trio adequat ... propose ca ca et
# la ca marche"). Renvoie $null si le stock a moins de 3 couleurs ou si aucune combinaison n'est
# exploitable.
# 16/10/2026 : prend $couleursFichier (deja extrait par l'appelant, voir Obtenir-CouleursFichier3MF)
# au lieu d'un chemin de fichier - evite de redezipper le .3mf une fois par combinaison testee
# (potentiellement des centaines, C(n,3) pour n couleurs en stock) alors que le fichier ne change
# pas d'une combinaison a l'autre.
function Obtenir-MeilleureComboDepuisCouleursPourFichier([array]$couleursFichier, [array]$couleurs) {
    $n = $couleurs.Count
    if ($n -lt 3) { return $null }
    $meilleurResultat = $null
    $meilleurCombo = $null
    for ($i = 0; $i -lt $n - 2; $i++) {
        for ($j = $i + 1; $j -lt $n - 1; $j++) {
            for ($k = $j + 1; $k -lt $n; $k++) {
                $combo = @($couleurs[$i], $couleurs[$j], $couleurs[$k])
                $resultat = Verifier-CouvertureAvecCouleurs $couleursFichier $combo
                if (-not $resultat) { continue }
                if (-not $meilleurResultat -or $resultat.EcartMoyen -lt $meilleurResultat.EcartMoyen) {
                    $meilleurResultat = $resultat
                    $meilleurCombo = $combo
                }
            }
        }
    }
    if (-not $meilleurResultat) { return $null }
    return @{ Composants = $meilleurCombo; Resultat = $meilleurResultat }
}

# Demande un nom (petite boite dediee, pre-remplie avec les noms des composants) et sauvegarde la
# combinaison comme nouveau trio personnalise - factorise (12/10/2026) car utilise a la fois par
# "Suggerer des trios depuis mes couleurs..." ci-dessous et par le repli de "Suggerer un trio pour
# ce fichier..." plus bas quand aucun trio sauvegarde ne convient. Renvoie $true si sauvegarde,
# $false si annule ou nom invalide/refuse.
function Demander-NomEtSauvegarderTrio($popupParent, [array]$composants, [bool]$silencieux = $false) {
    $zoneNomRapide = New-Object System.Windows.Forms.Form
    $zoneNomRapide.Text = "Nom du nouveau trio"
    $zoneNomRapide.StartPosition = "CenterParent"
    $zoneNomRapide.FormBorderStyle = "FixedDialog"
    $zoneNomRapide.MaximizeBox = $false
    $zoneNomRapide.MinimizeBox = $false
    $zoneNomRapide.ClientSize = New-Object System.Drawing.Size(300, 110)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nom :"
    $lbl.Location = New-Object System.Drawing.Point(10, 12)
    $lbl.AutoSize = $true
    $zoneNomRapide.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(10, 32)
    $txt.Size = New-Object System.Drawing.Size(280, 24)
    $txt.Text = ($composants | ForEach-Object { $_.Nom }) -join " + "
    $zoneNomRapide.Controls.Add($txt)
    $btnOKNom = New-Object System.Windows.Forms.Button
    $btnOKNom.Text = "OK"
    $btnOKNom.Location = New-Object System.Drawing.Point(105, 68)
    $btnOKNom.Size = New-Object System.Drawing.Size(90, 28)
    Rendre-BoutonPlat $btnOKNom "principal"
    $btnOKNom.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $zoneNomRapide.Controls.Add($btnOKNom)
    $btnAnnulerNom = New-Object System.Windows.Forms.Button
    $btnAnnulerNom.Text = "Annuler"
    $btnAnnulerNom.Location = New-Object System.Drawing.Point(200, 68)
    $btnAnnulerNom.Size = New-Object System.Drawing.Size(90, 28)
    Rendre-BoutonPlat $btnAnnulerNom "discret"
    $btnAnnulerNom.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $zoneNomRapide.Controls.Add($btnAnnulerNom)
    $zoneNomRapide.AcceptButton = $btnOKNom
    $zoneNomRapide.CancelButton = $btnAnnulerNom
    if ($zoneNomRapide.ShowDialog($popupParent) -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    $nomChoisi = $txt.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($nomChoisi)) { return $null }
    if ($script:NomsTriosPredefinis -contains $nomChoisi) {
        Afficher-Boite "Ce nom est deja utilise par un trio predefini - choisis-en un autre." "Nom reserve" "OK" "Warning" | Out-Null
        return $null
    }
    $TRIOS[$nomChoisi] = $composants
    $personnalisesActuels = @{}
    foreach ($nom in $TRIOS.Keys) {
        if ($script:NomsTriosPredefinis -notcontains $nom) { $personnalisesActuels[$nom] = $TRIOS[$nom] }
    }
    Sauvegarder-TriosPersonnalises $personnalisesActuels
    RafraichirListeTrios
    # 12/10/2026 : $silencieux (par defaut $false, comportement d'origine inchange pour tous les
    # appels existants) permet a Afficher-SuggestionTriosDepuisCouleurs d'enchainer plusieurs
    # sauvegardes sans une boite "Trio enregistre" apres CHAQUE trio - un seul recapitulatif final
    # a la place (voir le bouton "Sauvegarder... " de cette fenetre).
    if (-not $silencieux) {
        Afficher-Boite "Trio '$nomChoisi' enregistre." "Trio sauvegarde" "OK" "Info" | Out-Null
    }
    return $nomChoisi
}

# Fenetre "Suggerer des trios depuis mes couleurs..." (12/10/2026, Tomyn) - classement des
# meilleures combinaisons de 3 parmi $script:MesCouleurs, chacune avec un bouton "Sauvegarder"
# individuel qui l'enregistre directement comme trio personnalise (meme chemin que
# Afficher-GestionTrios : demande juste un nom, puis Sauvegarder-TriosPersonnalises).
function Afficher-SuggestionTriosDepuisCouleurs {
    if ($script:MesCouleurs.Count -lt 3) {
        Afficher-Boite "Il faut au moins 3 couleurs enregistrees dans 'Gerer mes couleurs...' pour pouvoir suggerer des trios." "Pas assez de couleurs" "OK" "Warning" | Out-Null
        return
    }

    # 12/10/2026, Tomyn : "pourquoi se limiter a un top 8... mets pas de limite, au pire un petit
    # ascenseur pour descendre plus bas" - plus de plafond arbitraire sur le nombre de combinaisons
    # affichees (0 = pas de limite, cf. Obtenir-MeilleuresCombosDepuisCouleurs), fenetre a taille
    # fixe raisonnable avec un panneau a defilement (AutoScroll) pour le reste de la liste au lieu
    # d'agrandir la fenetre a chaque couleur ajoutee au stock.
    # 12/10/2026 : CINQ versions successives (Panel AutoScroll, FlowLayoutPanel, ListBox natif,
    # ListBox OwnerDraw, RichTextBox) ont toutes echoue exactement pareil chez Tomyn - seule une
    # fraction du contenu se peint, toujours la meme quel que soit le controle. MAIS "Gerer mes
    # couleurs" (Afficher-GestionCouleurs, juste au-dessus dans ce fichier) affiche sa liste de
    # couleurs PARFAITEMENT chez lui, a chaque test, sans exception. L'unique vraie difference
    # structurelle entre les deux : "Gerer mes couleurs" est une fenetre a TAILLE FIXE
    # (FormBorderStyle "FixedDialog", pas de MaximizeBox) avec des controles en Location/Size fixes,
    # alors que cette fenetre-ci etait Sizable/MaximizeBox avec une disposition "Dock" (Top/Bottom/
    # Fill) qui se recalcule a la demande. Reconstruite ici a l'identique du modele qui marche :
    # taille fixe, ListBox simple en Location/Size fixes (pas de Dock, pas de AutoScroll, pas
    # d'OwnerDraw) - exactement la recette qui fonctionne sans probleme pour "Gerer mes couleurs".
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = "Trios suggeres depuis mes couleurs"
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox = $false
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(480, 448)

    $labelIntro = New-Object System.Windows.Forms.Label
    $labelIntro.Text = "Meilleures combinaisons de 3 (aire la plus large en premier, 1 seule avec du blanc) :"
    $labelIntro.ForeColor = $THEME.Texte
    $labelIntro.Location = New-Object System.Drawing.Point(10, 10)
    $labelIntro.Size = New-Object System.Drawing.Size(460, 32)
    $popup.Controls.Add($labelIntro)

    # $liste garde EXACTEMENT la meme Location/Size qu'avant (10,46,460,270) - c'est la recette
    # qui a enfin corrige le bug d'affichage de cette fenetre (voir le commentaire plus haut), donc
    # on ne touche pas a ce controle precis, seulement a ce qu'il y a autour.
    $liste = New-Object System.Windows.Forms.ListBox
    $liste.Location = New-Object System.Drawing.Point(10, 46)
    $liste.Size = New-Object System.Drawing.Size(460, 270)
    # 12/10/2026, Tomyn : "possibilite de selectionner un ou plusieurs ou tous pour ajouter
    # un/plusieurs/tous les trio d'un coup" - meme principe que "Gerer mes trios..." juste avant.
    $liste.SelectionMode = "MultiExtended"
    $popup.Controls.Add($liste)

    $btnToutSelectionnerSuggestion = New-Object System.Windows.Forms.Button
    $btnToutSelectionnerSuggestion.Text = "Tout selectionner"
    $btnToutSelectionnerSuggestion.Location = New-Object System.Drawing.Point(10, 320)
    $btnToutSelectionnerSuggestion.Size = New-Object System.Drawing.Size(150, 24)
    Rendre-BoutonPlat $btnToutSelectionnerSuggestion "secondaire"
    $popup.Controls.Add($btnToutSelectionnerSuggestion)

    $btnAucuneSelectionSuggestion = New-Object System.Windows.Forms.Button
    $btnAucuneSelectionSuggestion.Text = "Aucune selection"
    $btnAucuneSelectionSuggestion.Location = New-Object System.Drawing.Point(166, 320)
    $btnAucuneSelectionSuggestion.Size = New-Object System.Drawing.Size(150, 24)
    Rendre-BoutonPlat $btnAucuneSelectionSuggestion "discret"
    $popup.Controls.Add($btnAucuneSelectionSuggestion)

    $labelChoix = New-Object System.Windows.Forms.Label
    $labelChoix.Text = "Trio selectionne :"
    $labelChoix.ForeColor = $THEME.Texte
    $labelChoix.Location = New-Object System.Drawing.Point(10, 354)
    $labelChoix.AutoSize = $true
    $popup.Controls.Add($labelChoix)

    $pastillesPreview = @()
    for ($p = 0; $p -lt 3; $p++) {
        $pastille = New-Object System.Windows.Forms.Panel
        $pastille.Location = New-Object System.Drawing.Point((130 + $p * 24), 350)
        $pastille.Size = New-Object System.Drawing.Size(20, 20)
        $pastille.BorderStyle = "FixedSingle"
        $popup.Controls.Add($pastille)
        $pastillesPreview += $pastille
    }

    $btnSauvegarder = New-Object System.Windows.Forms.Button
    $btnSauvegarder.Text = "Sauvegarder la selection..."
    $btnSauvegarder.Location = New-Object System.Drawing.Point(10, 386)
    $btnSauvegarder.Size = New-Object System.Drawing.Size(215, 30)
    Rendre-BoutonPlat $btnSauvegarder "secondaire"
    $btnSauvegarder.Enabled = $false
    $popup.Controls.Add($btnSauvegarder)

    $btnFermerSuggestion = New-Object System.Windows.Forms.Button
    $btnFermerSuggestion.Text = "Fermer"
    $btnFermerSuggestion.Location = New-Object System.Drawing.Point(355, 386)
    $btnFermerSuggestion.Size = New-Object System.Drawing.Size(115, 30)
    Rendre-BoutonPlat $btnFermerSuggestion "discret"
    $btnFermerSuggestion.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnFermerSuggestion)
    $popup.CancelButton = $btnFermerSuggestion

    $popup.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $meilleures = @(Obtenir-MeilleuresCombosDepuisCouleurs $script:MesCouleurs 0)
    $popup.Cursor = [System.Windows.Forms.Cursors]::Default

    if ($meilleures.Count -eq 0) {
        $texteDiag = "Aucune combinaison exploitable. Couleurs chargees (" + $script:MesCouleurs.Count + ") :"
        foreach ($c in $script:MesCouleurs) { $texteDiag += " | $($c.Nom)=$($c.Hex)" }
        if ($script:DerniereErreursCombos -and $script:DerniereErreursCombos.Count -gt 0) {
            foreach ($e in $script:DerniereErreursCombos) { $texteDiag += " | ERREUR: $e" }
        }
        [void]$liste.Items.Add($texteDiag)
        $liste.Enabled = $false
        $btnSauvegarder.Enabled = $false
        $btnToutSelectionnerSuggestion.Enabled = $false
        $btnAucuneSelectionSuggestion.Enabled = $false
    } else {
        foreach ($combo in $meilleures) {
            $nomsCombo = ($combo.Composants | ForEach-Object { "$($_.Nom) ($($_.Hex))" }) -join "  +  "
            [void]$liste.Items.Add("$nomsCombo   -   aire $([Math]::Round($combo.Aire, 0))")
        }
        if ($script:DerniereErreursCombos -and $script:DerniereErreursCombos.Count -gt 0) {
            [void]$liste.Items.Add("--- $($script:DerniereErreursCombos.Count) combinaison(s) ignoree(s), erreur de calcul ---")
            foreach ($e in $script:DerniereErreursCombos) { [void]$liste.Items.Add("  $e") }
        }

        # 12/10/2026 : avec le multi-selection, le bouton "Sauvegarder" s'active des qu'AU MOINS UN
        # vrai trio (index < $meilleures.Count, donc pas une des lignes de diagnostic d'erreur
        # ajoutees juste au-dessus) est selectionne. Les pastilles d'apercu, elles, n'ont de sens que
        # pour UNE seule selection a la fois - restent vides sinon (pas d'ambiguite possible avec 3
        # emplacements pour potentiellement plusieurs trios differents).
        $metAJourPreview = {
            $indicesValides = @($liste.SelectedIndices | Where-Object { $_ -lt $meilleures.Count })
            $btnSauvegarder.Enabled = $indicesValides.Count -gt 0
            if ($indicesValides.Count -eq 1) {
                $combo = $meilleures[$indicesValides[0]]
                for ($p = 0; $p -lt 3; $p++) {
                    try { $pastillesPreview[$p].BackColor = [System.Drawing.ColorTranslator]::FromHtml($combo.Composants[$p].Hex) } catch { }
                }
            } else {
                foreach ($pas in $pastillesPreview) { $pas.BackColor = $THEME.Surface }
            }
        }.GetNewClosure()
        $liste.Add_SelectedIndexChanged($metAJourPreview)

        $btnToutSelectionnerSuggestion.Add_Click({
            for ($i = 0; $i -lt $meilleures.Count; $i++) { $liste.SetSelected($i, $true) }
        }.GetNewClosure())

        $btnAucuneSelectionSuggestion.Add_Click({
            $liste.ClearSelected()
        }.GetNewClosure())

        # 12/10/2026, Tomyn : "possibilite de selectionner un ou plusieurs ou tous pour ajouter
        # un/plusieurs/tous les trio d'un coup" - enchaine Demander-NomEtSauvegarderTrio (qui demande
        # un nom) pour CHAQUE trio selectionne, en mode silencieux (pas de boite "Trio enregistre"
        # apres chacun), avec un seul recapitulatif a la fin. Annuler la boite de nom pour un trio
        # n'interrompt pas les suivants - juste compte comme non sauvegarde dans le recapitulatif.
        $btnSauvegarder.Add_Click({
            $indicesValides = @($liste.SelectedIndices | Where-Object { $_ -lt $meilleures.Count } | Sort-Object)
            if ($indicesValides.Count -eq 0) { return }
            $nomsSauvegardes = New-Object System.Collections.Generic.List[string]
            $nombreAnnules = 0
            foreach ($idx in $indicesValides) {
                $nomSauvegarde = Demander-NomEtSauvegarderTrio $popup $meilleures[$idx].Composants $true
                if ($nomSauvegarde) { [void]$nomsSauvegardes.Add($nomSauvegarde) } else { $nombreAnnules++ }
            }
            if ($nomsSauvegardes.Count -eq 1) {
                Afficher-Boite "Trio '$($nomsSauvegardes[0])' enregistre." "Trio sauvegarde" "OK" "Info" | Out-Null
            } elseif ($nomsSauvegardes.Count -gt 1) {
                $messageRecap = "$($nomsSauvegardes.Count) trio(s) enregistre(s) :`r`n - " + ($nomsSauvegardes -join "`r`n - ")
                if ($nombreAnnules -gt 0) { $messageRecap += "`r`n`r`n$nombreAnnules annule(s) (nom non saisi)." }
                Afficher-Boite $messageRecap "Trios sauvegardes" "OK" "Info" | Out-Null
            }
        }.GetNewClosure())

        $liste.SelectedIndex = 0
        $labelIntro.Text = "Meilleures combinaisons de 3 ($($meilleures.Count) trouvee(s), aire la plus large en premier, 1 seule avec du blanc) :"
    }

    [void]$popup.ShowDialog($form)
}


# ============================== APERCU AVANT / APRES (10/10/2026) ==============================
# Decode UN code paint_color (meme format que celui explique en detail dans Traiter-Fichier3MF plus
# bas - voir ses commentaires) et retourne juste le PREMIER numero de filament qu'il contient (sans
# le decaler, contrairement a la version utilisee pendant le melange). Pour un apercu rapide, se
# contenter du premier numero suffit meme pour un triangle coupe en plusieurs morceaux a la frontiere
# entre deux couleurs (de toute facon tres minoritaires et visuellement un detail de bord).
function Decoder-EtatPaintColor([string]$texte) {
    $nibblesEntree = New-Object System.Collections.Generic.List[int]
    for ($i = $texte.Length - 1; $i -ge 0; $i--) {
        $nibblesEntree.Add([System.Convert]::ToInt32([string]$texte[$i], 16))
    }
    $position = 0
    $premierEtat = $null
    $pile = New-Object System.Collections.Generic.List[int]
    while ($true) {
        $code = $nibblesEntree[$position]; $position++
        $cotesDivises = $code -band 0x3
        $estDivise = $cotesDivises -ne 0
        $nombreEnfants = 0
        if ($estDivise) {
            $nombreEnfants = $cotesDivises + 1
        } else {
            if (($code -band 0xC) -eq 0xC) {
                $n2 = $nibblesEntree[$position]; $position++
                if ($n2 -eq 0xF) {
                    $n3 = $nibblesEntree[$position]; $position++
                    $etat = $n3 + 18
                } else {
                    $etat = $n2 + 3
                }
            } else {
                $etat = $code -shr 2
            }
            if ($null -eq $premierEtat) { $premierEtat = $etat }
        }
        if ($pile.Count -eq 0) {
            if ($estDivise) { $pile.Add($nombreEnfants); continue } else { break }
        }
        if ($estDivise) {
            $pile.Add($nombreEnfants)
        } else {
            $pile[$pile.Count - 1] = $pile[$pile.Count - 1] - 1
        }
        while ($pile.Count -gt 0 -and $pile[$pile.Count - 1] -eq 0) {
            $pile.RemoveAt($pile.Count - 1)
            if ($pile.Count -gt 0) { $pile[$pile.Count - 1] = $pile[$pile.Count - 1] - 1 }
        }
        if ($pile.Count -eq 0) { break }
    }
    return $premierEtat
}

# Juste le NOMBRE de couleurs detectees dans un .3mf (pas tout le maillage comme
# Lire-TrianglesPourApercu ci-dessous) - utilise pour pre-remplir le selecteur "nombre de
# melanges" des qu'un fichier est choisi (10/10/2026, demande par Tomyn).
function Obtenir-NombreCouleursDetectees([string]$chemin3mf) {
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("couleurs3mf_" + [guid]::NewGuid().ToString("N"))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($chemin3mf, $dossierTemp)
    try {
        $cheminConfig = Join-Path $dossierTemp "Metadata\project_settings.config"
        if (-not (Test-Path $cheminConfig)) { return 0 }
        $config = Get-Content $cheminConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($config.filament_colour).Count
    } catch {
        return 0
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Liste des couleurs ("filament_colour") d'un .3mf, telles quelles (meme source que
# Obtenir-NombreCouleursDetectees ci-dessus, qui n'en gardait que le compte) - base de la
# verification de couverture PAR FICHIER ci-dessous.
function Obtenir-CouleursFichier3MF([string]$chemin3mf) {
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("couleurs3mf_" + [guid]::NewGuid().ToString("N"))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($chemin3mf, $dossierTemp)
    try {
        $cheminConfig = Join-Path $dossierTemp "Metadata\project_settings.config"
        if (-not (Test-Path $cheminConfig)) { return @() }
        $config = Get-Content $cheminConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($config.filament_colour)
    } catch {
        return @()
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Verification de couverture PAR FICHIER (11/10/2026, Tomyn : "d'autres idees ?" -> "toutes") -
# complement du score "a vide" de Mettre-A-Jour-ApercuTrioSelectionne (qui ne regarde que la
# geometrie du trio) : ici, on prend les couleurs REELLEMENT presentes dans le fichier choisi et
# on verifie, pour chacune, a quelle distance Lab se trouve son MEILLEUR dosage possible avec le
# trio selectionne (meme fonction Trouver-MeilleurDosage que le vrai traitement, mais avec un pas
# plus grossier - 10 au lieu de 5 - pour rester rapide dans un controle "a la demande"). Un seuil
# empirique de 12 (meme echelle Lab que Obtenir-DistanceLab utilisee partout ailleurs) separe "le
# dosage trouve est visuellement tres proche" de "ca va se voir a l'oeil".
# 16/10/2026, Tomyn : "quand j'ai beaucoup de trio perso et que je clique suggerer un trio pour ce
# fichier c'est ultra long" - le vrai cout n'est pas le calcul Lab (rapide), c'est
# Obtenir-CouleursFichier3MF qui DEZIPPE le .3mf sur le disque (ExtractToDirectory, puis nettoyage)
# a CHAQUE appel. Verifier-CouvertureFichier ci-dessous le faisait une fois PAR TRIO teste - avec
# beaucoup de trios personnalises (et pire, la recherche combinatoire dans "mes couleurs" juste en
# dessous, qui peut tester des centaines de combinaisons de 3), ca fait autant de dezippages
# complets du meme fichier, inchange, pour rien. Separe maintenant en deux : cette fonction fait le
# calcul Lab seul, a partir d'une liste de couleurs DEJA extraite (couts fixe, appele une seule
# fois par le code appelant) ; Verifier-CouvertureFichier juste en dessous redevient un simple
# raccourci (extrait puis appelle celle-ci) pour les endroits qui ne testent qu'UN seul trio et
# n'ont donc rien a gagner a se compliquer.
function Verifier-CouvertureAvecCouleurs($couleurs, $trio) {
    if ($couleurs.Count -eq 0) { return $null }
    $primairesRGB = @($trio | ForEach-Object { Obtenir-RGBDepuisHex $_.Hex })
    $seuilEcart = 12.0
    $distances = New-Object System.Collections.Generic.List[double]
    $nombreMalCouvertes = 0
    # 13/10/2026, Tomyn : "pourquoi 2 sur 4 et pas juste 1, ton calcul est trop agressif non ?" -
    # jusqu'ici le resultat ne donnait qu'un total ("X couleur(s) mal rendue(s)"), impossible a
    # verifier sans deviner. On garde maintenant le detail PAR couleur (hex + ecart Lab obtenu avec
    # le meilleur dosage trouve), affiche dans le rapport ci-dessous - Tomyn peut voir directement
    # QUELLES couleurs posent souci plutot que de devoir me croire sur parole.
    #
    # 13/10/2026, suite - cas reel trouve grace au detail ci-dessus : #2A2424 (quasi-noir, teinte
    # chaude) marque "mal rendu" (ecart 14.9) a cote d'un trio BEIGE/WHITE/BLACK - Tomyn : "noir
    # chaud ou noir froid, c'est noir, y'a plus d'espoir". Il a raison : la distance Lab reste
    # geometriquement exacte, mais l'oeil humain distingue tres mal une difference de TEINTE (a*/b*,
    # chaud/froid) quand la LUMINOSITE (L*) est deja tres basse - une nuance qui saute aux yeux en
    # plein jour sur un gris clair devient invisible sur un quasi-noir. On relache donc le seuil de
    # detection (PAS le dosage choisi plus haut, qui reste le plus precis possible) pour les
    # couleurs CIBLES tres sombres : en dessous de L*=25, le seuil augmente progressivement jusqu'a
    # +20 a L*=0 (seuil effectif 32 pour du noir pur), degressif jusqu'a +0 a L*=25 ou le seuil
    # normal de 12 s'applique entier.
    $details = New-Object System.Collections.Generic.List[object]
    foreach ($hex in $couleurs) {
        try {
            $rgbCible = Obtenir-RGBDepuisHex $hex
            $meilleur = Trouver-MeilleurDosage $rgbCible $primairesRGB 10
            $distances.Add($meilleur.Distance)
            $labCible = Convertir-RGBVersLab $rgbCible.R $rgbCible.G $rgbCible.B
            $seuilEffectif = $seuilEcart
            if ($labCible.L -lt 25) { $seuilEffectif += (25 - $labCible.L) * 0.8 }
            $estMalRendue = $meilleur.Distance -gt $seuilEffectif
            if ($estMalRendue) { $nombreMalCouvertes++ }
            [void]$details.Add(@{ Hex = $hex; Distance = $meilleur.Distance; MalRendue = $estMalRendue; SeuilApplique = $seuilEffectif })
        } catch { }
    }
    if ($distances.Count -eq 0) { return $null }
    return @{
        NombreCouleurs      = $couleurs.Count
        NombreMalCouvertes  = $nombreMalCouvertes
        EcartMoyen          = ($distances | Measure-Object -Average).Average
        EcartMax            = ($distances | Measure-Object -Maximum).Maximum
        Details             = $details.ToArray()
    }
}

# Raccourci pour les appelants qui ne testent qu'UN seul trio sur le fichier (extrait les couleurs
# une fois puis delegue a Verifier-CouvertureAvecCouleurs ci-dessus) - inchange niveau API, tous
# les appels existants continuent de marcher tels quels.
function Verifier-CouvertureFichier($chemin3mf, $trio) {
    $couleurs = Obtenir-CouleursFichier3MF $chemin3mf
    return Verifier-CouvertureAvecCouleurs $couleurs $trio
}

# Rapport texte pour un resultat de Verifier-CouvertureFichier - factorise car utilise a la fois
# par le controle simple (un trio) et par la comparaison de deux trios ci-dessous (11/10/2026,
# Tomyn : "1-2-3-4").
function Obtenir-LignesRapportCouverture([string]$nomTrio, $resultat) {
    # L'operateur virgule unaire sur CHAQUE "return" est volontaire (meme piege que
    # Obtenir-PairesTropProches plus haut, trouve en testant precisement CE cas en sandbox) : le cas
    # "$resultat = $null" ne renvoie qu'UNE ligne, et sans la virgule, PowerShell la deballerait en
    # simple chaine au lieu d'un tableau d'une chaine - avec un "+" sur deux tableaux de lignes plus
    # loin (voir le bouton Comparer), ca donnerait un collage sans retours a la ligne au lieu d'un
    # rapport lisible.
    if (-not $resultat) { return ,@("$nomTrio : impossible de lire les couleurs de ce fichier.") }
    $lignes = New-Object System.Collections.Generic.List[string]
    [void]$lignes.Add("$nomTrio :")
    [void]$lignes.Add("  $($resultat.NombreCouleurs) couleur(s) detectee(s) dans le fichier")
    [void]$lignes.Add("  $($resultat.NombreMalCouvertes) couleur(s) risquent d'etre visiblement mal rendues")
    [void]$lignes.Add("  Ecart Lab moyen : $([Math]::Round($resultat.EcartMoyen, 1))")
    [void]$lignes.Add("  Ecart Lab max   : $([Math]::Round($resultat.EcartMax, 1))")
    # 13/10/2026, Tomyn : detail par couleur (quelle(s) couleur(s) exactement, et leur ecart), triee
    # par ecart decroissant - les plus genantes en premier. Montre les "mal rendues" en entier, et
    # garde une ligne recap pour celles qui passent le seuil sans toutes les detailler (pas d'interet
    # a lister 50 bonnes couleurs par souci de couleurs).
    if ($resultat.Details -and $resultat.Details.Count -gt 0) {
        $detailsTries = @($resultat.Details | Sort-Object -Property Distance -Descending)
        $malRendues = @($detailsTries | Where-Object { $_.MalRendue })
        if ($malRendues.Count -gt 0) {
            [void]$lignes.Add("  Couleur(s) a surveiller :")
            foreach ($d in $malRendues) {
                # 13/10/2026, Tomyn : le seuil applique varie pour les couleurs tres sombres (voir
                # Verifier-CouvertureFichier) - affiche a cote de l'ecart quand il differe du seuil
                # normal de 12, pour que ce soit visible sans avoir a deviner pourquoi une couleur
                # presque noire a echappe au classement "a surveiller" malgre un ecart Lab eleve.
                $mentionSeuil = if ($d.SeuilApplique -and [Math]::Round($d.SeuilApplique, 1) -ne 12.0) { " - seuil applique $([Math]::Round($d.SeuilApplique, 1)) (couleur tres sombre)" } else { "" }
                [void]$lignes.Add("    $($d.Hex)  (ecart Lab $([Math]::Round($d.Distance, 1))$mentionSeuil)")
            }
        }
        $bienRendues = $detailsTries.Count - $malRendues.Count
        if ($bienRendues -gt 0) {
            [void]$lignes.Add("  (+ $bienRendues couleur(s) bien rendue(s), seuil 12 - plus haut pour les tons tres sombres)")
        }
    }
    return ,$lignes.ToArray()
}

# Export du rapport de couverture dans un .txt a cote du fichier .3mf verifie (11/10/2026, Tomyn :
# "1-2-3-4") - garde une trace ecrite avant un gros lot plutot qu'une popup qu'on referme et qu'on
# oublie. Jamais bloquant si l'ecriture echoue (meme principe que partout ailleurs dans ce fichier
# pour les ecritures sur disque qui ne sont pas le resultat principal demande) - retourne le chemin
# ecrit, ou $null si ca a echoue.
function Exporter-RapportCouverture([string]$chemin3mf, [string[]]$lignes) {
    try {
        $horodatage = Get-Date -Format "yyyyMMdd_HHmmss"
        $cheminRapport = Join-Path ([System.IO.Path]::GetDirectoryName((Resolve-Path $chemin3mf))) ("$([System.IO.Path]::GetFileNameWithoutExtension($chemin3mf))_couverture_$horodatage.txt")
        $entete = @(
            "Rapport de couverture - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "Fichier verifie : $chemin3mf"
            ""
        )
        ($entete + $lignes) | Set-Content -Path $cheminRapport -Encoding UTF8 -ErrorAction Stop
        return $cheminRapport
    } catch {
        Ecrire-Journal "(Impossible d'exporter le rapport de couverture sur le disque : $_)"
        return $null
    }
}

# Extrait d'un .3mf (sans rien modifier) la liste des triangles avec leurs 3 sommets et leur couleur
# deja resolue (hex) - utilisee aussi bien pour l'apercu "avant" (fichier choisi par Tomyn) que
# "apres" (fichier genere par le melange), chacun ayant deja ses propres couleurs dans son
# project_settings.config.
function Lire-TrianglesPourApercu([string]$chemin3mf) {
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("apercu3mf_" + [guid]::NewGuid().ToString("N"))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($chemin3mf, $dossierTemp)
    try {
        $cheminConfig = Join-Path $dossierTemp "Metadata\project_settings.config"
        $config = Get-Content $cheminConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        $couleurs = @($config.filament_colour)

        $triangles = New-Object System.Collections.Generic.List[object]
        $fichiersModele = @(Get-ChildItem -Path (Join-Path $dossierTemp "3D") -Recurse -Filter "*.model" -ErrorAction SilentlyContinue)
        foreach ($fichierModele in $fichiersModele) {
            $texteModele = [System.IO.File]::ReadAllText($fichierModele.FullName)

            $sommets = New-Object System.Collections.Generic.List[double[]]
            foreach ($m in [System.Text.RegularExpressions.Regex]::Matches($texteModele, '<vertex x="([^"]+)" y="([^"]+)" z="([^"]+)"')) {
                [void]$sommets.Add(@([double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture), [double]::Parse($m.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture), [double]::Parse($m.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)))
            }
            if ($sommets.Count -eq 0) { continue }

            $cacheEtats = @{}
            foreach ($m in [System.Text.RegularExpressions.Regex]::Matches($texteModele, '<triangle v1="(\d+)" v2="(\d+)" v3="(\d+)"(?:[^>]*paint_color="([0-9A-Fa-f]+)")?')) {
                $i1 = [int]$m.Groups[1].Value; $i2 = [int]$m.Groups[2].Value; $i3 = [int]$m.Groups[3].Value
                $codeCouleur = $m.Groups[4].Value
                $couleurHex = "#CCCCCC"
                if ($codeCouleur) {
                    if (-not $cacheEtats.ContainsKey($codeCouleur)) {
                        $cacheEtats[$codeCouleur] = Decoder-EtatPaintColor $codeCouleur
                    }
                    $etat = $cacheEtats[$codeCouleur]
                    if ($etat -and $etat -ge 1 -and $etat -le $couleurs.Count) {
                        $couleurHex = $couleurs[$etat - 1]
                    }
                }
                if ($i1 -lt $sommets.Count -and $i2 -lt $sommets.Count -and $i3 -lt $sommets.Count) {
                    [void]$triangles.Add([PSCustomObject]@{ P1 = $sommets[$i1]; P2 = $sommets[$i2]; P3 = $sommets[$i3]; Couleur = $couleurHex })
                }
            }
        }
        return $triangles
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Choisit le meilleur angle de VUE (rotation autour de l'axe vertical ET inclinaison/tilt) pour la
# projection isometrique de Nouvelle-ImageApercu. Historique : une premiere version (10/10/2026,
# Tomyn : "on voit son cul") ne faisait tourner QUE l'axe vertical (8 angles a plat) en gardant un
# tilt fixe a -30 degres - Tomyn a confirme que ca restait insuffisant ("ANGLE MAUVAIS", meme avec
# la rotation choisie a 90 degres). Le vrai probleme : si le modele est, par ex., couche sur le
# cote ou debout mais "la face interessante" n'est pas a hauteur d'oeil avec un tilt de -30 fixe,
# aucune rotation horizontale seule ne peut compenser - il fallait aussi faire varier l'inclinaison.
# Desormais on teste une grille de 8 rotations horizontales x 4 inclinaisons (32 combinaisons) et on
# garde celle qui donne la meilleure surface bien eclairee/face a la "camera" (meme calcul d'ombrage
# que le rendu final), sur un ECHANTILLON du maillage pour rester rapide. Le budget total
# d'evaluations (nombre de triangles echantillonnes x nombre de combinaisons testees) est garde a
# peu pres constant quel que soit le nombre de combinaisons, pour que cette etape ne devienne pas
# plus lente juste parce qu'on teste plus d'angles.
function Choisir-MeilleurAngleVue($triangles) {
    $n = $triangles.Count
    if ($n -eq 0) { return [PSCustomObject]@{ AngleY = 45.0; AngleX = -30.0 } }

    $anglesY = @(0, 45, 90, 135, 180, 225, 270, 315)
    # Inclinaisons testees : de "vue plongeante" classique (-45) a "vue a hauteur d'oeil" (0), en
    # plus de l'ancien reglage fixe (-30) - couvre le cas ou la face interessante du modele n'est
    # visible qu'en regardant presque de face plutot que d'en haut.
    $anglesX = @(-45, -30, -15, 0)

    $nombreCombinaisons = $anglesY.Count * $anglesX.Count
    $budgetTotal = 64000
    $tailleEchantillon = [Math]::Max(200, [Math]::Floor($budgetTotal / $nombreCombinaisons))
    $pas = [Math]::Max(1, [Math]::Floor($n / $tailleEchantillon))
    $echantillon = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $n; $i += $pas) { [void]$echantillon.Add($triangles[$i]) }

    $lx = 0.3; $ly = 0.5; $lz = 0.8
    $normeLumiere = [math]::Sqrt($lx * $lx + $ly * $ly + $lz * $lz)
    $lx /= $normeLumiere; $ly /= $normeLumiere; $lz /= $normeLumiere

    $meilleurAngleY = 45.0
    $meilleurAngleX = -30.0
    $meilleurScore = [double]::MinValue
    foreach ($angleXDeg in $anglesX) {
        $angleX = $angleXDeg * [math]::PI / 180
        $cosB = [math]::Cos($angleX); $sinB = [math]::Sin($angleX)
        foreach ($angleYDeg in $anglesY) {
            $angleY = $angleYDeg * [math]::PI / 180
            $cosA = [math]::Cos($angleY); $sinA = [math]::Sin($angleY)
            $score = 0.0
            foreach ($tri in $echantillon) {
                # Garde-fou (10/10/2026, Tomyn : "Indexation impossible dans un tableau Null" sur son
                # fichier reel - jamais reproduit ici, mais un triangle sans P1/P2/P3 valides ne doit
                # plus planter tout l'apercu, juste etre ignore pour le score de cet angle.
                if (-not $tri -or -not $tri.P1 -or -not $tri.P2 -or -not $tri.P3) { continue }
                $pr = New-Object 'double[][]' 3
                for ($k = 0; $k -lt 3; $k++) {
                    $p = if ($k -eq 0) { $tri.P1 } elseif ($k -eq 1) { $tri.P2 } else { $tri.P3 }
                    $x1 = $p[0] * $cosA + $p[2] * $sinA
                    $z1 = -$p[0] * $sinA + $p[2] * $cosA
                    $y2 = $p[1] * $cosB - $z1 * $sinB
                    $z2 = $p[1] * $sinB + $z1 * $cosB
                    $pr[$k] = @($x1, $y2, $z2)
                }
                $ux = $pr[1][0] - $pr[0][0]; $uy = $pr[1][1] - $pr[0][1]; $uz = $pr[1][2] - $pr[0][2]
                $vx = $pr[2][0] - $pr[0][0]; $vy = $pr[2][1] - $pr[0][1]; $vz = $pr[2][2] - $pr[0][2]
                $nx = $uy * $vz - $uz * $vy; $ny = $uz * $vx - $ux * $vz; $nz = $ux * $vy - $uy * $vx
                $nlen = [math]::Sqrt($nx * $nx + $ny * $ny + $nz * $nz)
                if ($nlen -eq 0) { continue }
                $dot = ($nx / $nlen) * $lx + ($ny / $nlen) * $ly + ($nz / $nlen) * $lz
                if ($dot -gt 0) { $score += $dot * (0.5 * $nlen) }
            }
            if ($score -gt $meilleurScore) { $meilleurScore = $score; $meilleurAngleY = $angleYDeg; $meilleurAngleX = $angleXDeg }
        }
    }
    return [PSCustomObject]@{ AngleY = $meilleurAngleY; AngleX = $meilleurAngleX }
}

# Rendu statique du maillage colorise (projection isometrique maison + tri peintre + ombrage simple
# par la normale - pas un vrai moteur 3D, juste de quoi se faire une idee visuelle rapide des
# couleurs, demande par Tomyn pour voir d'un coup d'oeil ce qui a ete detecte et ce que le melange a
# produit, sans avoir a ouvrir Bambu Studio juste pour verifier). $angleYDegres (rotation) et
# $angleXDegres (inclinaison) viennent de Choisir-MeilleurAngleVue ci-dessus (45/-30 par defaut,
# l'ancien reglage fixe, si jamais omis).
function Nouvelle-ImageApercu($triangles, [int]$largeur, [int]$hauteur, [double]$angleYDegres = 45, [double]$angleXDegres = -30) {
    if (-not $triangles -or $triangles.Count -eq 0) { return $null }

    $angleY = $angleYDegres * [math]::PI / 180
    $angleX = $angleXDegres * [math]::PI / 180
    $cosA = [math]::Cos($angleY); $sinA = [math]::Sin($angleY)
    $cosB = [math]::Cos($angleX); $sinB = [math]::Sin($angleX)

    $n = $triangles.Count

    # Correctif du 10/10/2026 ("l'appli ne repond pas" signale par Tomyn sur son gros fichier) :
    # ici on travaille avec des tableaux "plats" (double[]) plutot que des PSCustomObject passes
    # dans Add-Member puis Sort-Object - ces deux-la ont un cout par element tres eleve en
    # PowerShell (meme constat que pour le bug de remapage des couleurs, plus haut dans ce
    # fichier : le goulot n'est jamais .NET, toujours le cout par iteration de PowerShell lui-meme)
    # et faisaient grimper le calcul a plusieurs minutes sur ~200000 triangles.
    $p1x = New-Object double[] $n; $p1y = New-Object double[] $n; $p1z = New-Object double[] $n
    $p2x = New-Object double[] $n; $p2y = New-Object double[] $n; $p2z = New-Object double[] $n
    $p3x = New-Object double[] $n; $p3y = New-Object double[] $n; $p3z = New-Object double[] $n
    $couleurs = New-Object string[] $n

    $minX = [double]::MaxValue; $maxX = [double]::MinValue
    $minY = [double]::MaxValue; $maxY = [double]::MinValue

    $idx = 0
    foreach ($tri in $triangles) {
        # Garde-fou (10/10/2026, Tomyn : "Indexation impossible dans un tableau Null" sur son fichier
        # reel - jamais reproduit ici, mais un triangle sans P1/P2/P3 valides ne doit plus planter
        # tout l'apercu, juste etre ignore (il restera a la couleur/position par defaut, filtree
        # ensuite par le seuil d'aire a l'ecran puisqu'il reste a l'origine, aire quasi nulle).
        if (-not $tri -or -not $tri.P1 -or -not $tri.P2 -or -not $tri.P3) { continue }
        for ($k = 0; $k -lt 3; $k++) {
            $p = if ($k -eq 0) { $tri.P1 } elseif ($k -eq 1) { $tri.P2 } else { $tri.P3 }
            $x1 = $p[0] * $cosA + $p[2] * $sinA
            $z1 = -$p[0] * $sinA + $p[2] * $cosA
            $y2 = $p[1] * $cosB - $z1 * $sinB
            $z2 = $p[1] * $sinB + $z1 * $cosB
            if ($k -eq 0) { $p1x[$idx] = $x1; $p1y[$idx] = $y2; $p1z[$idx] = $z2 }
            elseif ($k -eq 1) { $p2x[$idx] = $x1; $p2y[$idx] = $y2; $p2z[$idx] = $z2 }
            else { $p3x[$idx] = $x1; $p3y[$idx] = $y2; $p3z[$idx] = $z2 }
            if ($x1 -lt $minX) { $minX = $x1 }
            if ($x1 -gt $maxX) { $maxX = $x1 }
            if ($y2 -lt $minY) { $minY = $y2 }
            if ($y2 -gt $maxY) { $maxY = $y2 }
        }
        $couleurs[$idx] = $tri.Couleur
        $idx++
    }

    $marge = 15
    $largeurScene = $maxX - $minX; if ($largeurScene -le 0) { $largeurScene = 1 }
    $hauteurScene = $maxY - $minY; if ($hauteurScene -le 0) { $hauteurScene = 1 }
    $echelle = [math]::Min(($largeur - 2 * $marge) / $largeurScene, ($hauteur - 2 * $marge) / $hauteurScene)

    $lx = 0.3; $ly = 0.5; $lz = 0.8
    $normeLumiere = [math]::Sqrt($lx * $lx + $ly * $ly + $lz * $lz)
    $lx /= $normeLumiere; $ly /= $normeLumiere; $lz /= $normeLumiere

    $zMoyen = New-Object double[] $n
    $ombre = New-Object double[] $n
    # Correctif du 10/10/2026 (Tomyn : apercu "plus de 1 min" sur un gros fichier, 500 060
    # triangles - confirme par le chronometrage ajoute juste avant : 9,6 s de lecture, 48,0 s de
    # DESSIN) : sur une image d'apercu de 300x260 pixels, l'immense majorite de triangles d'un
    # maillage aussi dense occupent largement moins d'un pixel a l'ecran - les dessiner un par un
    # (chaque FillPolygon a un cout fixe en GDI+, meme pour un resultat invisible) est le vrai
    # goulot, pas le calcul. On calcule ici l'aire a l'ECRAN (en pixels, apres mise a l'echelle)
    # de chaque triangle, et seuls ceux qui couvrent au moins un peu de surface visible seront
    # dessines plus bas - contrairement a la decimation essayee (et rejetee) avant l'envoi de la
    # toute premiere version (un essai sur triangle sur deux, au hasard, qui laissait des trous
    # visibles), celle-ci ne retire QUE ce qui serait de toute facon invisible a cette taille
    # d'image : une zone pleine faite de nombreux petits triangles garde toujours au moins les
    # quelques-uns dont le contour traverse un pixel, donc pas de trou attendu.
    $aireEcran = New-Object double[] $n
    $indices = New-Object int[] $n

    for ($i = 0; $i -lt $n; $i++) {
        $indices[$i] = $i
        $zMoyen[$i] = ($p1z[$i] + $p2z[$i] + $p3z[$i]) / 3

        $ux = $p2x[$i] - $p1x[$i]; $uy = $p2y[$i] - $p1y[$i]; $uz = $p2z[$i] - $p1z[$i]
        $vx = $p3x[$i] - $p1x[$i]; $vy = $p3y[$i] - $p1y[$i]; $vz = $p3z[$i] - $p1z[$i]
        $nx = $uy * $vz - $uz * $vy
        $ny = $uz * $vx - $ux * $vz
        $nz = $ux * $vy - $uy * $vx
        $nlen = [math]::Sqrt($nx * $nx + $ny * $ny + $nz * $nz)
        if ($nlen -eq 0) { $nlen = 1 }
        $o = 0.5 + 0.5 * (($nx / $nlen) * $lx + ($ny / $nlen) * $ly + ($nz / $nlen) * $lz)
        if ($o -lt 0.35) { $o = 0.35 }
        if ($o -gt 1.0) { $o = 1.0 }
        $ombre[$i] = $o

        # Aire du triangle PROJETE A L'ECRAN (en ignorant Z, puisque le dessin final ne garde que
        # X/Y) - c'est exactement la formule du lacet en 2D, et $nz (deja calcule juste au-dessus
        # pour l'ombrage) en est directement la composante : nz = ux*vy - uy*vx, pas la peine de
        # la recalculer separement. Attention a ne pas utiliser $nlen ici (norme du produit
        # vectoriel en 3D) - une aire 3D n'est pas la meme chose que l'aire projetee a l'ecran,
        # elle vaudrait trop pour un triangle presque "de profil" par rapport a la camera.
        $aireEcran[$i] = 0.5 * [math]::Abs($nz) * $echelle * $echelle
    }

    # Tri peintre (arriere -> avant) avec [System.Array]::Sort au lieu de Sort-Object : meme
    # resultat (tri par Z croissant, $indices devient la permutation), mais sans le cout de
    # Sort-Object qui doit relire une propriete par comparaison sur chaque objet.
    [System.Array]::Sort($zMoyen, $indices)

    $bmp = New-Object System.Drawing.Bitmap $largeur, $hauteur
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    # Correctif du 10/10/2026 (Tomyn : "ultra long" a charger) : AntiAlias est connu pour couter
    # tres cher en GDI+ par polygone depose - sur des dizaines/centaines de milliers de triangles
    # (jamais chronometrable ici, System.Drawing n'existe pas sous Linux), ca peut facilement
    # devenir le vrai goulot, bien plus que le calcul en lui-meme (deja optimise juste avant). Sans
    # interet visuel sur une image d'apercu aussi petite (300x260) avec autant de triangles minuscules
    # empiles les uns sur les autres - HighSpeed desactive l'anticrenelage et les autres options
    # couteuses du meme genre.
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighSpeed
    $g.Clear([System.Drawing.Color]::FromArgb(245, 245, 245))

    # En dessous de ce seuil (en pixels carres), un triangle est de toute facon invisible sur une
    # image de cette taille - pas la peine de payer le cout GDI+ pour le dessiner. 0.15 a ete regle
    # (10/10/2026) pour la taille de REFERENCE 300x260 (la version a 0.02, plus prudente, testee
    # pour l'hypothese "detail perdu", s'est averee a la fois plus lente ET pas plus claire pour
    # Tomyn). Correctif du meme jour (Tomyn : "nuage de points" a demi-resolution, 150x130, pour la
    # rotation interactive) : un seuil FIXE en pixels devient disproportionnellement severe sur une
    # image plus petite (moins de 2% des triangles survivaient a 150x130, contre 34% a 300x260, bien
    # plus que la division par ~4 attendue) - le seuil est maintenant mis a l'echelle avec la surface
    # reelle de l'image (largeur x hauteur) par rapport a cette reference, pour garder une densite de
    # triangles affiches comparable quelle que soit la taille demandee.
    $seuilAirePixels = 0.15 * ($largeur * $hauteur) / (300.0 * 260.0)
    $compteurDessines = 0

    # Cache de la conversion couleur de base (10/10/2026, Tomyn : encore "tres long") : un maillage
    # n'a en pratique que quelques couleurs de base DISTINCTES (3 sur le dernier fichier de test) -
    # repasser par [ColorTranslator]::FromHtml (parsing de chaine + try/catch) a CHAQUE triangle,
    # des centaines de milliers de fois, pour re-obtenir le meme resultat a chaque fois, est le
    # meme genre de gaspillage deja corrige ailleurs dans ce fichier (meme principe que le cache de
    # decalage des couleurs peint sur le maillage, voir Traiter-Fichier3MF plus bas).
    $cacheCouleurBase = @{}

    # Correctif du 10/10/2026 (meme contexte que l'aire ci-dessus) : un FillPolygon individuel par
    # triangle a un cout GDI+ fixe par APPEL (pas juste par pixel rempli) - avec des centaines de
    # milliers de petits triangles, c'est ce cout d'appel repete qui domine tout, pas le
    # remplissage en lui-meme (negligeable sur des formes aussi petites). On regroupe donc tous les
    # triangles de la MEME teinte finale dans un seul GraphicsPath, dessine en un seul FillPath :
    # chaque triangle est toujours dessine (aucune perte de geometrie), seul le nombre d'APPELS a
    # FillXxx chute, de "un par triangle" a "un par teinte distincte".
    #
    # L'ombrage continu d'origine produisait quasiment une teinte DIFFERENTE par triangle (le cache
    # de brosses precedent ne servait donc presque jamais) - on le quantifie ici a 16 niveaux,
    # largement suffisant pour l'oeil sur une image de 300x260, pour que des triangles voisins de
    # la meme couleur de base se retrouvent effectivement dans le meme groupe.
    #
    # Entre deux triangles de la MEME teinte finale, l'ordre de dessin ne change de toute facon
    # jamais le resultat (memes pixels, meme couleur) - seul l'ordre "peintre" EXACT entre deux
    # teintes DIFFERENTES devient approximatif (les groupes sont dessines du plus loin au plus
    # proche par leur profondeur MOYENNE, plutot que triangle par triangle comme avant) :
    # suffisant pour un apercu rapide, pas un rendu 3D exact (voir le README).
    $NIVEAUX_OMBRE = 16
    $groupes = @{}
    foreach ($i in $indices) {
        if ($aireEcran[$i] -lt $seuilAirePixels) { continue }
        $compteurDessines++
        $hexCouleur = $couleurs[$i]
        if (-not $cacheCouleurBase.ContainsKey($hexCouleur)) {
            try {
                $cacheCouleurBase[$hexCouleur] = [System.Drawing.ColorTranslator]::FromHtml($hexCouleur)
            } catch {
                $cacheCouleurBase[$hexCouleur] = [System.Drawing.Color]::Gray
            }
        }
        $coul = $cacheCouleurBase[$hexCouleur]
        $niveau = [math]::Round((($ombre[$i] - 0.35) / 0.65) * ($NIVEAUX_OMBRE - 1))
        $oQuantifie = 0.35 + ($niveau / [double]($NIVEAUX_OMBRE - 1)) * 0.65
        $r = [int]($coul.R * $oQuantifie); $vv = [int]($coul.G * $oQuantifie); $b = [int]($coul.B * $oQuantifie)
        $cle = "$r,$vv,$b"
        if (-not $groupes.ContainsKey($cle)) {
            $groupes[$cle] = [PSCustomObject]@{
                Chemin  = New-Object System.Drawing.Drawing2D.GraphicsPath
                Couleur = [System.Drawing.Color]::FromArgb($r, $vv, $b)
                SommeZ  = 0.0
                Compte  = 0
            }
        }
        $grp = $groupes[$cle]
        $pts = @(
            (New-Object System.Drawing.PointF(($marge + ($p1x[$i] - $minX) * $echelle), ($hauteur - ($marge + ($p1y[$i] - $minY) * $echelle))))
            (New-Object System.Drawing.PointF(($marge + ($p2x[$i] - $minX) * $echelle), ($hauteur - ($marge + ($p2y[$i] - $minY) * $echelle))))
            (New-Object System.Drawing.PointF(($marge + ($p3x[$i] - $minX) * $echelle), ($hauteur - ($marge + ($p3y[$i] - $minY) * $echelle))))
        )
        $grp.Chemin.AddPolygon($pts)
        $grp.SommeZ += $zMoyen[$i]
        $grp.Compte++
    }

    foreach ($grp in ($groupes.Values | Sort-Object { $_.SommeZ / $_.Compte })) {
        $brush = New-Object System.Drawing.SolidBrush $grp.Couleur
        $g.FillPath($brush, $grp.Chemin)
        $brush.Dispose()
        $grp.Chemin.Dispose()
    }
    $g.Dispose()
    return [PSCustomObject]@{ Bitmap = $bmp; NombreDessines = $compteurDessines; NombreTotal = $n; NombreGroupes = $groupes.Count }
}

# ============================== TRAITEMENT DU FICHIER .3MF ==============================
# Meme logique que la version console (voir Melange-Couleurs-3MF.ps1 pour les commentaires
# detailles sur le format retrouve dans l'exemple de Tomyn) - ici $EcrireLigne est un scriptblock
# fourni par l'appelant pour afficher la progression dans le journal de la fenetre au lieu de
# Write-Host.
function Traiter-Fichier3MF([string]$cheminEntree, [string]$cheminSortie, $trio, [int]$pasPourcent, [scriptblock]$EcrireLigne, [int]$nombreMelangesVoulu = 0) {
    $primairesRGB = @($trio | ForEach-Object { Obtenir-RGBDepuisHex $_.Hex })

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("melange3mf_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dossierTemp | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($cheminEntree, $dossierTemp)

        $cheminConfig = Join-Path $dossierTemp "Metadata\project_settings.config"
        $cheminParamsModele = Join-Path $dossierTemp "Metadata\model_settings.config"

        if (-not (Test-Path $cheminConfig)) {
            throw "Ce fichier .3mf ne contient pas Metadata\project_settings.config - ce n'est probablement pas un projet Bambu Studio. Ouvre-le une premiere fois dans Bambu Studio, enregistre-le, et reessaie avec ce fichier-la."
        }

        & $EcrireLigne "Lecture de la configuration..."
        $jsonTexte = [System.IO.File]::ReadAllText($cheminConfig)
        $config = $jsonTexte | ConvertFrom-Json

        if (-not $config.filament_colour) {
            throw "Pas de liste 'filament_colour' trouvee dans ce fichier - format inattendu."
        }
        $couleursOrigine = @($config.filament_colour)
        $nombreCouleursOrigine = $couleursOrigine.Count
        & $EcrireLigne "$nombreCouleursOrigine couleur(s) detectee(s)."

        # 13/10/2026, Tomyn : "repasser le fichier deja melange une deuxieme fois dans l'outil, ca
        # va mieux" - signe d'un vrai manque de detection, pas une impression. Certains fichiers
        # (export Meshy/Bambu Studio) contiennent des zones peintes (paint_color sur le maillage) ou
        # un extrudeur par defaut d'objet (key="extruder" dans model_settings.config) qui pointent
        # vers un numero de couleur SUPERIEUR au nombre d'entrees de 'filament_colour' lu ci-dessus.
        # Le remappage plus bas (voir $scriptDecalerEtatPaintColor) a une securite qui laisse alors
        # ces zones totalement INTACTES ("etat hors de la plage connue") - elles ne sont donc jamais
        # melangees, silencieusement, sans qu'aucun message ne le signale. $etatsOrphelinsTrouves
        # (declaree juste avant $scriptDecalerEtatPaintColor plus bas) est remplie PENDANT le
        # remappage reel - pas de scan separe (correctif du 13/10/2026 : un premier essai faisait un
        # passage dedie en PLUS du remappage, donc relisait et re-decodait TOUT le maillage une
        # deuxieme fois sans rien afficher entre les deux - sur un gros fichier, ca pouvait
        # ressembler a un blocage de plusieurs minutes). Le message d'avertissement est affiche plus
        # bas, une fois le remappage termine.

        # Nombre de melanges a produire (10/10/2026, demande par Tomyn ; plafond recalcule le
        # 11/10/2026 au passage de l'outil en mode trio) : jusqu'a 32 emplacements au total dans
        # l'AMS, 3 fixes pour les primaires -> maximum 29 melanges. Si on en demande moins que de
        # couleurs detectees, les couleurs les plus proches visuellement sont regroupees (voir
        # Regrouper-CouleursParProximite) et traitees comme un seul melange.
        $nombreMelanges = $nombreCouleursOrigine
        if ($nombreMelangesVoulu -gt 0 -and $nombreMelangesVoulu -lt $nombreCouleursOrigine) {
            $nombreMelanges = [Math]::Min($nombreMelangesVoulu, 29)
        }
        $groupeDe = Regrouper-CouleursParProximite $couleursOrigine $nombreMelanges

        if ($nombreMelanges -lt $nombreCouleursOrigine) {
            & $EcrireLigne "Regroupement en $nombreMelanges melange(s) (demande par toi, moins que les $nombreCouleursOrigine couleurs detectees) :"
            for ($g = 0; $g -lt $nombreMelanges; $g++) {
                $membresLog = @(0..($nombreCouleursOrigine - 1) | Where-Object { $groupeDe[$_] -eq $g })
                $couleursLog = ($membresLog | ForEach-Object { $couleursOrigine[$_] }) -join ", "
                & $EcrireLigne ("  - Melange {0} <- couleur(s) {1}" -f ($g + 1), $couleursLog)
            }
        }
        & $EcrireLigne ""

        $dosages = @()
        for ($g = 0; $g -lt $nombreMelanges; $g++) {
            $membres = @(0..($nombreCouleursOrigine - 1) | Where-Object { $groupeDe[$_] -eq $g })
            $rgbMembres = @($membres | ForEach-Object { Obtenir-RGBDepuisHex $couleursOrigine[$_] })
            $ratiosEgaux = @($membres | ForEach-Object { 100.0 / $membres.Count })
            # Un seul membre : pas la peine de repasser par Melanger-EnLumiereLineaire, sa propre
            # couleur suffit comme cible.
            $cibleRGB = if ($membres.Count -eq 1) { $rgbMembres[0] } else { Melanger-EnLumiereLineaire $rgbMembres $ratiosEgaux }
            $meilleur = Trouver-MeilleurDosage $cibleRGB $primairesRGB $pasPourcent
            $dosages += [PSCustomObject]@{
                ResultatRGB = $meilleur.Resultat
                ResultatHex = Obtenir-HexDepuisRGB $meilleur.Resultat.R $meilleur.Resultat.G $meilleur.Resultat.B
                Dosage      = $meilleur.Dosage
            }
            $resume = ($trio | ForEach-Object -Begin { $k = 0 } -Process {
                $pct = $meilleur.Dosage[$k]; $k++
                if ($pct -gt 0) { "$($_.Nom) $pct%" }
            }) -join " + "
            $hexCible = Obtenir-HexDepuisRGB $cibleRGB.R $cibleRGB.G $cibleRGB.B
            # Pastille (11/10/2026, Tomyn : "1-2-3-4") avec la couleur REELLEMENT obtenue
            # ($dosages[$g].ResultatHex, deja calcule juste au-dessus) plutot que la couleur CIBLE
            # ($hexCible, deja affichee en texte) - c'est precisement l'ecart entre les deux que
            # "ecart Lab" mesure, donc la pastille montre ce que le dosage donne vraiment.
            & $EcrireLigne ("Melange {0} ({1}) -> {2}  (ecart Lab {3:N1})" -f ($g + 1), $hexCible, $resume, $meilleur.Distance) $dosages[$g].ResultatHex
        }
        & $EcrireLigne ""

        # Fusion des melanges strictement identiques (11/10/2026, Tomyn : constate sur un vrai
        # fichier avec un trio au faible volume de couverture - voir Obtenir-AireCouvertureTrio
        # plus haut) - avec un trio "etroit", le MEILLEUR dosage trouve pour plusieurs groupes aux
        # couleurs d'ORIGINE pourtant differentes peut retomber exactement sur le meme point du volume
        # atteignable (meme dosage au pas de 5% pres -> meme code hex resultant), gaspillant des
        # emplacements d'AMS pour des couleurs rigoureusement identiques. Fusionne ici en un seul
        # melange final AVANT de construire le fichier de sortie, peu importe le trio utilise -
        # utile aussi avec un bon trio, juste plus rare que ca arrive dans ce cas.
        $indexFinalParHex = @{}
        $dosagesFinaux = @()
        $mappingAncienVersFinal = New-Object int[] $nombreMelanges
        for ($g = 0; $g -lt $nombreMelanges; $g++) {
            $hex = $dosages[$g].ResultatHex
            if (-not $indexFinalParHex.ContainsKey($hex)) {
                $indexFinalParHex[$hex] = $dosagesFinaux.Count
                $dosagesFinaux += $dosages[$g]
            }
            $mappingAncienVersFinal[$g] = $indexFinalParHex[$hex]
        }
        if ($dosagesFinaux.Count -lt $nombreMelanges) {
            & $EcrireLigne "Fusion de $($nombreMelanges - $dosagesFinaux.Count) melange(s) strictement identique(s) (meme couleur resultante) : $nombreMelanges -> $($dosagesFinaux.Count) melange(s) final/finaux."
            & $EcrireLigne ""
        }
        for ($i = 0; $i -lt $nombreCouleursOrigine; $i++) {
            $groupeDe[$i] = $mappingAncienVersFinal[$groupeDe[$i]]
        }
        $nombreMelanges = $dosagesFinaux.Count
        $dosages = $dosagesFinaux

        # Recalcule APRES la fusion ci-dessus (un representant par groupe FINAL, pas par groupe
        # d'avant-fusion - la taille et le contenu de $groupeDe ont change).
        $representantDuGroupe = New-Object int[] $nombreMelanges
        for ($g = 0; $g -lt $nombreMelanges; $g++) { $representantDuGroupe[$g] = -1 }
        for ($i = 0; $i -lt $nombreCouleursOrigine; $i++) {
            $g = $groupeDe[$i]
            if ($representantDuGroupe[$g] -eq -1) { $representantDuGroupe[$g] = $i }
        }

        $nouveauTotal = 3 + $nombreMelanges

        # Correctif du 10/10/2026 (vu sur un vrai fichier de Tomyn, deux essais de suite) : on
        # n'utilise plus DU TOUT "$config | ConvertTo-Json" pour reecrire le fichier. Deux correctifs
        # precedents (Add-Member, puis object[] au lieu de string[]) n'ont pas suffi - en comparant
        # la meme sortie generee ici avec PowerShell 7 (correcte) contre celle produite par Tomyn
        # avec Windows PowerShell 5.1 (toujours cassee), le vrai responsable est confirme etre
        # ConvertTo-Json lui-meme sur cette version : TOUT champ tableau reaffecte (pas seulement
        # ceux qu'on ajoute - meme ceux de la boucle generique juste en dessous, deja presents dans
        # le fichier d'origine) ressortait en JSON sous la forme {"value":[...],"Count":N} au lieu
        # d'un tableau tout simple - ce que Bambu Studio lit de travers, d'ou le plantage "Out of
        # Memory" a l'ouverture. On modifie donc desormais directement le TEXTE JSON d'origine
        # (remplacement cible par expression reguliere, un champ a la fois), sans jamais repasser
        # par ConvertTo-Json - tout le reste du fichier (les ~500 autres champs) reste absolument
        # identique a l'original, octet pour octet.
        # Echappement complet selon la norme JSON (10/10/2026, bug trouve sur un vrai fichier) : des
        # champs comme "filament_start_gcode" sont dupliques par la boucle generique ci-dessous et
        # contiennent du G-code multiligne - une fois lu par ConvertFrom-Json, le "\n" d'origine
        # redevient un VRAI retour a la ligne dans la chaine PowerShell. Un simple Replace('\','\\')
        # ne le reechappait pas, ce qui cassait le JSON (retour a la ligne litteral dans une chaine)
        # - Bambu Studio refusait alors de charger le fichier. On echappe ici tous les caracteres de
        # controle requis par la norme JSON, pas seulement l'antislash et le guillemet.
        function Echapper-JsonTexte([string]$texte) {
            $construction = New-Object System.Text.StringBuilder
            foreach ($caractere in $texte.ToCharArray()) {
                if ($caractere -eq '\') { [void]$construction.Append('\\') }
                elseif ($caractere -eq '"') { [void]$construction.Append('\"') }
                elseif ($caractere -eq "`n") { [void]$construction.Append('\n') }
                elseif ($caractere -eq "`r") { [void]$construction.Append('\r') }
                elseif ($caractere -eq "`t") { [void]$construction.Append('\t') }
                elseif ([int]$caractere -lt 0x20) { [void]$construction.Append("\u{0:x4}" -f [int]$caractere) }
                else { [void]$construction.Append($caractere) }
            }
            return $construction.ToString()
        }
        function ConvertTo-JsonArrayTexte($valeurs) {
            $elements = @($valeurs | ForEach-Object { '"' + (Echapper-JsonTexte([string]$_)) + '"' })
            return '[' + ($elements -join ',') + ']'
        }
        # Remplace la valeur du champ "$nomChamp": [...] dans le texte JSON brut, passe par [ref]
        # (une fonction imbriquee ne modifie pas une variable de la fonction englobante par simple
        # affectation en PowerShell - [ref] est la facon explicite et fiable de le faire). S'il
        # n'existe pas deja dans le fichier d'origine (ex. filament_colour_type, absent de certains
        # projets), on l'insere juste apres "filament_colour" (toujours present - verifie plus haut)
        # plutot que de planter. Le remplacement passe par un MatchEvaluator (et non une simple
        # chaine) pour eviter tout souci si jamais la valeur contenait un caractere "$" (syntaxe de
        # backreference en remplacement regex).
        #
        # Le motif pour reperer "[ ... ]" ne peut pas etre un simple "pas de crochet a l'interieur"
        # (10/10/2026, bug trouve sur le vrai fichier de Tomyn) : des champs comme
        # "filament_start_gcode" contiennent du G-code avec des crochets dans le TEXTE lui-meme
        # (ex. "bed_temperature[current_extruder]"), qui coupaient le motif en plein milieu et
        # laissaient une entree en double dans le fichier. Le motif reconnait maintenant
        # explicitement une suite de chaines JSON entre guillemets (en ignorant les crochets a
        # l'interieur d'une chaine) plutot que de s'arreter au premier crochet rencontre.
        $script:MOTIF_TABLEAU_JSON = '\s*:\s*\[\s*(?:"(?:[^"\\]|\\.)*"\s*,?\s*)*\]'
        function Definir-ChampJson([ref]$refTexteJson, [string]$nomChamp, $nouveauTableau) {
            $texteTableau = ConvertTo-JsonArrayTexte $nouveauTableau
            $motif = '"' + [regex]::Escape($nomChamp) + '"' + $script:MOTIF_TABLEAU_JSON
            if ([System.Text.RegularExpressions.Regex]::IsMatch($refTexteJson.Value, $motif)) {
                $evaluateurChamp = [System.Text.RegularExpressions.MatchEvaluator]{
                    param($m)
                    return '"' + $nomChamp + '": ' + $texteTableau
                }.GetNewClosure()
                $refTexteJson.Value = [System.Text.RegularExpressions.Regex]::Replace($refTexteJson.Value, $motif, $evaluateurChamp, 1)
            } else {
                $motifAncre = '"filament_colour"' + $script:MOTIF_TABLEAU_JSON
                $evaluateurAncre = [System.Text.RegularExpressions.MatchEvaluator]{
                    param($m)
                    return $m.Value + ",`n    " + '"' + $nomChamp + '": ' + $texteTableau
                }.GetNewClosure()
                $refTexteJson.Value = [System.Text.RegularExpressions.Regex]::Replace($refTexteJson.Value, $motifAncre, $evaluateurAncre, 1)
            }
        }

        $proprietes = $config.PSObject.Properties | Where-Object { $_.Value -is [array] -and $_.Value.Count -eq $nombreCouleursOrigine }
        & $EcrireLigne "Extension de $($proprietes.Count) reglage(s) 'par filament' a $nouveauTotal emplacements..."
        foreach ($prop in $proprietes) {
            $ancien = $prop.Value
            $nouveau = New-Object object[] $nouveauTotal
            for ($i = 0; $i -lt 3; $i++) { $nouveau[$i] = $ancien[0] }
            for ($i = 0; $i -lt $nombreCouleursOrigine; $i++) { $nouveau[3 + $groupeDe[$i]] = $ancien[$i] }
            Definir-ChampJson ([ref]$jsonTexte) $prop.Name $nouveau
        }

        # Champs "par filament" ou chaque filament occupe un bloc de PLUSIEURS valeurs consecutives,
        # pas une seule (ex. filament_retraction_length : "nil","0.4" repete deux fois par filament -
        # confirme en comparant avec le vrai fichier de Tomyn). La boucle ci-dessus ne les detectait
        # pas (leur longueur ne vaut jamais exactement $nombreCouleursOrigine) et les laissait donc
        # a leur ancienne taille, trop courte pour le nouveau nombre total de filaments - une autre
        # cause tres probable des plantages "Out of Memory"/silencieux (10/10/2026, trouve en
        # comparant systematiquement la taille de CHAQUE champ tableau du fichier d'origine a un
        # multiple exact du nombre de couleurs Meshy, plutot qu'en se fiant au seul message d'erreur
        # - aucun des fichiers de test envoyes par Tomyn n'en disait assez pour le trouver autrement).
        $proprietesParBloc = $config.PSObject.Properties | Where-Object {
            $_.Value -is [array] -and $_.Value.Count -gt $nombreCouleursOrigine -and
            $_.Value.Count % $nombreCouleursOrigine -eq 0 -and
            ($_.Value.Count / $nombreCouleursOrigine) -ne $nombreCouleursOrigine -and
            $_.Name -ne "flush_volumes_matrix"
        }
        if ($proprietesParBloc.Count -gt 0) {
            & $EcrireLigne "Extension de $($proprietesParBloc.Count) reglage(s) 'par filament' (plusieurs valeurs par filament) a $nouveauTotal emplacements..."
        }
        foreach ($prop in $proprietesParBloc) {
            $ancien = $prop.Value
            $taille = [int]($ancien.Count / $nombreCouleursOrigine)
            $nouveau = New-Object object[] ($nouveauTotal * $taille)
            for ($i = 0; $i -lt 3; $i++) {
                for ($b = 0; $b -lt $taille; $b++) { $nouveau[$i * $taille + $b] = $ancien[$b] }
            }
            for ($i = 0; $i -lt $nombreCouleursOrigine; $i++) {
                for ($b = 0; $b -lt $taille; $b++) { $nouveau[(3 + $groupeDe[$i]) * $taille + $b] = $ancien[$i * $taille + $b] }
            }
            Definir-ChampJson ([ref]$jsonTexte) $prop.Name $nouveau
        }

        # filament_self_index : contrairement aux champs ci-dessus, ce n'est pas une propriete du
        # filament (comme sa vitesse de retraction) mais son PROPRE numero (le filament a l'ancienne
        # position 3 y stocke "3,3" ; le 4e, "4,4"). Le dupliquer tel quel comme les autres champs
        # "par bloc" donnerait des numeros faux (les 3 nouvelles primaires auraient toutes "1,1" au
        # lieu de 1,2,3, et les couleurs d'origine garderaient leur ancien numero 1-6 au lieu de
        # 4-9) - corrige en le recalculant entierement a partir de la nouvelle position de chaque
        # filament plutot que de copier les anciennes valeurs.
        if ($config.PSObject.Properties.Match("filament_self_index").Count -gt 0) {
            $ancienSelfIndex = $config.filament_self_index
            if ($ancienSelfIndex -is [array] -and $ancienSelfIndex.Count -gt 0 -and ($ancienSelfIndex.Count % $nombreCouleursOrigine) -eq 0) {
                $tailleSelfIndex = [int]($ancienSelfIndex.Count / $nombreCouleursOrigine)
                $nouveauSelfIndex = New-Object object[] ($nouveauTotal * $tailleSelfIndex)
                for ($i = 0; $i -lt $nouveauTotal; $i++) {
                    for ($b = 0; $b -lt $tailleSelfIndex; $b++) { $nouveauSelfIndex[$i * $tailleSelfIndex + $b] = [string]($i + 1) }
                }
                Definir-ChampJson ([ref]$jsonTexte) "filament_self_index" $nouveauSelfIndex
            }
        }

        # flush_volumes_matrix : une vraie matrice NxN (volume de purge entre chaque PAIRE de
        # filaments), pas un simple tableau par filament - meme souci que ci-dessus mais en deux
        # dimensions : laissee a sa taille d'origine (N x N), alors que Bambu Studio l'indexe avec le
        # numero de filament jusqu'au nouveau total, largement hors limite du tableau d'origine. Les
        # cases touchant une des 3 nouvelles primaires recoivent la valeur la plus frequente hors
        # diagonale de la matrice d'origine (la valeur "par defaut" que Bambu Studio lui-meme utilise
        # entre deux filaments sans reglage particulier) ; les cases entre deux couleurs d'origine
        # recuperent leur valeur calibree exacte, inchangee.
        if ($config.PSObject.Properties.Match("flush_volumes_matrix").Count -gt 0 -and
            $config.flush_volumes_matrix.Count -eq ($nombreCouleursOrigine * $nombreCouleursOrigine)) {
            $ancienneMatrice = $config.flush_volumes_matrix
            $valeursHorsDiagonale = @()
            for ($i = 0; $i -lt $nombreCouleursOrigine; $i++) {
                for ($j = 0; $j -lt $nombreCouleursOrigine; $j++) {
                    if ($i -ne $j) { $valeursHorsDiagonale += $ancienneMatrice[$i * $nombreCouleursOrigine + $j] }
                }
            }
            $valeurParDefaut = "280"
            if ($valeursHorsDiagonale.Count -gt 0) {
                $groupePlusFrequent = $valeursHorsDiagonale | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
                if ($groupePlusFrequent) { $valeurParDefaut = $groupePlusFrequent.Name }
            }

            $nouvelleMatrice = New-Object object[] ($nouveauTotal * $nouveauTotal)
            for ($i = 0; $i -lt $nouveauTotal; $i++) {
                for ($j = 0; $j -lt $nouveauTotal; $j++) {
                    if ($i -eq $j) {
                        $nouvelleMatrice[$i * $nouveauTotal + $j] = "0"
                    } elseif ($i -ge 3 -and $j -ge 3) {
                        # Avec le regroupement de couleurs (10/10/2026), $i-4/$j-4 sont des numeros
                        # de GROUPE, pas de couleur d'origine - la matrice d'origine, elle, est
                        # toujours indexee par couleur d'origine. On recupere donc la valeur calibree
                        # d'un representant de chaque groupe (la premiere couleur d'origine qui lui a
                        # ete affectee) plutot que d'indexer directement avec le numero de groupe.
                        $iOrig = $representantDuGroupe[$i - 3]; $jOrig = $representantDuGroupe[$j - 3]
                        $nouvelleMatrice[$i * $nouveauTotal + $j] = $ancienneMatrice[$iOrig * $nombreCouleursOrigine + $jOrig]
                    } else {
                        $nouvelleMatrice[$i * $nouveauTotal + $j] = $valeurParDefaut
                    }
                }
            }
            & $EcrireLigne "Extension de flush_volumes_matrix ($nombreCouleursOrigine x $nombreCouleursOrigine -> $nouveauTotal x $nouveauTotal)..."
            Definir-ChampJson ([ref]$jsonTexte) "flush_volumes_matrix" $nouvelleMatrice
        }

        $nouvCouleur    = New-Object object[] $nouveauTotal
        $nouvColourType = New-Object object[] $nouveauTotal
        $nouvEstMelange = New-Object object[] $nouveauTotal
        $nouvComposants = New-Object object[] $nouveauTotal
        $nouvRatios     = New-Object object[] $nouveauTotal
        $nouvMapping    = New-Object object[] $nouveauTotal

        for ($i = 0; $i -lt 3; $i++) {
            $nouvCouleur[$i]    = $trio[$i].Hex
            $nouvColourType[$i] = "1"
            $nouvEstMelange[$i] = "0"
            $nouvComposants[$i] = ""
            $nouvRatios[$i]     = ""
            $nouvMapping[$i]    = "1"
        }
        for ($g = 0; $g -lt $nombreMelanges; $g++) {
            $d = $dosages[$g]
            $nouvCouleur[3 + $g]    = $d.ResultatHex
            $nouvColourType[3 + $g] = "1"
            $nouvMapping[3 + $g]    = "1"
            # [System.Globalization.CultureInfo]::InvariantCulture explicitement (10/10/2026, bug
            # trouve sur le vrai fichier de Tomyn) : "{0:0.0000}" -f (...) utilise par defaut le
            # format regional de Windows pour le separateur decimal - sur une machine configuree en
            # francais, "0.3000" ressortait "0,3000" (virgule au lieu du point), ce qui cassait
            # totalement filament_mixed_sublayer_ratios (3 ratios en virgule devenant 6 fragments
            # illisibles pour Bambu Studio) et faisait planter Bambu Studio au chargement, sans
            # message d'erreur. Le JSON exige un point, quelle que soit la langue de Windows.
            #
            # Composants a 0% exclus (10/10/2026, trouve en comparant avec un vrai melange fait par
            # Tomyn a la main dans Bambu Studio, present dans son propre fichier de test) : son
            # melange (2 primaires sur les 3 qu'il avait choisies, la 3e a 0%) est enregistre par
            # Bambu Studio avec SEULEMENT 2 entrees dans filament_mixed_components ("1,2") et 2
            # ratios ("0.2000,0.8000") - PAS "1,2,3" avec un 3eme ratio a "0.0000". L'ancienne
            # version de ce script ecrivait toujours les 3 primaires, y compris celles a 0% - un
            # format que Bambu Studio n'ecrit jamais lui-meme.
            $indicesUtilises = @()
            $ratiosUtilises = @()
            for ($p = 0; $p -lt $d.Dosage.Count; $p++) {
                if ($d.Dosage[$p] -gt 0) {
                    $indicesUtilises += ($p + 1)
                    $ratiosUtilises += ($d.Dosage[$p] / 100.0).ToString("0.0000", [System.Globalization.CultureInfo]::InvariantCulture)
                }
            }
            # Pas de "melange" a un seul ingredient (10/10/2026, trouve en comparant encore une fois
            # avec le fichier de Tomyn) : quand une couleur Meshy tombe pile sur une des 3 primaires
            # (dosage 100%/0/0), le script creait quand meme un filament "melange" compose d'un seul
            # composant - une donnee degenere que Bambu Studio ne produit jamais lui-meme via sa
            # propre interface (un "melange" a un seul ingredient n'est juste pas un melange). C'est
            # tres probablement une autre cause du "Out of Memory" : le code de Bambu Studio qui gere
            # les melanges de filaments n'a sans doute jamais ete teste avec un cas pareil. Dans ce
            # cas-la, on enregistre maintenant un filament normal (non melange), identique a la
            # primaire correspondante - exactement comme n'importe quel autre filament du fichier.
            if ($indicesUtilises.Count -le 1) {
                $nouvEstMelange[3 + $g] = "0"
                $nouvComposants[3 + $g] = ""
                $nouvRatios[3 + $g]     = ""
            } else {
                $nouvEstMelange[3 + $g] = "1"
                $nouvComposants[3 + $g] = $indicesUtilises -join ","
                $nouvRatios[3 + $g]     = $ratiosUtilises -join ","
            }
        }

        # Reecrase par-dessus les valeurs dupliquees posees par la boucle generique ci-dessus (ces
        # champs correspondent aussi a $nombreCouleursOrigine elements donc y passent aussi) avec les
        # vraies couleurs/ratios de melange calcules.
        Definir-ChampJson ([ref]$jsonTexte) "filament_colour"                $nouvCouleur
        Definir-ChampJson ([ref]$jsonTexte) "filament_colour_type"           $nouvColourType
        Definir-ChampJson ([ref]$jsonTexte) "filament_is_mixed"              $nouvEstMelange
        Definir-ChampJson ([ref]$jsonTexte) "filament_mixed_components"     $nouvComposants
        Definir-ChampJson ([ref]$jsonTexte) "filament_mixed_sublayer_ratios" $nouvRatios
        if ($config.PSObject.Properties.Match("filament_multi_colour").Count -gt 0) {
            Definir-ChampJson ([ref]$jsonTexte) "filament_multi_colour" $nouvCouleur
        }
        if ($config.PSObject.Properties.Match("filament_map").Count -gt 0) {
            Definir-ChampJson ([ref]$jsonTexte) "filament_map" $nouvMapping
        }

        & $EcrireLigne "Ecriture de la configuration modifiee..."
        [System.IO.File]::WriteAllText($cheminConfig, $jsonTexte)

        # Correctif du 10/10/2026 (fichier de test de Tomyn) : le maillage et les paint_color ne sont
        # PAS forcement dans 3D/3dmodel.model - Bambu Studio eclate souvent chaque objet dans son
        # propre fichier sous 3D/Objects/ (ex. object_1.model), 3dmodel.model ne faisant plus que les
        # reference via un <component>. L'ancienne version ne touchait QUE 3dmodel.model : sur ce
        # fichier de test, elle ne remappait donc RIEN (0 paint_color dedans, les 199000+ etaient
        # tous dans Objects/object_1.model) - les couleurs seraient restees fausses silencieusement.
        # On parcourt maintenant tous les .model sous 3D/ (3dmodel.model + tout objet separe).
        #
        # Correctif du 10/10/2026 (bien plus grave, trouve en comparant un fichier produit par ce
        # script a un fichier ou Tomyn a refait le MEME melange a la main dans Bambu Studio) :
        # l'attribut paint_color N'EST PAS un numero de filament ecrit en decimal. C'est un format
        # a part (celui de PrusaSlicer/Bambu Studio pour le "MMU painting") : une chaine de chiffres
        # hexadecimaux qui encode, en bits, un petit arbre - "ce triangle est-il subdivise, et si
        # oui en combien de sous-triangles, sinon quel est son numero de filament" - le tout range a
        # l'envers (le dernier caractere de la chaine est lu en premier). Ajouter 4 au nombre
        # decimal en tete de la chaine (ce que faisait l'ancienne version) tombait juste par hasard
        # pour certaines couleurs et cassait les autres - par exemple "8" (qui code en realite le
        # filament n°2) devenait "12", un code qui ne veut tout simplement rien dire dans ce format
        # (il indique "ce triangle est subdivise en 3" sans fournir les donnees des 3 sous-
        # triangles). Avec des milliers de triangles corrompus de cette facon d'un coup, c'est tres
        # probablement la vraie cause de tous les plantages silencieux precedents, malgre tous les
        # correctifs deja faits. Corrige en decodant vraiment ce petit arbre, en decalant seulement
        # les numeros de filament qu'il contient (jamais la structure de subdivision), puis en le
        # reencodant - verifie caractere pour caractere contre un fichier ou Tomyn a fait le meme
        # melange a la main dans Bambu Studio (deux trios differents, memes resultats), et sur
        # les 199 000+ triangles de son fichier de test (aucune anomalie, decalage de 0 redonne
        # exactement la chaine de depart partout).
        # Definie comme bloc de script (et non comme "function") pour pouvoir etre appelee depuis
        # l'interieur du MatchEvaluator ci-dessous : une fonction PowerShell normale definie ici
        # n'est pas visible depuis ce bloc-la une fois passee a Regex.Replace (meme piege de portee
        # que celui deja rencontre plus haut avec $script:jsonTexte - une fonction n'est pas une
        # simple variable, GetNewClosure() ne capture que les variables).
        # $tableauGroupe : lookup "numero de couleur d'origine (1-based) -> numero de groupe
        # (0-based)" (10/10/2026, ajoute avec le regroupement de couleurs) - remplace l'ancien
        # decalage fixe de 3, puisque deux couleurs d'origine peuvent desormais partager le meme
        # emplacement de melange. Avec $tableauGroupe = @(0,1,2,...) (une couleur = un groupe, le
        # cas par defaut), le resultat est identique a l'ancien "+3" pour chaque etat.
        $etatsOrphelinsTrouves = New-Object System.Collections.Generic.List[int]
        $scriptDecalerEtatPaintColor = {
            param([string]$texte, [int[]]$tableauGroupe, [System.Collections.Generic.List[int]]$refEtatsOrphelins)
            $nibblesEntree = New-Object System.Collections.Generic.List[int]
            for ($i = $texte.Length - 1; $i -ge 0; $i--) {
                $nibblesEntree.Add([System.Convert]::ToInt32([string]$texte[$i], 16))
            }
            $position = 0
            $nibblesSortie = New-Object System.Collections.Generic.List[int]
            $pile = New-Object System.Collections.Generic.List[int]
            while ($true) {
                $code = $nibblesEntree[$position]; $position++
                $propresNibbles = New-Object System.Collections.Generic.List[int]
                $propresNibbles.Add($code)
                $cotesDivises = $code -band 0x3
                $estDivise = $cotesDivises -ne 0
                $nombreEnfants = 0
                if ($estDivise) {
                    $nombreEnfants = $cotesDivises + 1
                } else {
                    if (($code -band 0xC) -eq 0xC) {
                        $n2 = $nibblesEntree[$position]; $position++
                        $propresNibbles.Add($n2)
                        if ($n2 -eq 0xF) {
                            $n3 = $nibblesEntree[$position]; $position++
                            $propresNibbles.Add($n3)
                            $etat = $n3 + 18
                        } else {
                            $etat = $n2 + 3
                        }
                    } else {
                        $etat = $code -shr 2
                    }
                    if ($etat -ne 0) {
                        if ($etat -ge 1 -and $etat -le $tableauGroupe.Count) {
                            # 4 = 3 primaires du trio (etats 1-3) + 1, puisque la numerotation des
                            # etats paint_color commence a 1 (11/10/2026, etait "5" avant le passage
                            # de l'outil en mode trio a 3 couleurs - voir plus haut).
                            $nouvelEtat = 4 + $tableauGroupe[$etat - 1]
                        } else {
                            # Securite : un etat hors de la plage connue (ne devrait pas arriver)
                            # reste tel quel plutot que de produire un code invalide. 13/10/2026 :
                            # note dans $refEtatsOrphelins (liste, mutee par reference - pas besoin
                            # de passage separe sur tout le maillage pour le detecter, voir plus haut)
                            # pour pouvoir avertir Tomyn une fois le remappage termine.
                            $nouvelEtat = $etat
                            [void]$refEtatsOrphelins.Add($etat)
                        }
                        $propresNibbles.Clear()
                        if ($nouvelEtat -lt 3) {
                            $propresNibbles.Add($nouvelEtat -shl 2)
                        } elseif ($nouvelEtat -le 17) {
                            $propresNibbles.Add(0xC); $propresNibbles.Add($nouvelEtat - 3)
                        } else {
                            $propresNibbles.Add(0xC); $propresNibbles.Add(0xF); $propresNibbles.Add($nouvelEtat - 18)
                        }
                    }
                }
                foreach ($n in $propresNibbles) { $nibblesSortie.Add($n) }

                if ($pile.Count -eq 0) {
                    if ($estDivise) { $pile.Add($nombreEnfants); continue } else { break }
                }
                if ($estDivise) {
                    $pile.Add($nombreEnfants)
                } else {
                    $pile[$pile.Count - 1] = $pile[$pile.Count - 1] - 1
                }
                while ($pile.Count -gt 0 -and $pile[$pile.Count - 1] -eq 0) {
                    $pile.RemoveAt($pile.Count - 1)
                    if ($pile.Count -gt 0) { $pile[$pile.Count - 1] = $pile[$pile.Count - 1] - 1 }
                }
                if ($pile.Count -eq 0) { break }
            }
            $construction = New-Object System.Text.StringBuilder
            for ($i = $nibblesSortie.Count - 1; $i -ge 0; $i--) {
                [void]$construction.Append($nibblesSortie[$i].ToString("X"))
            }
            return $construction.ToString()
        }

        $fichiersModele = @(Get-ChildItem -Path (Join-Path $dossierTemp "3D") -Recurse -Filter "*.model" -ErrorAction SilentlyContinue)
        if ($fichiersModele.Count -gt 0) {
            & $EcrireLigne "Remappage des couleurs sur le maillage ($($fichiersModele.Count) fichier(s), peut prendre un moment)..."
            # Cache : un maillage peint n'a en pratique qu'une poignee de codes paint_color
            # DIFFERENTS (3 ou 4 en general, meme sur 200 000 triangles - chaque triangle d'une
            # meme zone colorise partage le meme code). Decoder/reencoder a chaque triangle est
            # donc inutilement lent (environ 2 minutes sur le fichier de 199 000 triangles de
            # Tomyn, le temps que son retour confirme) : on ne calcule plus le resultat qu'une
            # fois par code DISTINCT rencontre, et on reutilise le resultat deja calcule pour
            # toutes les repetitions suivantes de ce meme code.
            $cacheDecalage = @{}
            # 13/10/2026, Tomyn : fichier de plus d'1 million de triangles, 10 minutes d'attente sur
            # cette seule etape SANS AUCUN message entre le debut et la fin - ca ressemble a un
            # blocage meme quand ca travaille vraiment (Regex.Replace ne donne aucun callback de
            # progression natif). Compteur de triangles traites ($etatCompteur, table mutee par
            # reference - meme principe que $etatsOrphelinsTrouves plus haut), avec un message tous
            # les 200 000 triangles pour prouver que ca avance, sans spammer le journal sur un petit
            # fichier (200 000 passages dans l'evaluateur = quelques dixiemes de seconde, cout
            # negligeable).
            # 13/10/2026 (suite), Tomyn : avec un fichier de plus d'1 million de triangles, Windows a
            # carrement affiche "Ne repond pas" sur la fenetre pendant l'attente, meme APRES l'ajout
            # du message de progression ci-dessus. Raison : & $EcrireLigne -> Ecrire-Journal fait deja
            # un DoEvents() a chaque appel, mais vu que le message ne sort que tous les 200 000
            # triangles, Windows ne voit la fenetre repondre que toutes les 2-3 minutes sur ce fichier
            # - largement au-dela des ~5 secondes que Windows tolere avant de marquer "Ne repond pas".
            # Donc deux compteurs separes maintenant : un DoEvents() direct et frequent (sans passer
            # par un message de journal, pour ne pas spammer) pour que la fenetre reste repondante en
            # continu, et le message de progression toujours tous les 200 000 triangles pour prouver
            # que ca avance sans noyer le journal.
            $etatCompteur = @{ N = 0 }
            $evaluateur = [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                $etatCompteur.N++
                if ($etatCompteur.N % 2000 -eq 0) {
                    [System.Windows.Forms.Application]::DoEvents()
                }
                if ($etatCompteur.N % 200000 -eq 0) {
                    & $EcrireLigne "  ... $($etatCompteur.N) triangle(s) traite(s), ca travaille toujours..."
                }
                $valeurOrigine = $m.Groups[1].Value
                if (-not $cacheDecalage.ContainsKey($valeurOrigine)) {
                    $cacheDecalage[$valeurOrigine] = & $scriptDecalerEtatPaintColor $valeurOrigine $groupeDe $etatsOrphelinsTrouves
                }
                return 'paint_color="' + $cacheDecalage[$valeurOrigine] + '"'
            }.GetNewClosure()
            foreach ($fichierModele in $fichiersModele) {
                $texteModele = [System.IO.File]::ReadAllText($fichierModele.FullName)
                $texteModeleRemappe = [System.Text.RegularExpressions.Regex]::Replace($texteModele, 'paint_color="([0-9A-Fa-f]+)"', $evaluateur)
                if ($texteModeleRemappe -ne $texteModele) {
                    [System.IO.File]::WriteAllText($fichierModele.FullName, $texteModeleRemappe)
                    & $EcrireLigne "  - $($fichierModele.Name) : couleurs remappees."
                }
            }
        } else {
            & $EcrireLigne "ATTENTION : aucun fichier .model trouve sous 3D/, le maillage n'a pas pu etre remappe."
        }

        if (Test-Path $cheminParamsModele) {
            $texteParams = [System.IO.File]::ReadAllText($cheminParamsModele)
            # key="extruder" value="N" : extrudeur par defaut d'un OBJET entier (pas par triangle,
            # contrairement a paint_color ci-dessus) - N est le meme numero de couleur d'origine
            # (1-based) que dans filament_colour, donc le meme lookup par groupe s'applique
            # (10/10/2026, avec le regroupement de couleurs). .GetNewClosure() necessaire pour que
            # $groupeDe soit visible ici, une fois ce bloc passe a Regex.Replace (meme regle que
            # pour $scriptDecalerEtatPaintColor plus haut).
            $evaluateurExtrudeur = [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                $ancienIndex = [int]$m.Groups[1].Value
                if ($ancienIndex -ge 1 -and $ancienIndex -le $groupeDe.Count) {
                    $nouvelIndex = 5 + $groupeDe[$ancienIndex - 1]
                } else {
                    $nouvelIndex = $ancienIndex
                    # 13/10/2026 : meme suivi que pour paint_color ci-dessus (extrudeur par defaut
                    # d'un objet entier qui pointe hors de la plage connue).
                    [void]$etatsOrphelinsTrouves.Add($ancienIndex)
                }
                return 'key="extruder" value="' + $nouvelIndex + '"'
            }.GetNewClosure()
            $texteParams = [System.Text.RegularExpressions.Regex]::Replace($texteParams, 'key="extruder" value="(\d+)"', $evaluateurExtrudeur)
            [System.IO.File]::WriteAllText($cheminParamsModele, $texteParams)
        }

        # 13/10/2026, Tomyn : avertissement sur les zones orphelines (voir le commentaire plus haut,
        # pres de $etatMaxRencontre) - rempli PENDANT le remappage ci-dessus (couts additionnel quasi
        # nul, juste un .Add() dans le cas deja rare "hors plage"), jamais par un passage separe.
        if ($etatsOrphelinsTrouves.Count -gt 0) {
            $etatMaxRencontre = ($etatsOrphelinsTrouves | Measure-Object -Maximum).Maximum
            $nombreZonesOrphelines = $etatsOrphelinsTrouves.Count
            & $EcrireLigne ""
            & $EcrireLigne "ATTENTION : $nombreZonesOrphelines zone(s) peinte(s) (ou objet(s)) referencent un numero de couleur allant jusqu'a $etatMaxRencontre, alors que seulement $nombreCouleursOrigine couleur(s) sont listees dans ce fichier (filament_colour) - ces zones ne correspondent a RIEN de declare et n'ont PAS ete melangees correctement sur ce passage. Pense a relancer le melange sur le fichier obtenu une deuxieme fois pour tenter de les rattraper (sans garantie que la teinte retrouvee alors soit la bonne)."
            & $EcrireLigne ""
        }

        # Correctif du 10/10/2026 (confirme en inspectant le fichier produit : toutes les entrees du
        # zip etaient nommees avec des antislashs, "3D\3dmodel.model" au lieu de "3D/3dmodel.model")
        # : [System.IO.Compression.ZipFile]::CreateFromDirectory() sur Windows PowerShell (.NET
        # Framework) nomme les entrees avec le separateur de chemin de l'OS (antislash), alors que le
        # format ZIP (et donc le 3MF, qui est un paquet OPC base sur ZIP) exige des slashs - Bambu
        # Studio n'a alors pas retrouve 3D/3dmodel.model et a affiche "le fichier ne contient pas de
        # donnees geometriques". On reconstruit le zip a la main, entree par entree, en forcant des
        # slashs - garanti conforme quel que soit le framework .NET utilise.
        & $EcrireLigne "Reconstruction du fichier .3mf..."
        if (Test-Path $cheminSortie) { Remove-Item $cheminSortie -Force }
        $fluxSortie = [System.IO.File]::Open($cheminSortie, [System.IO.FileMode]::Create)
        try {
            $archive = New-Object System.IO.Compression.ZipArchive($fluxSortie, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $tousLesFichiers = Get-ChildItem -Path $dossierTemp -Recurse -File
                foreach ($fichierASerialiser in $tousLesFichiers) {
                    $cheminRelatif = $fichierASerialiser.FullName.Substring($dossierTemp.Length + 1).Replace('\', '/')
                    $entreeZip = $archive.CreateEntry($cheminRelatif, [System.IO.Compression.CompressionLevel]::Optimal)
                    $fluxEntree = $entreeZip.Open()
                    try {
                        $fluxFichierSource = [System.IO.File]::OpenRead($fichierASerialiser.FullName)
                        try { $fluxFichierSource.CopyTo($fluxEntree) } finally { $fluxFichierSource.Dispose() }
                    } finally { $fluxEntree.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $fluxSortie.Dispose() }

        & $EcrireLigne ""
        & $EcrireLigne "Termine : $cheminSortie"
    } finally {
        if (Test-Path $dossierTemp) { Remove-Item $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ============================== ECRAN DE LANCEMENT ==============================
# Splash screen (10/10/2026, Tomyn : "un ecran de lancement comme tu avais fait pour Coloriser
# STL") - repris quasi tel quel de Coloriser-STL-GUI.ps1 (meme fenetre sans bordure, meme violet de
# banniere, meme logo "bobine" via Creer-ImageSpool, meme barre qui se remplit pendant que le reste
# du script construit le formulaire principal plus bas) : seuls le titre et le sous-titre changent.
# Le formulaire principal n'est pas encore lance a ce stade (pas de boucle de messages active avant
# le ShowDialog tout en bas du script), donc on pompe nous-memes les messages via
# [Application]::DoEvents() pendant l'animation - seule facon de faire avancer la barre et de
# laisser la fenetre se peindre (meme technique de DoEvents que celle deja utilisee par
# Ecrire-Journal plus bas).
$splash = New-Object System.Windows.Forms.Form
$splash.FormBorderStyle = "None"
$splash.StartPosition = "CenterScreen"
$splash.Size = New-Object System.Drawing.Size(380, 230)
$splash.BackColor = $THEME.FondBanniere
$splash.ShowInTaskbar = $false
$splash.TopMost = $true

try {
    $bmpSplash = Creer-ImageSpool 90 $THEME.FondBanniere
    $logoSplash = New-Object System.Windows.Forms.PictureBox
    $logoSplash.Image = $bmpSplash
    $logoSplash.SizeMode = "AutoSize"
    $logoSplash.Location = New-Object System.Drawing.Point((($splash.Width - 90) / 2), 28)
    $splash.Controls.Add($logoSplash)
} catch { }

$titreSplash = New-Object System.Windows.Forms.Label
$titreSplash.Text = "MelangeCouleurs"
$titreSplash.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
$titreSplash.ForeColor = [System.Drawing.Color]::White
$titreSplash.BackColor = [System.Drawing.Color]::Transparent
$titreSplash.AutoSize = $true
$splash.Controls.Add($titreSplash)
$titreSplash.Location = New-Object System.Drawing.Point((($splash.Width - $titreSplash.PreferredWidth) / 2), 128)

$sousTitreSplash = New-Object System.Windows.Forms.Label
$sousTitreSplash.Text = "Melange de couleurs primaires (3MF)"
$sousTitreSplash.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$sousTitreSplash.ForeColor = [System.Drawing.Color]::FromArgb(0xD8, 0xCC, 0xF5)
$sousTitreSplash.BackColor = [System.Drawing.Color]::Transparent
$sousTitreSplash.AutoSize = $true
$splash.Controls.Add($sousTitreSplash)
$sousTitreSplash.Location = New-Object System.Drawing.Point((($splash.Width - $sousTitreSplash.PreferredWidth) / 2), 160)

# Fine barre de progression maison plutot qu'une ProgressBar native (pas besoin du bricolage
# SendMessage utilise ailleurs dans Coloriser-STL juste pour la recolorer) : une piste violette plus
# sombre et un remplissage orange (meme accent que les boutons "chaud" de ce fichier), qui grandit
# pendant l'animation ci-dessous.
$pisteBarreSplash = New-Object System.Windows.Forms.Panel
$pisteBarreSplash.Size = New-Object System.Drawing.Size(260, 4)
$pisteBarreSplash.Location = New-Object System.Drawing.Point((($splash.Width - 260) / 2), 195)
$pisteBarreSplash.BackColor = [System.Drawing.Color]::FromArgb(0x36, 0x1D, 0x78)
$splash.Controls.Add($pisteBarreSplash)

$remplissageBarreSplash = New-Object System.Windows.Forms.Panel
$remplissageBarreSplash.Size = New-Object System.Drawing.Size(0, 4)
$remplissageBarreSplash.Location = New-Object System.Drawing.Point(0, 0)
$remplissageBarreSplash.BackColor = $THEME.AccentChaud
$pisteBarreSplash.Controls.Add($remplissageBarreSplash)

$splash.Show()
$splash.Refresh()

$etapesSplash = 24
for ($i = 1; $i -le $etapesSplash; $i++) {
    $remplissageBarreSplash.Width = [int]($pisteBarreSplash.Width * $i / $etapesSplash)
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 28
}

# ============================== FENETRE ==============================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Melange de couleurs 3MF [build 16/10 08h50]"
$form.Size = New-Object System.Drawing.Size(800, 1060)
$form.MinimumSize = New-Object System.Drawing.Size(800, 940)
$form.FormBorderStyle = "Sizable"
$form.StartPosition = "CenterScreen"
$form.BackColor = $THEME.FondApp
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

try {
    $bmpIcone = Creer-ImageSpool 64 $THEME.FondApp
    $form.Icon = [System.Drawing.Icon]::FromHandle($bmpIcone.GetHicon())
} catch { }

$banniere = New-Object System.Windows.Forms.Panel
$banniere.Dock = "Top"
$banniere.Height = $THEME.HauteurBanniere
$banniere.BackColor = $THEME.FondBanniere
$form.Controls.Add($banniere)

try {
    $bmpLogoBanniere = Creer-ImageSpool 36 $THEME.FondBanniere
    $logoBanniere = New-Object System.Windows.Forms.PictureBox
    $logoBanniere.Image = $bmpLogoBanniere
    $logoBanniere.Size = New-Object System.Drawing.Size(36, 36)
    $logoBanniere.Location = New-Object System.Drawing.Point(14, (($THEME.HauteurBanniere - 36) / 2))
    $logoBanniere.SizeMode = "AutoSize"
    $banniere.Controls.Add($logoBanniere)
} catch { }

$titreBanniere = New-Object System.Windows.Forms.Label
$titreBanniere.Text = "Melange de couleurs"
$titreBanniere.ForeColor = [System.Drawing.Color]::White
$titreBanniere.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
$titreBanniere.Location = New-Object System.Drawing.Point(60, 10)
$titreBanniere.AutoSize = $true
$banniere.Controls.Add($titreBanniere)

$sousTitreBanniere = New-Object System.Windows.Forms.Label
$sousTitreBanniere.Text = "Dosage automatique de trio a partir d'un .3mf colorise"
$sousTitreBanniere.ForeColor = [System.Drawing.Color]::FromArgb(210, 200, 245)
$sousTitreBanniere.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$sousTitreBanniere.Location = New-Object System.Drawing.Point(61, 32)
$sousTitreBanniere.AutoSize = $true
$banniere.Controls.Add($sousTitreBanniere)

$yActuel = $THEME.HauteurBanniere + 18

$labelFichier = New-Object System.Windows.Forms.Label
$labelFichier.Text = "Fichier .3mf colorise :"
$labelFichier.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelFichier.AutoSize = $true
$labelFichier.ForeColor = $THEME.Texte
$form.Controls.Add($labelFichier)
$yActuel += 20

$txtFichier = New-Object System.Windows.Forms.TextBox
$txtFichier.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtFichier.Size = New-Object System.Drawing.Size(600, 24)
$txtFichier.BackColor = $THEME.Surface
$txtFichier.AllowDrop = $true
$txtFichier.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = "Copy" } })
$txtFichier.Add_DragDrop({
    param($s, $e)
    $elements = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    if (-not $elements -or $elements.Count -eq 0) { return }
    if ($elements.Count -eq 1 -and (Test-Path $elements[0] -PathType Container)) {
        # Dossier depose entier (10/10/2026, Tomyn : "go les amelio") - meme chemin que le bouton
        # "Lot : un dossier...", juste declenche par glisser-deposer plutot que par le dialogue.
        # Lancer-LotDepuisDossier est defini plus bas dans le fichier, mais resolu par son NOM au
        # moment du clic (pas a la creation de cette closure) - l'ordre textuel n'a pas d'importance,
        # comme pour les autres boutons de ce fichier qui appellent des fonctions definies plus loin.
        Lancer-LotDepuisDossier $elements[0]
        return
    }
    if ($elements.Count -gt 1) {
        # Plusieurs fichiers deposes d'un coup - meme chemin que "Lot : plusieurs fichiers...", pas
        # besoin de rouvrir un dialogue de selection puisqu'ils sont deja choisis par le depot.
        $nomTrio = $menuTrio.SelectedItem.ToString()
        $trio = $TRIOS[$nomTrio]
        Afficher-ConfirmationLot $elements $nomTrio $trio
        return
    }
    # Un seul fichier depose : comportement d'origine, inchange.
    $txtFichier.Text = $elements[0]
    Mettre-A-Jour-Apercu $pictureAvant "avant" $elements[0]
    Mettre-A-Jour-SelecteurMelanges $elements[0]
    Mettre-A-Jour-AlerteDejaTraite $elements[0]
    Sauvegarder-DernierFichier $elements[0]
})
$form.Controls.Add($txtFichier)

$btnParcourir = New-Object System.Windows.Forms.Button
$btnParcourir.Text = "Parcourir..."
$btnParcourir.Location = New-Object System.Drawing.Point(625, ($yActuel - 1))
$btnParcourir.Size = New-Object System.Drawing.Size(100, 26)
Rendre-BoutonPlat $btnParcourir "secondaire"
$btnParcourir.Add_Click({
    $dialogue = New-Object System.Windows.Forms.OpenFileDialog
    $dialogue.Filter = "Fichiers 3MF (*.3mf)|*.3mf|Tous les fichiers (*.*)|*.*"
    if ($dialogue.ShowDialog() -eq "OK") {
        $txtFichier.Text = $dialogue.FileName
        Mettre-A-Jour-Apercu $pictureAvant "avant" $dialogue.FileName
        Mettre-A-Jour-SelecteurMelanges $dialogue.FileName
        Mettre-A-Jour-AlerteDejaTraite $dialogue.FileName
        Sauvegarder-DernierFichier $dialogue.FileName
    }
})
$form.Controls.Add($btnParcourir)

# 12/10/2026, idee d'amelioration validee "vaut le coup" : "Ouvrir le dossier contenant" a cote du
# fichier .3mf choisi, pour retrouver vite le dossier (notamment le resultat "..._melange.3mf" cree
# a cote de l'original) sans fouiller a la main dans l'explorateur. Meme mecanique que l'ouverture
# automatique deja faite apres "Lancer le melange" (explorer.exe /select, voir plus bas), juste
# disponible a la demande sur le fichier ACTUELLEMENT selectionne plutot qu'uniquement apres un
# traitement reussi.
$btnOuvrirDossier = New-Object System.Windows.Forms.Button
$btnOuvrirDossier.Text = "Ouvrir le dossier"
$btnOuvrirDossier.Location = New-Object System.Drawing.Point(735, ($yActuel - 1))
$btnOuvrirDossier.Size = New-Object System.Drawing.Size(140, 26)
Rendre-BoutonPlat $btnOuvrirDossier "discret"
$btnOuvrirDossier.Add_Click({
    $cheminActuel = $txtFichier.Text.Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($cheminActuel)) {
        Afficher-Boite "Choisis d'abord un fichier .3mf." "Aucun fichier selectionne" "OK" "Warning" | Out-Null
        return
    }
    if (-not (Test-Path $cheminActuel)) {
        Afficher-Boite "Ce fichier n'existe plus a cet emplacement :`r`n$cheminActuel" "Fichier introuvable" "OK" "Warning" | Out-Null
        return
    }
    try {
        Start-Process "explorer.exe" -ArgumentList "/select,`"$cheminActuel`""
    } catch {
        Afficher-Boite "Impossible d'ouvrir l'explorateur. Le fichier se trouve ici :`r`n$cheminActuel" "Erreur" "OK" "Error" | Out-Null
    }
})
$form.Controls.Add($btnOuvrirDossier)
$yActuel += 40

$labelTrio = New-Object System.Windows.Forms.Label
$labelTrio.Text = "Trio de primaires a utiliser :"
$labelTrio.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelTrio.AutoSize = $true
$labelTrio.ForeColor = $THEME.Texte
$form.Controls.Add($labelTrio)
$yActuel += 20

$menuTrio = New-Object System.Windows.Forms.ComboBox
$menuTrio.Location = New-Object System.Drawing.Point(15, $yActuel)
$menuTrio.Size = New-Object System.Drawing.Size(360, 24)
$menuTrio.DropDownStyle = "DropDownList"
foreach ($nom in Obtenir-NomsTriosOrdonnes) { [void]$menuTrio.Items.Add($nom) }
# Reprend le dernier trio utilise au lancement precedent s'il existe encore (11/10/2026,
# Tomyn : "toutes stp") - sinon (premier lancement, nom supprime depuis, JSON illisible), on
# retombe sur le tout premier de la liste comme avant.
$dernierTrioCharge = Charger-DernierTrio
if ($dernierTrioCharge -and $menuTrio.Items.Contains($dernierTrioCharge)) {
    $menuTrio.SelectedItem = $dernierTrioCharge
} else {
    $menuTrio.SelectedIndex = 0
}
Rendre-ComboBoxPlate $menuTrio $true
$form.Controls.Add($menuTrio)

# Bouton de gestion des trios personnalises (10/10/2026, Tomyn : "toutes stp") - a cote de la
# ComboBox plutot que dans un menu separe, pour rester visible sans chercher.
$btnGererTrios = New-Object System.Windows.Forms.Button
$btnGererTrios.Text = "Gerer mes trios..."
$btnGererTrios.Location = New-Object System.Drawing.Point(385, ($yActuel - 1))
$btnGererTrios.Size = New-Object System.Drawing.Size(170, 26)
Rendre-BoutonPlat $btnGererTrios "secondaire"
$btnGererTrios.Add_Click({ Afficher-GestionTrios })
$form.Controls.Add($btnGererTrios)
$yActuel += 30

# Gestion du "stock" de couleurs individuelles + suggestion de trios dedans (12/10/2026, Tomyn :
# "je rentre une 7, 8, 10, 20, 50 [couleurs] et ben il me dit avec tes couleurs ce serait bien
# que tu fasses des trio ca ca ca") - meme ligne que les deux boutons de trios ci-dessus,
# nouvelle rangee pour ne pas surcharger celle du dessus.
$btnGererCouleurs = New-Object System.Windows.Forms.Button
$btnGererCouleurs.Text = "Gerer mes couleurs..."
$btnGererCouleurs.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnGererCouleurs.Size = New-Object System.Drawing.Size(270, 26)
Rendre-BoutonPlat $btnGererCouleurs "secondaire"
$btnGererCouleurs.Add_Click({ Afficher-GestionCouleurs })
$form.Controls.Add($btnGererCouleurs)

$btnSuggererTriosDepuisCouleurs = New-Object System.Windows.Forms.Button
$btnSuggererTriosDepuisCouleurs.Text = "Suggerer des trios depuis mes couleurs..."
$btnSuggererTriosDepuisCouleurs.Location = New-Object System.Drawing.Point(295, $yActuel)
$btnSuggererTriosDepuisCouleurs.Size = New-Object System.Drawing.Size(285, 26)
Rendre-BoutonPlat $btnSuggererTriosDepuisCouleurs "secondaire"
$btnSuggererTriosDepuisCouleurs.Add_Click({ Afficher-SuggestionTriosDepuisCouleurs })
$form.Controls.Add($btnSuggererTriosDepuisCouleurs)
$yActuel += 32

# Pastilles de couleur + score de couverture du trio selectionne (11/10/2026, Tomyn : "toutes
# stp") - mis a jour par Mettre-A-Jour-ApercuTrioSelectionne (definie plus haut dans le fichier,
# juste apres Obtenir-SeuilAvertissementCouverture), appelee ci-dessous une premiere fois pour
# l'etat initial puis a chaque changement de selection dans le menu deroulant.
$panneauxPastilles = New-Object System.Windows.Forms.Panel[] 3
$xPastille = 15
for ($i = 0; $i -lt 3; $i++) {
    $panneau = New-Object System.Windows.Forms.Panel
    $panneau.Location = New-Object System.Drawing.Point($xPastille, $yActuel)
    $panneau.Size = New-Object System.Drawing.Size(22, 22)
    $panneau.BorderStyle = "FixedSingle"
    $form.Controls.Add($panneau)
    $panneauxPastilles[$i] = $panneau
    $xPastille += 26
}

$labelCouvertureTrio = New-Object System.Windows.Forms.Label
$labelCouvertureTrio.Location = New-Object System.Drawing.Point(($xPastille + 10), ($yActuel + 3))
$labelCouvertureTrio.Size = New-Object System.Drawing.Size(420, 18)
$labelCouvertureTrio.Font = New-Object System.Drawing.Font($labelCouvertureTrio.Font.FontFamily, 8)
$labelCouvertureTrio.ForeColor = $THEME.TexteSecondaire
$form.Controls.Add($labelCouvertureTrio)

$menuTrio.Add_SelectedIndexChanged({ Mettre-A-Jour-ApercuTrioSelectionne })
Mettre-A-Jour-ApercuTrioSelectionne

$yActuel += 32

# Verification de couverture PAR FICHIER (11/10/2026, Tomyn : "d'autres idees ?" -> "toutes") -
# complement du score "a vide" des pastilles ci-dessus : utilise le fichier deja saisi dans
# $txtFichier (le meme champ que "Lancer le melange") pour verifier concretement, sur SES couleurs
# a lui, si le trio selectionne couvre bien ou pas - voir Verifier-CouvertureFichier plus haut.
$btnVerifierCouverture = New-Object System.Windows.Forms.Button
$btnVerifierCouverture.Text = "Verifier la couverture du fichier..."
$btnVerifierCouverture.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnVerifierCouverture.Size = New-Object System.Drawing.Size(265, 28)
Rendre-BoutonPlat $btnVerifierCouverture "discret"
$btnVerifierCouverture.Add_Click({
    $cheminAVerifier = $txtFichier.Text.Trim('"').Trim()
    if (-not $cheminAVerifier -or -not (Test-Path $cheminAVerifier)) {
        Afficher-Boite "Choisis d'abord un fichier .3mf (meme champ que pour lancer le melange)." "Aucun fichier" "OK" "Warning" | Out-Null
        return
    }
    if (-not $menuTrio.SelectedItem) { return }
    $nomTrioAVerifier = $menuTrio.SelectedItem.ToString()
    $trioAVerifier = $TRIOS[$nomTrioAVerifier]
    $btnVerifierCouverture.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $resultat = Verifier-CouvertureFichier $cheminAVerifier $trioAVerifier
        if (-not $resultat) {
            Afficher-Boite "Impossible de lire les couleurs de ce fichier (pas un .3mf Bambu Studio avec des couleurs enregistrees ?)." "Lecture impossible" "OK" "Warning" | Out-Null
            return
        }
        $lignesRapport = Obtenir-LignesRapportCouverture $nomTrioAVerifier $resultat
        $cheminRapport = Exporter-RapportCouverture $cheminAVerifier $lignesRapport
        $texteRapport = $lignesRapport -join "`r`n"
        $lignePiedDePage = if ($cheminRapport) { "`r`n`r`nRapport exporte ici :`r`n$cheminRapport" } else { "`r`n`r`n(Rapport non exporte sur le disque, voir le journal.)" }
        if ($resultat.NombreMalCouvertes -eq 0) {
            Afficher-Boite "$texteRapport`r`n`r`nToutes les couleurs sont bien couvertes.$lignePiedDePage" "Couverture OK" "OK" "Info" | Out-Null
        } else {
            Afficher-Boite "$texteRapport`r`n`r`nCa ne bloque rien - juste une estimation avant de lancer un gros lot sur ce fichier-la.$lignePiedDePage" "Couverture a surveiller" "OK" "Warning" | Out-Null
        }
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnVerifierCouverture.Enabled = $true
    }
})
$form.Controls.Add($btnVerifierCouverture)

# Comparer deux trios sur le MEME fichier (11/10/2026, Tomyn : "1-2-3-4") - avant un gros lot,
# voir cote a cote lequel de deux trios couvre le mieux CE fichier precis (pas juste leur score
# "a vide" des pastilles), via la meme Verifier-CouvertureFichier que le bouton juste au-dessus.
$btnComparerTrios = New-Object System.Windows.Forms.Button
$btnComparerTrios.Text = "Comparer deux trios..."
$btnComparerTrios.Location = New-Object System.Drawing.Point(290, $yActuel)
$btnComparerTrios.Size = New-Object System.Drawing.Size(195, 28)
Rendre-BoutonPlat $btnComparerTrios "discret"
$btnComparerTrios.Add_Click({
    $cheminAVerifier = $txtFichier.Text.Trim('"').Trim()
    if (-not $cheminAVerifier -or -not (Test-Path $cheminAVerifier)) {
        Afficher-Boite "Choisis d'abord un fichier .3mf (meme champ que pour lancer le melange)." "Aucun fichier" "OK" "Warning" | Out-Null
        return
    }

    $popupComparaison = New-Object System.Windows.Forms.Form
    $popupComparaison.Text = "Comparer deux trios sur ce fichier"
    $popupComparaison.StartPosition = "CenterParent"
    $popupComparaison.FormBorderStyle = "FixedDialog"
    $popupComparaison.MaximizeBox = $false
    $popupComparaison.MinimizeBox = $false
    $popupComparaison.ClientSize = New-Object System.Drawing.Size(360, 160)

    $labelA = New-Object System.Windows.Forms.Label
    $labelA.Text = "Trio A :"
    $labelA.Location = New-Object System.Drawing.Point(10, 14)
    $labelA.AutoSize = $true
    $popupComparaison.Controls.Add($labelA)

    $menuTrioA = New-Object System.Windows.Forms.ComboBox
    $menuTrioA.Location = New-Object System.Drawing.Point(10, 34)
    $menuTrioA.Size = New-Object System.Drawing.Size(340, 24)
    $menuTrioA.DropDownStyle = "DropDownList"
    foreach ($nom in Obtenir-NomsTriosOrdonnes) { [void]$menuTrioA.Items.Add($nom) }
    if ($menuTrio.SelectedItem -and $menuTrioA.Items.Contains($menuTrio.SelectedItem.ToString())) {
        $menuTrioA.SelectedItem = $menuTrio.SelectedItem.ToString()
    } elseif ($menuTrioA.Items.Count -gt 0) { $menuTrioA.SelectedIndex = 0 }
    $popupComparaison.Controls.Add($menuTrioA)

    $labelB = New-Object System.Windows.Forms.Label
    $labelB.Text = "Trio B :"
    $labelB.Location = New-Object System.Drawing.Point(10, 66)
    $labelB.AutoSize = $true
    $popupComparaison.Controls.Add($labelB)

    $menuTrioB = New-Object System.Windows.Forms.ComboBox
    $menuTrioB.Location = New-Object System.Drawing.Point(10, 86)
    $menuTrioB.Size = New-Object System.Drawing.Size(340, 24)
    $menuTrioB.DropDownStyle = "DropDownList"
    foreach ($nom in Obtenir-NomsTriosOrdonnes) { [void]$menuTrioB.Items.Add($nom) }
    if ($menuTrioB.Items.Count -gt 1) { $menuTrioB.SelectedIndex = 1 } elseif ($menuTrioB.Items.Count -gt 0) { $menuTrioB.SelectedIndex = 0 }
    $popupComparaison.Controls.Add($menuTrioB)

    $btnComparer = New-Object System.Windows.Forms.Button
    $btnComparer.Text = "Comparer"
    $btnComparer.Location = New-Object System.Drawing.Point(255, 120)
    $btnComparer.Size = New-Object System.Drawing.Size(95, 28)
    Rendre-BoutonPlat $btnComparer "principal"
    $btnComparer.Add_Click({
        if (-not $menuTrioA.SelectedItem -or -not $menuTrioB.SelectedItem) { return }
        $nomA = $menuTrioA.SelectedItem.ToString()
        $nomB = $menuTrioB.SelectedItem.ToString()
        $popupComparaison.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $resultatA = Verifier-CouvertureFichier $cheminAVerifier $TRIOS[$nomA]
            $resultatB = Verifier-CouvertureFichier $cheminAVerifier $TRIOS[$nomB]
        } finally {
            $popupComparaison.Cursor = [System.Windows.Forms.Cursors]::Default
        }
        $lignesA = Obtenir-LignesRapportCouverture $nomA $resultatA
        $lignesB = Obtenir-LignesRapportCouverture $nomB $resultatB
        $toutesLesLignes = $lignesA + @("") + $lignesB
        $cheminRapport = Exporter-RapportCouverture $cheminAVerifier $toutesLesLignes
        $lignePiedDePage = if ($cheminRapport) { "`r`n`r`nRapport exporte ici :`r`n$cheminRapport" } else { "" }
        Afficher-Boite (($toutesLesLignes -join "`r`n") + $lignePiedDePage) "Comparaison de couverture" "OK" "Info" | Out-Null
    }.GetNewClosure())
    $popupComparaison.Controls.Add($btnComparer)
    $popupComparaison.AcceptButton = $btnComparer

    [void]$popupComparaison.ShowDialog($form)
})
$form.Controls.Add($btnComparerTrios)
$yActuel += 36

# Suggerer un trio (12/10/2026, Tomyn : apres avoir decouvert sur un vrai fichier - un chien aux
# tons pastel/lavande - que son trio RYB ne pouvait pas du tout approcher ces teintes, faute de
# primaire claire. Plutot que de lui faire comparer les trios un par un via le bouton ci-dessus,
# ce bouton teste TOUS les trios "utilisables" sur le fichier choisi et applique directement celui
# qui a l'ecart Lab moyen le plus faible - une reponse nette ("prends celui-la"), pas un classement
# a eplucher (Tomyn : "le classement je m'en fous un peu"). Candidats = TOUS ses trios personnalises
# sauvegardes (plus, a l'origine, les presets CMY/RYB - retires du menu le 12/10/2026 a sa demande,
# voir le commentaire sur $TRIOS plus haut - donc deja absents de $TRIOS.Keys ; Pastel/Neon restent
# explicitement exclus ici au cas ou Tomyn les garderait un jour dans le menu). Reutilise
# Verifier-CouvertureFichier, deja ecrite pour le bouton "Verifier la couverture" juste au-dessus -
# meme calcul, juste repete sur plusieurs trios puis trie.
$script:NomsPresetsExclusDeLaSuggestion = @("Pastel", "Neon")
function Obtenir-CandidatsSuggestionTrio {
    return @($TRIOS.Keys | Where-Object { $script:NomsPresetsExclusDeLaSuggestion -notcontains $_ })
}

# "Suggerer 5 trios differents pour ce fichier..." (12/10/2026, Tomyn : le bouton ci-dessous applique
# directement LE meilleur trio, mais Tomyn veut parfois comparer plusieurs options valables plutot
# que d'avoir une seule reponse imposee - avec une contrainte explicite : "je suis sur que dans les
# cinq trio il va toujours me proposer du blanc ... le blanc c'est compliquer a trouver". Le blanc
# est en effet quasi toujours un bon choix de primaire (aire de couverture large), donc un classement
# brut par ecart Lab ressortirait du blanc dans presque toutes les meilleures combinaisons - inutile
# si Tomyn ne peut pas se reapprovisionner facilement en blanc.
#
# Teste la meme reunion de candidats que Obtenir-CandidatsSuggestionTrio (trios sauvegardes, CMY/RYB
# mais pas Pastel/Neon) PLUS toutes les combinaisons de 3 du stock individuel (meme recherche que
# Obtenir-MeilleureComboDepuisCouleursPourFichier, mais on garde tous les resultats au lieu de ne
# garder que le meilleur), les trie par ecart Lab moyen croissant, puis les choisit un par un avec
# deux regles de diversite :
#   - un trio n'est retenu que s'il ne partage pas plus de $maxCommuns couleur(s) (meme code hex) avec
#     un trio deja retenu - on commence stricte (0 couleur commune) et on ne relache (1, puis 2) que
#     si la liste stricte ne suffit pas a atteindre $nombreVoulu ;
#   - un seul trio "a dominante blanche" (L* Lab > 90, meme seuil que "quasi blanc" visuel) est
#     accepte au total, meme si plusieurs scoreraient tres bien - les autres emplacements vont aux
#     meilleurs trios SANS blanc.
function Obtenir-TrioEstBlancDominant([array]$composants) {
    foreach ($composant in $composants) {
        $rgb = Obtenir-RGBDepuisHex $composant.Hex
        $lab = Convertir-RGBVersLab $rgb.R $rgb.G $rgb.B
        if ($lab.L -gt 90) { return $true }
    }
    return $false
}
function Obtenir-NombreHexCommuns([array]$composantsA, [array]$composantsB) {
    $hexA = @($composantsA | ForEach-Object { $_.Hex.ToUpper() })
    $hexB = @($composantsB | ForEach-Object { $_.Hex.ToUpper() })
    $communs = 0
    foreach ($hex in $hexA) { if ($hexB -contains $hex) { $communs++ } }
    return $communs
}
function Obtenir-SuggestionsTriosDiversifiees([string]$chemin3mf, [int]$nombreVoulu) {
    $candidats = New-Object System.Collections.Generic.List[object]
    # 16/10/2026 : extrait les couleurs du .3mf UNE SEULE FOIS ici (voir Verifier-CouvertureAvecCouleurs
    # plus haut) - avant, chacun des appels Verifier-CouvertureFichier ci-dessous (un par trio
    # personnalise, PLUS un par combinaison de 3 du stock de couleurs, potentiellement des centaines)
    # redezippait le meme fichier inchange a chaque fois. Avec "beaucoup de trios perso", ca rendait
    # ce bouton tres long (signale par Tomyn).
    $couleursFichier = Obtenir-CouleursFichier3MF $chemin3mf

    foreach ($nom in (Obtenir-CandidatsSuggestionTrio)) {
        $resultat = Verifier-CouvertureAvecCouleurs $couleursFichier $TRIOS[$nom]
        if ($resultat) { [void]$candidats.Add(@{ Nom = $nom; Composants = $TRIOS[$nom]; Resultat = $resultat }) }
    }

    $n = $script:MesCouleurs.Count
    if ($n -ge 3) {
        for ($i = 0; $i -lt $n - 2; $i++) {
            for ($j = $i + 1; $j -lt $n - 1; $j++) {
                for ($k = $j + 1; $k -lt $n; $k++) {
                    $combo = @($script:MesCouleurs[$i], $script:MesCouleurs[$j], $script:MesCouleurs[$k])
                    $resultat = Verifier-CouvertureAvecCouleurs $couleursFichier $combo
                    if ($resultat) {
                        $nomCombo = ($combo | ForEach-Object { $_.Nom }) -join " + "
                        [void]$candidats.Add(@{ Nom = $nomCombo; Composants = $combo; Resultat = $resultat })
                    }
                }
            }
        }
    }

    if ($candidats.Count -eq 0) { return @() }
    $tries = @($candidats | Sort-Object { $_.Resultat.EcartMoyen })

    $choisis = New-Object System.Collections.Generic.List[object]
    $nombreBlancsChoisis = 0
    foreach ($maxCommuns in 0, 1, 2) {
        if ($choisis.Count -ge $nombreVoulu) { break }
        foreach ($candidat in $tries) {
            if ($choisis.Count -ge $nombreVoulu) { break }
            $estBlanc = Obtenir-TrioEstBlancDominant $candidat.Composants
            if ($estBlanc -and $nombreBlancsChoisis -ge 1) { continue }
            $conflit = $false
            foreach ($dejaChoisi in $choisis) {
                if ((Obtenir-NombreHexCommuns $candidat.Composants $dejaChoisi.Composants) -gt $maxCommuns) { $conflit = $true; break }
            }
            if ($conflit) { continue }
            [void]$choisis.Add($candidat)
            if ($estBlanc) { $nombreBlancsChoisis++ }
        }
    }
    return @($choisis | Select-Object -First $nombreVoulu)
}

# Popup d'affichage pour Obtenir-SuggestionsTriosDiversifiees - meme gabarit visuel que
# Afficher-SuggestionTriosDepuisCouleurs (pastilles + nom + bouton par ligne), mais le bouton
# "Appliquer..." fait les deux etapes d'un coup : si la combinaison n'est pas deja un trio
# sauvegarde/preset (cas des combos venant du stock), elle demande d'abord un nom et la sauvegarde
# (reutilise Demander-NomEtSauvegarderTrio), puis selectionne le trio dans $menuTrio - qui declenche
# l'apercu avant/apres comme partout ailleurs dans l'outil.
function Afficher-SuggestionsTriosDiversifiees([string]$chemin3mf, [array]$suggestions) {
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = "5 trios differents pour ce fichier"
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox = $false
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(480, (60 + $suggestions.Count * 50 + 50))

    $labelIntro = New-Object System.Windows.Forms.Label
    $labelIntro.Text = "Du plus fidele au moins fidele sur ce fichier, couleurs volontairement variees (1 trio blanc max) :"
    $labelIntro.Location = New-Object System.Drawing.Point(10, 10)
    $labelIntro.Size = New-Object System.Drawing.Size(460, 32)
    $popup.Controls.Add($labelIntro)

    $yLigne = 46
    foreach ($suggestion in $suggestions) {
        $labelSuggestion = New-Object System.Windows.Forms.Label
        $labelSuggestion.Text = "$($suggestion.Nom)  (ecart moyen $([Math]::Round($suggestion.Resultat.EcartMoyen, 1)))"
        $labelSuggestion.Location = New-Object System.Drawing.Point(10, ($yLigne + 5))
        $labelSuggestion.Size = New-Object System.Drawing.Size(345, 20)
        $labelSuggestion.AutoEllipsis = $true
        $popup.Controls.Add($labelSuggestion)

        $xPastille = 10
        foreach ($composant in $suggestion.Composants) {
            $pastille = New-Object System.Windows.Forms.Panel
            $pastille.Location = New-Object System.Drawing.Point($xPastille, ($yLigne + 24))
            $pastille.Size = New-Object System.Drawing.Size(16, 16)
            $pastille.BorderStyle = "FixedSingle"
            try { $pastille.BackColor = [System.Drawing.ColorTranslator]::FromHtml($composant.Hex) } catch { }
            $popup.Controls.Add($pastille)
            $xPastille += 20
        }

        $btnAppliquerSuggestion = New-Object System.Windows.Forms.Button
        $btnAppliquerSuggestion.Text = "Appliquer..."
        $btnAppliquerSuggestion.Location = New-Object System.Drawing.Point(365, $yLigne)
        $btnAppliquerSuggestion.Size = New-Object System.Drawing.Size(105, 26)
        Rendre-BoutonPlat $btnAppliquerSuggestion "secondaire"
        $btnAppliquerSuggestion.Tag = $suggestion
        $btnAppliquerSuggestion.Add_Click({
            $suggestionChoisie = $btnAppliquerSuggestion.Tag
            $nomAAppliquer = $suggestionChoisie.Nom
            if (-not $menuTrio.Items.Contains($nomAAppliquer)) {
                $nomSauvegarde = Demander-NomEtSauvegarderTrio $popup $suggestionChoisie.Composants
                if (-not $nomSauvegarde) { return }
                $nomAAppliquer = $nomSauvegarde
            }
            if ($menuTrio.Items.Contains($nomAAppliquer)) { $menuTrio.SelectedItem = $nomAAppliquer }
            $popup.Close()
        }.GetNewClosure())
        $popup.Controls.Add($btnAppliquerSuggestion)

        $yLigne += 50
    }

    $btnFermerSuggestions = New-Object System.Windows.Forms.Button
    $btnFermerSuggestions.Text = "Fermer"
    $btnFermerSuggestions.Location = New-Object System.Drawing.Point(365, ($yLigne + 6))
    $btnFermerSuggestions.Size = New-Object System.Drawing.Size(105, 28)
    Rendre-BoutonPlat $btnFermerSuggestions "discret"
    $btnFermerSuggestions.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnFermerSuggestions)
    $popup.CancelButton = $btnFermerSuggestions

    [void]$popup.ShowDialog($form)
}

$btnSuggererTrio = New-Object System.Windows.Forms.Button
$btnSuggererTrio.Text = "Suggerer un trio pour ce fichier..."
$btnSuggererTrio.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnSuggererTrio.Size = New-Object System.Drawing.Size(470, 28)
Rendre-BoutonPlat $btnSuggererTrio "discret"
$btnSuggererTrio.Add_Click({
    $cheminAVerifier = $txtFichier.Text.Trim('"').Trim()
    if (-not $cheminAVerifier -or -not (Test-Path $cheminAVerifier)) {
        Afficher-Boite "Choisis d'abord un fichier .3mf (meme champ que pour lancer le melange)." "Aucun fichier" "OK" "Warning" | Out-Null
        return
    }
    $candidats = @(Obtenir-CandidatsSuggestionTrio)
    if ($candidats.Count -eq 0) {
        Afficher-Boite "Aucun trio personnalise a tester." "Rien a comparer" "OK" "Warning" | Out-Null
        return
    }
    $btnSuggererTrio.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        # 16/10/2026, Tomyn : "quand j'ai beaucoup de trio perso ... c'est ultra long" - le fichier
        # etait redezippe UNE FOIS PAR TRIO teste (voir Verifier-CouvertureAvecCouleurs plus haut
        # pour le detail). Extrait une seule fois ici, reutilise pour chaque trio ET pour la
        # recherche dans "mes couleurs" juste en dessous si besoin.
        $couleursFichier = Obtenir-CouleursFichier3MF $cheminAVerifier
        $meilleurNom = $null
        $meilleurResultat = $null
        # 16/10/2026, Tomyn : "le trio proposé change à chaque clic, sans rien faire d'autre entre
        # les deux" - en theorie impossible vu que tout le calcul ci-dessous est pur (meme fichier,
        # memes trios -> meme resultat), donc avant de deviner une cause, on journalise le classement
        # COMPLET de ce passage (tous les candidats testes + leur ecart exact, pas arrondi) dans le
        # panneau "Avancement". Si le classement differe d'un clic a l'autre pour un meme fichier
        # inchange, ca prouvera qu'un des candidats (ou le fichier lu) change reellement entre les
        # clics, au lieu de deviner.
        $resultatsTousLesCandidats = New-Object System.Collections.Generic.List[object]
        foreach ($nom in $candidats) {
            $resultat = Verifier-CouvertureAvecCouleurs $couleursFichier $TRIOS[$nom]
            if (-not $resultat) { continue }
            [void]$resultatsTousLesCandidats.Add(@{ Nom = $nom; Ecart = $resultat.EcartMoyen })
            if (-not $meilleurResultat -or $resultat.EcartMoyen -lt $meilleurResultat.EcartMoyen) {
                $meilleurNom = $nom
                $meilleurResultat = $resultat
            }
        }
        Ecrire-Journal "--- Suggestion de trio pour $(Split-Path $cheminAVerifier -Leaf) ($($resultatsTousLesCandidats.Count) trio(s) teste(s)) : ---"
        foreach ($r in ($resultatsTousLesCandidats | Sort-Object Ecart)) {
            Ecrire-Journal ("  $($r.Nom) : ecart $([Math]::Round($r.Ecart, 3))")
        }
        if (-not $meilleurResultat) {
            Afficher-Boite "Impossible de lire les couleurs de ce fichier (pas un .3mf Bambu Studio avec des couleurs enregistrees ?)." "Lecture impossible" "OK" "Warning" | Out-Null
            return
        }
        # Applique directement le trio gagnant (declenche Mettre-A-Jour-ApercuTrioSelectionne via
        # SelectedIndexChanged) - pas besoin d'un second clic "Appliquer" separe.
        if ($menuTrio.Items.Contains($meilleurNom)) { $menuTrio.SelectedItem = $meilleurNom }
        $messageResultat = "Trio applique : $meilleurNom`r`n`r`nEcart Lab moyen sur ce fichier : $([Math]::Round($meilleurResultat.EcartMoyen, 1))`r`n$($meilleurResultat.NombreMalCouvertes) couleur(s) sur $($meilleurResultat.NombreCouleurs) risquent d'etre visiblement mal rendues."
        if ($meilleurResultat.EcartMoyen -gt 12.0) {
            $messageResultat += "`r`n`r`nMeme le meilleur de tes trios reste moyen sur ce fichier (ecart > 12)."
            # Aucun trio sauvegarde ne convient bien - avant de conclure qu'il faut en racheter,
            # on cherche aussi dans le stock de couleurs individuelles (12/10/2026, Tomyn : "s'il
            # trouve pas le trio adequat ... propose ca ca et la ca marche") une combinaison de 3
            # qui ferait mieux, meme si elle n'a jamais ete sauvegardee comme trio.
            if ($script:MesCouleurs.Count -ge 3) {
                $meilleureComboStock = Obtenir-MeilleureComboDepuisCouleursPourFichier $couleursFichier $script:MesCouleurs
                if ($meilleureComboStock -and $meilleureComboStock.Resultat.EcartMoyen -lt $meilleurResultat.EcartMoyen) {
                    $nomsComboStock = ($meilleureComboStock.Composants | ForEach-Object { $_.Nom }) -join " + "
                    $messageResultat += "`r`n`r`nEn revanche, dans tes couleurs individuelles (Gerer mes couleurs...), la combinaison '$nomsComboStock' ferait mieux : ecart moyen $([Math]::Round($meilleureComboStock.Resultat.EcartMoyen, 1)) au lieu de $([Math]::Round($meilleurResultat.EcartMoyen, 1))."
                    Afficher-Boite $messageResultat "Trio suggere" "OK" "Info" | Out-Null
                    if ((Afficher-Boite "Veux-tu l'enregistrer comme nouveau trio et l'appliquer tout de suite ?" "Nouvelle combinaison trouvee" "YesNo" "Question") -eq [System.Windows.Forms.DialogResult]::Yes) {
                        $nomSauvegarde = Demander-NomEtSauvegarderTrio $form $meilleureComboStock.Composants
                        if ($nomSauvegarde -and $menuTrio.Items.Contains($nomSauvegarde)) { $menuTrio.SelectedItem = $nomSauvegarde }
                    }
                    return
                }
            } else {
                $messageResultat += "`r`n`r`nTu peux aussi entrer tes couleurs une par une dans 'Gerer mes couleurs...' pour que l'outil cherche directement une meilleure combinaison dedans."
            }
        }
        Afficher-Boite $messageResultat "Trio suggere" "OK" "Info" | Out-Null
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnSuggererTrio.Enabled = $true
    }
})
$form.Controls.Add($btnSuggererTrio)
$yActuel += 36

# Bouton "Suggerer 5 trios differents..." (12/10/2026, Tomyn, cf. commentaire au-dessus de
# Obtenir-SuggestionsTriosDiversifiees) - a cote du bouton ci-dessus qui n'applique que LE meilleur,
# celui-ci affiche 5 options valables et volontairement variees entre elles.
$btnSuggerer5Trios = New-Object System.Windows.Forms.Button
$btnSuggerer5Trios.Text = "Suggerer 5 trios differents pour ce fichier..."
$btnSuggerer5Trios.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnSuggerer5Trios.Size = New-Object System.Drawing.Size(470, 28)
Rendre-BoutonPlat $btnSuggerer5Trios "discret"
$btnSuggerer5Trios.Add_Click({
    $cheminAVerifier = $txtFichier.Text.Trim('"').Trim()
    if (-not $cheminAVerifier -or -not (Test-Path $cheminAVerifier)) {
        Afficher-Boite "Choisis d'abord un fichier .3mf (meme champ que pour lancer le melange)." "Aucun fichier" "OK" "Warning" | Out-Null
        return
    }
    $btnSuggerer5Trios.Enabled = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $suggestions = @(Obtenir-SuggestionsTriosDiversifiees $cheminAVerifier 5)
        if ($suggestions.Count -eq 0) {
            Afficher-Boite "Impossible de lire les couleurs de ce fichier, ou aucun trio/combinaison exploitable (trios personnalises et couleurs de 'Gerer mes couleurs...')." "Rien a proposer" "OK" "Warning" | Out-Null
            return
        }
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnSuggerer5Trios.Enabled = $true
    }
    Afficher-SuggestionsTriosDiversifiees $cheminAVerifier $suggestions
})
$form.Controls.Add($btnSuggerer5Trios)
$yActuel += 36

# Selecteur du nombre de melanges (10/10/2026, demande par Tomyn ; plafond recalcule le 11/10/2026
# au passage de l'outil en mode trio) : 3 primaires fixes + jusqu'a 29 melanges = 32 emplacements au
# total (le maximum de l'AMS). Pre-rempli automatiquement avec le nombre de couleurs detectees dans
# le fichier choisi (plafonne a 29) - le rabaisser regroupe les couleurs les plus proches (voir
# Regrouper-CouleursParProximite) au lieu d'en faire un melange par couleur ; plus il y a de
# melanges, plus le resultat est fidele au modele d'origine.
$labelMelanges = New-Object System.Windows.Forms.Label
$labelMelanges.Text = "Nombre de melanges (1 a 29, en plus des 3 primaires) :"
$labelMelanges.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelMelanges.AutoSize = $true
$labelMelanges.ForeColor = $THEME.Texte
$form.Controls.Add($labelMelanges)
$yActuel += 20

$selecteurMelanges = New-Object System.Windows.Forms.NumericUpDown
$selecteurMelanges.Location = New-Object System.Drawing.Point(15, $yActuel)
$selecteurMelanges.Size = New-Object System.Drawing.Size(80, 24)
$selecteurMelanges.Minimum = 1
$selecteurMelanges.Maximum = 29
$selecteurMelanges.Value = 29
$selecteurMelanges.BackColor = $THEME.Surface
$selecteurMelanges.ForeColor = $THEME.Texte
$form.Controls.Add($selecteurMelanges)
$yActuel += 40

# Pre-remplit le selecteur avec le nombre de couleurs reellement detectees dans le fichier choisi
# (plafonne a 29) - evite d'avoir a y toucher si on veut simplement "un melange par couleur",
# comportement d'origine avant l'ajout de ce selecteur.
function Mettre-A-Jour-SelecteurMelanges([string]$chemin3mf) {
    try {
        $nombre = Obtenir-NombreCouleursDetectees $chemin3mf
        if ($nombre -gt 0) {
            $selecteurMelanges.Value = [Math]::Min($nombre, 29)
        }
    } catch { }
}

# Precision du dosage (11/10/2026, Tomyn : "1-2-3-4") - c'etait fige a 5% dans le code (le "pas"
# avec lequel Trouver-MeilleurDosage balaie les combinaisons de pourcentages des 3 primaires) ;
# expose ici pour pouvoir descendre a 1% sur une piece importante (calcul plus fin mais plus lent -
# le nombre de combinaisons testees explose quand le pas diminue) ou remonter a 20% pour aller vite
# sur un brouillon. Utilise aussi bien par "Lancer le melange" que par le traitement en lot (voir
# Traiter-LotDeFichiers plus bas) - meme reglage pour les deux plutot que de le dupliquer.
$labelPrecision = New-Object System.Windows.Forms.Label
$labelPrecision.Text = "Precision du dosage (pas en %, 1 = fin/lent, 20 = rapide/grossier) :"
$labelPrecision.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelPrecision.AutoSize = $true
$labelPrecision.ForeColor = $THEME.Texte
$form.Controls.Add($labelPrecision)
$yActuel += 20

$selecteurPrecision = New-Object System.Windows.Forms.NumericUpDown
$selecteurPrecision.Location = New-Object System.Drawing.Point(15, $yActuel)
$selecteurPrecision.Size = New-Object System.Drawing.Size(80, 24)
$selecteurPrecision.Minimum = 1
$selecteurPrecision.Maximum = 20
$selecteurPrecision.Value = 5
$selecteurPrecision.BackColor = $THEME.Surface
$selecteurPrecision.ForeColor = $THEME.Texte
$form.Controls.Add($selecteurPrecision)
$yActuel += 40

$btnLancer = New-Object System.Windows.Forms.Button
$btnLancer.Text = "Lancer le melange"
$btnLancer.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnLancer.Size = New-Object System.Drawing.Size(200, 36)
Rendre-BoutonPlat $btnLancer "principal"
$form.Controls.Add($btnLancer)

# Mode "test rapide" (11/10/2026, Tomyn : "1-2-3-4") - calcule les dosages et le rapport normal
# dans le journal, mais ECRIT le resultat dans un fichier TEMPORAIRE qui est supprime juste apres
# au lieu du "..._melange.3mf" a cote du fichier d'origine : pratique pour essayer un trio sans
# polluer le dossier avec des fichiers d'essai a chaque fois. Pas de confirmation d'ecrasement, pas
# d'ouverture de l'explorateur, pas de ligne d'historique (ce n'est pas un vrai resultat produit) -
# voir $btnLancer.Add_Click plus bas.
$caseTestRapide = New-Object System.Windows.Forms.CheckBox
$caseTestRapide.Text = "Test rapide (sans ecrire de fichier)"
$caseTestRapide.Location = New-Object System.Drawing.Point(225, ($yActuel + 8))
$caseTestRapide.Size = New-Object System.Drawing.Size(260, 24)
$caseTestRapide.ForeColor = $THEME.Texte
$form.Controls.Add($caseTestRapide)
$yActuel += 44

# 12/10/2026, idee d'amelioration validee "vaut le coup" : rappel si le fichier .3mf actuellement
# choisi a deja ete traite auparavant (relit historique-lots.log, deja alimente par Ajouter-
# LigneHistorique a chaque traitement reussi) - evite de refaire deux fois le meme fichier sans
# s'en rendre compte. Invisible par defaut, mis a jour par Mettre-A-Jour-AlerteDejaTraite ci-
# dessous (appelee partout ou $txtFichier.Text change : Parcourir, glisser-depose, rechargement du
# dernier fichier au demarrage).
$labelDejaTraite = New-Object System.Windows.Forms.Label
$labelDejaTraite.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelDejaTraite.Size = New-Object System.Drawing.Size(600, 18)
$labelDejaTraite.Font = New-Object System.Drawing.Font($labelDejaTraite.Font.FontFamily, 8)
$labelDejaTraite.ForeColor = $THEME.AccentChaud
$labelDejaTraite.Visible = $false
$form.Controls.Add($labelDejaTraite)
$yActuel += 22

function Mettre-A-Jour-AlerteDejaTraite([string]$chemin3mf) {
    try {
        $derniereUtilisation = Obtenir-DerniereUtilisationHistorique $chemin3mf
        if ($derniereUtilisation) {
            $dateAffichee = try { (Get-Date $derniereUtilisation.Date).ToString("dd/MM 'a' HH:mm") } catch { $derniereUtilisation.Date }
            $labelDejaTraite.Text = "Deja melange le $dateAffichee avec le trio '$($derniereUtilisation.Trio)'."
            $labelDejaTraite.Visible = $true
        } else {
            $labelDejaTraite.Visible = $false
        }
    } catch { $labelDejaTraite.Visible = $false }
}

# Traitement en lot (10/10/2026, Tomyn : "je voudrais arriver a terme ne pas faire qu'un .3mf mais
# en faire plusieurs voir un dossier complet") - deux points d'entree distincts plutot qu'un seul
# dialogue a choix multiple, plus direct : "un dossier" prend tous les .3mf d'un dossier (PAS les
# sous-dossiers - pas demande, facile a changer plus tard si besoin), "plusieurs fichiers" ouvre un
# choix multiple classique pour des fichiers eparpilles. Les deux appellent la MEME fonction
# Traiter-LotDeFichiers une fois la liste de chemins constituee - voir plus bas.
$btnLotDossier = New-Object System.Windows.Forms.Button
$btnLotDossier.Text = "Lot : un dossier..."
$btnLotDossier.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnLotDossier.Size = New-Object System.Drawing.Size(195, 32)
Rendre-BoutonPlat $btnLotDossier "secondaire"
$form.Controls.Add($btnLotDossier)

$btnLotFichiers = New-Object System.Windows.Forms.Button
$btnLotFichiers.Text = "Lot : plusieurs fichiers..."
$btnLotFichiers.Location = New-Object System.Drawing.Point(215, $yActuel)
$btnLotFichiers.Size = New-Object System.Drawing.Size(195, 32)
Rendre-BoutonPlat $btnLotFichiers "secondaire"
$form.Controls.Add($btnLotFichiers)
$yActuel += 40

# Historique cumulatif (11/10/2026, Tomyn : "toutes stp") - ouvre historique-lots.log (alimente par
# Ajouter-LigneHistorique, voir plus haut) dans l'editeur de texte par defaut de Windows, pour
# retrouver rapidement quel trio a ete utilise sur quel fichier et quand. Juste un raccourci
# pratique vers un fichier texte tout simple, pas une fenetre custom - rien a construire de plus.
$btnVoirHistorique = New-Object System.Windows.Forms.Button
$btnVoirHistorique.Text = "Voir l'historique..."
$btnVoirHistorique.Location = New-Object System.Drawing.Point(15, $yActuel)
$btnVoirHistorique.Size = New-Object System.Drawing.Size(195, 28)
Rendre-BoutonPlat $btnVoirHistorique "discret"
$btnVoirHistorique.Add_Click({
    $chemin = Obtenir-CheminHistoriqueLots
    if (-not (Test-Path $chemin)) {
        Afficher-Boite "Aucun historique pour l'instant - il se remplit a chaque fichier traite (seul ou en lot)." "Historique vide" "OK" "Info" | Out-Null
        return
    }
    try {
        Start-Process $chemin
    } catch {
        Afficher-Boite "Impossible d'ouvrir automatiquement l'historique. Il se trouve ici :`r`n$chemin" "Erreur" "OK" "Error" | Out-Null
    }
})
$form.Controls.Add($btnVoirHistorique)
$yActuel += 36

# Sauvegarde/restauration groupee de toute la config (11/10/2026, Tomyn : "2-3" ; complete le
# 16/10/2026 avec couleurs-personnalisees.json et trios-favoris.json - Tomyn avait demande un
# export/import "couleurs + trios favoris", et ces deux fichiers manquaient a l'appel alors que
# la fonctionnalite de sauvegarde/restauration groupee existait deja pour tout le reste) - regroupe
# les petits fichiers crees par cet outil a cote de lui-meme (trios personnalises, couleurs
# individuelles, trios favoris, dernier trio, trios recents, historique des lots, angles de
# reference) dans un seul .zip, pratique en cas de changement de PC ou de reinstallation plutot
# que de devoir retrouver et recopier chaque fichier a la main. La liste est centralisee ici : un
# nouveau fichier de config cree plus tard dans le script n'a qu'a etre ajoute a cette liste pour
# etre couvert par la sauvegarde/restauration.
function Obtenir-FichiersConfigConnus {
    return ,@(
        @{ Nom = "trios-personnalises.json"; Chemin = (Obtenir-CheminConfigTrios) }
        @{ Nom = "couleurs-personnalisees.json"; Chemin = (Obtenir-CheminConfigCouleurs) }
        @{ Nom = "trios-favoris.json";       Chemin = (Obtenir-CheminTriosFavoris) }
        @{ Nom = "dernier-trio.json";        Chemin = (Obtenir-CheminDernierTrio) }
        @{ Nom = "trios-recents.json";       Chemin = (Obtenir-CheminTriosRecents) }
        @{ Nom = "historique-lots.log";         Chemin = (Obtenir-CheminHistoriqueLots) }
        @{ Nom = "reference-angle.json";        Chemin = (Obtenir-CheminConfigReference) }
        @{ Nom = "angles-par-fichier.json";      Chemin = (Obtenir-CheminConfigAnglesFichiers) }
    )
}

$btnSauvegarderConfig = New-Object System.Windows.Forms.Button
$btnSauvegarderConfig.Text = "Sauvegarder ma config..."
$btnSauvegarderConfig.Location = New-Object System.Drawing.Point(215, $yActuel)
$btnSauvegarderConfig.Size = New-Object System.Drawing.Size(195, 28)
Rendre-BoutonPlat $btnSauvegarderConfig "discret"
$btnSauvegarderConfig.Add_Click({
    $fichiersConnus = @(Obtenir-FichiersConfigConnus | Where-Object { Test-Path $_.Chemin })
    if ($fichiersConnus.Count -eq 0) {
        Afficher-Boite "Aucun fichier de config a sauvegarder pour l'instant (rien n'a encore ete cree - trio personnalise, historique, etc.)." "Rien a sauvegarder" "OK" "Info" | Out-Null
        return
    }
    $dialogue = New-Object System.Windows.Forms.SaveFileDialog
    $dialogue.Filter = "Archive ZIP (*.zip)|*.zip"
    $dialogue.FileName = "melange-couleurs-config_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    if ($dialogue.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("config3mf_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dossierTemp | Out-Null
    try {
        foreach ($f in $fichiersConnus) { Copy-Item -Path $f.Chemin -Destination (Join-Path $dossierTemp $f.Nom) -Force }
        if (Test-Path $dialogue.FileName) { Remove-Item -Path $dialogue.FileName -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dossierTemp, $dialogue.FileName)
        Afficher-Boite "Config sauvegardee ($($fichiersConnus.Count) fichier(s)) :`r`n$($dialogue.FileName)" "Sauvegarde terminee" "OK" "Info" | Out-Null
    } catch {
        Afficher-Boite "$_" "Erreur" "OK" "Error" | Out-Null
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
})
$form.Controls.Add($btnSauvegarderConfig)

$btnRestaurerConfig = New-Object System.Windows.Forms.Button
$btnRestaurerConfig.Text = "Restaurer ma config..."
$btnRestaurerConfig.Location = New-Object System.Drawing.Point(15, ($yActuel + 32))
$btnRestaurerConfig.Size = New-Object System.Drawing.Size(195, 28)
Rendre-BoutonPlat $btnRestaurerConfig "discret"
$btnRestaurerConfig.Add_Click({
    $dialogue = New-Object System.Windows.Forms.OpenFileDialog
    $dialogue.Filter = "Archive ZIP (*.zip)|*.zip"
    if ($dialogue.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    if ((Afficher-Boite "Ceci va REMPLACER ta config actuelle (trios personnalises, couleurs individuelles, trios favoris, dernier trio utilise, trios recents, historique, angles de reference) par celle de cette archive.`r`n`r`nContinuer ?" "Restaurer la config" "YesNo" "Warning") -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $dossierTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("config3mf_" + [guid]::NewGuid().ToString("N"))
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::ExtractToDirectory($dialogue.FileName, $dossierTemp)
        $fichiersConnus = Obtenir-FichiersConfigConnus
        $nombreRestaures = 0
        foreach ($f in $fichiersConnus) {
            $cheminExtrait = Join-Path $dossierTemp $f.Nom
            if (Test-Path $cheminExtrait) {
                Copy-Item -Path $cheminExtrait -Destination $f.Chemin -Force
                $nombreRestaures++
            }
        }
        # Les trios personnalises sont charges en memoire dans $TRIOS au demarrage - sans ce
        # rechargement explicite, la restauration ecrirait bien le nouveau fichier sur le disque
        # mais le menu deroulant continuerait d'afficher les anciens jusqu'au prochain lancement.
        foreach ($nom in @($TRIOS.Keys)) {
            if ($script:NomsTriosPredefinis -notcontains $nom) { $TRIOS.Remove($nom) }
        }
        $triosRestaures = Charger-TriosPersonnalises
        foreach ($nom in $triosRestaures.Keys) { $TRIOS[$nom] = $triosRestaures[$nom] }
        # Meme raisonnement que pour $TRIOS juste au-dessus : "mes couleurs" et les trios favoris
        # sont eux aussi charges en memoire une seule fois au demarrage (16/10/2026, ajoutes a la
        # sauvegarde/restauration groupee) - sans ce rechargement, la restauration ecrirait bien
        # les nouveaux fichiers sur le disque mais l'appli afficherait encore les anciens jusqu'au
        # prochain lancement.
        $script:MesCouleurs = @(Charger-MesCouleurs)
        $script:TriosFavoris.Clear()
        foreach ($nom in (Charger-TriosFavoris)) { [void]$script:TriosFavoris.Add($nom) }
        RafraichirListeTrios
        Afficher-Boite "Config restauree ($nombreRestaures fichier(s) trouve(s) dans l'archive)." "Restauration terminee" "OK" "Info" | Out-Null
    } catch {
        Afficher-Boite "$_" "Erreur" "OK" "Error" | Out-Null
    } finally {
        Remove-Item -Path $dossierTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
})
$form.Controls.Add($btnRestaurerConfig)
$yActuel += 64

# Barre + libelle de progression du lot - invisibles au repos, affiches seulement pendant un
# traitement en lot (voir Traiter-LotDeFichiers). Meme principe que "Stop" pour l'apercu : visible/
# actif seulement quand pertinent, pour ne pas encombrer l'ecran en usage normal fichier-unique.
$labelProgresLot = New-Object System.Windows.Forms.Label
$labelProgresLot.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelProgresLot.AutoSize = $true
$labelProgresLot.ForeColor = $THEME.Texte
$labelProgresLot.Visible = $false
$form.Controls.Add($labelProgresLot)
$yActuel += 18

$barreProgresLot = New-Object System.Windows.Forms.ProgressBar
$barreProgresLot.Location = New-Object System.Drawing.Point(15, $yActuel)
$barreProgresLot.Size = New-Object System.Drawing.Size(410, 18)
$barreProgresLot.Minimum = 0
$barreProgresLot.Visible = $false
$form.Controls.Add($barreProgresLot)
$yActuel += 28

$labelJournal = New-Object System.Windows.Forms.Label
$labelJournal.Text = "Avancement :"
$labelJournal.Location = New-Object System.Drawing.Point(15, $yActuel)
$labelJournal.AutoSize = $true
$labelJournal.ForeColor = $THEME.Texte
$form.Controls.Add($labelJournal)
$yActuel += 20

# RichTextBox plutot qu'un simple TextBox (11/10/2026, Tomyn : "1-2-3-4") - meme usage partout
# ailleurs (AppendText, SelectionStart, ScrollToCaret, Clear, Text, MaxLength existent tous les
# deux de la meme facon), mais permet en plus de colorer un morceau de texte precis : utilise par
# Ecrire-Journal ci-dessous pour afficher une petite pastille avec la VRAIE couleur resultante de
# chaque melange, pas juste son code hex en texte brut.
$txtJournal = New-Object System.Windows.Forms.RichTextBox
$txtJournal.Location = New-Object System.Drawing.Point(15, $yActuel)
$txtJournal.Size = New-Object System.Drawing.Size(430, 300)
$txtJournal.Anchor = "Top, Bottom, Left"
$txtJournal.ScrollBars = "Vertical"
$txtJournal.ReadOnly = $true
$txtJournal.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtJournal.BackColor = $THEME.Surface
$txtJournal.ForeColor = $THEME.Texte
# Meme correctif que Coloriser-STL-GUI (10/10/2026) : un TextBox/RichTextBox a par defaut une
# limite cachee de 32767 caracteres (MaxLength) - au-dela, AppendText() n'ajoute plus rien,
# silencieusement. Leve ici des le depart pour ne pas retomber dans le meme piege.
$txtJournal.MaxLength = 0
$form.Controls.Add($txtJournal)

# $hexCouleur optionnel (11/10/2026, Tomyn : "1-2-3-4") - quand fourni, insere une petite pastille
# coloree ("(symbole carre) ") AVANT le texte, dans la couleur demandee. Important : avec un
# RichTextBox, AppendText() ne respecte PAS SelectionColor si on la pose AVANT d'ajouter le texte
# (piege connu .NET) - il faut ajouter le texte D'ABORD, puis SELECTIONNER ce qu'on vient d'ajouter
# pour lui appliquer la couleur, puis deselectionner et remettre la couleur par defaut pour la
# suite. Si le code hex est invalide, le texte s'affiche quand meme, juste sans pastille.
function Ecrire-Journal([string]$texte, [string]$hexCouleur = "") {
    if (-not [string]::IsNullOrWhiteSpace($hexCouleur)) {
        try {
            $couleurPastille = [System.Drawing.ColorTranslator]::FromHtml($hexCouleur)
            $debutPastille = $txtJournal.TextLength
            $txtJournal.AppendText([char]0x25A0 + " ")
            $txtJournal.Select($debutPastille, 2)
            $txtJournal.SelectionColor = $couleurPastille
            $txtJournal.Select($txtJournal.TextLength, 0)
            $txtJournal.SelectionColor = $THEME.Texte
        } catch { }
    }
    $txtJournal.AppendText("$texte`r`n")
    $txtJournal.SelectionStart = $txtJournal.TextLength
    $txtJournal.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# ---- Apercu avant / apres (10/10/2026, demande par Tomyn) ----
# A droite du journal : un rendu statique (pas un vrai 3D interactif, juste une image - voir
# Nouvelle-ImageApercu plus haut) du maillage avec les couleurs detectees ("avant", des que le
# fichier est choisi), puis avec les couleurs du dosage calcule ("apres", une fois le melange
# termine). But : voir d'un coup d'oeil si ca a du sens sans avoir a ouvrir Bambu Studio.
$xApercu = 465
$largeurApercu = 300
$hauteurApercu = 260

# Memorise, pour chaque apercu ("avant"/"apres"), les triangles deja lus et l'angle actuellement
# affiche - sert a Redessiner-Apercu-AvecRotation (boutons de rotation manuelle) pour pouvoir
# re-dessiner juste avec un nouvel angle SANS relire tout le fichier .3mf a chaque clic. Initialise
# ICI (et non juste avant Mettre-A-Jour-Apercu plus bas) car Ajouter-BoutonsRotationApercu, appelee
# des la construction de la fenetre juste en dessous, a besoin qu'elle existe deja.
#
# Correctif du 10/10/2026 (Tomyn : erreur "Indexation impossible dans un tableau Null" persistante,
# diagnostiquee grace au message d'erreur detaille qu'il a bien voulu renvoyer - merci) : A L'INTERIEUR
# d'un scriptblock passe par .GetNewClosure() (les gestionnaires Add_Tick/Add_Click plus bas),
# `$script:ApercuEtat` ne pointe PLUS vers cette variable mais vers $null - confirme par un test
# isole ici. La regle qui en decoule PARTOUT dans ce fichier : jamais de `$script:` a l'interieur
# d'un scriptblock ferme par GetNewClosure() - toujours capturer une variable LOCALE (sans prefixe
# de portee) juste avant, qui reference le MEME objet (une reference .NET, pas une copie), et s'en
# servir a l'interieur de la closure.
$script:ApercuEtat = @{}

# Persistance de l'angle de reference entre deux lancements de l'outil (10/10/2026, Tomyn : "go les
# amelio") - avant ce correctif, la reference memorisee via la case a cocher du selecteur de
# vignettes ne vivait qu'en memoire et se perdait a chaque fermeture de l'appli. Enregistree dans un
# petit fichier JSON a cote du script lui-meme (pas dans le dossier du .3mf, qui peut changer a
# chaque import).
function Obtenir-CheminConfigReference {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "reference-angle.json" } else { Join-Path (Get-Location) "reference-angle.json" }
}

function Charger-ReferenceGlobale {
    $chemin = Obtenir-CheminConfigReference
    if (-not (Test-Path $chemin)) { return $null }
    try {
        $contenu = Get-Content -Path $chemin -Raw -ErrorAction Stop
        $objet = $contenu | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $objet.AngleY -and $null -ne $objet.AngleX) {
            return [PSCustomObject]@{ AngleY = [double]$objet.AngleY; AngleX = [double]$objet.AngleX }
        }
    } catch { }
    return $null
}

function Sauvegarder-ReferenceGlobale($reference) {
    $chemin = Obtenir-CheminConfigReference
    try {
        if ($null -eq $reference) {
            if (Test-Path $chemin) { Remove-Item -Path $chemin -Force -ErrorAction Stop }
        } else {
            ($reference | ConvertTo-Json) | Set-Content -Path $chemin -Encoding UTF8 -ErrorAction Stop
        }
    } catch {
        # Jamais bloquant : si l'ecriture disque echoue (dossier en lecture seule, etc.), la
        # reference continue de fonctionner pour la session en cours, juste pas au prochain lancement.
        Ecrire-Journal "(Impossible d'enregistrer la reference d'angle sur le disque : $_)"
    }
}

# Au demarrage : recharge une reference deja enregistree lors d'un lancement precedent, si elle existe.
$referenceGlobaleChargee = Charger-ReferenceGlobale
if ($referenceGlobaleChargee) { $script:ApercuEtat['__ReferenceGlobale__'] = $referenceGlobaleChargee }

# Memorise l'angle par FICHIER (10/10/2026, Tomyn : "go les amelio") - complement a la reference
# GLOBALE ci-dessus (qui s'applique a tous les imports) : ici, un fichier .3mf donne (meme chemin)
# retrouve directement le DERNIER angle choisi dessus la prochaine fois qu'il est rouvert, sans
# repasser par la recherche automatique complete. Stocke dans un second fichier JSON (une table
# chemin -> angle), a part de la reference globale, pour ne pas les mélanger.
function Obtenir-CheminConfigAnglesFichiers {
    if ($PSScriptRoot) { Join-Path $PSScriptRoot "angles-par-fichier.json" } else { Join-Path (Get-Location) "angles-par-fichier.json" }
}

function Charger-AnglesParFichier {
    $chemin = Obtenir-CheminConfigAnglesFichiers
    if (-not (Test-Path $chemin)) { return @{} }
    try {
        $contenu = Get-Content -Path $chemin -Raw -ErrorAction Stop
        $objet = $contenu | ConvertFrom-Json -ErrorAction Stop
        $table = @{}
        foreach ($prop in $objet.PSObject.Properties) {
            $table[$prop.Name] = [PSCustomObject]@{ AngleY = [double]$prop.Value.AngleY; AngleX = [double]$prop.Value.AngleX }
        }
        return $table
    } catch { return @{} }
}

function Obtenir-CheminAbsolu3MF([string]$chemin3mf) {
    try { return (Resolve-Path -LiteralPath $chemin3mf -ErrorAction Stop).Path } catch { return $chemin3mf }
}

function Obtenir-AngleFichier([string]$chemin3mf) {
    $table = Charger-AnglesParFichier
    $cleChemin = Obtenir-CheminAbsolu3MF $chemin3mf
    if ($table.ContainsKey($cleChemin)) { return $table[$cleChemin] }
    return $null
}

function Enregistrer-AngleFichier([string]$chemin3mf, [double]$angleY, [double]$angleX) {
    $table = Charger-AnglesParFichier
    $cleChemin = Obtenir-CheminAbsolu3MF $chemin3mf
    $table[$cleChemin] = [PSCustomObject]@{ AngleY = $angleY; AngleX = $angleX }
    try {
        ($table | ConvertTo-Json) | Set-Content -Path (Obtenir-CheminConfigAnglesFichiers) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Ecrire-Journal "(Impossible d'enregistrer l'angle de ce fichier sur le disque : $_)"
    }
}

# Export PNG de l'apercu (10/10/2026, Tomyn : "go les amelio") - clic droit sur l'image plutot
# qu'un bouton de plus dans des rangees deja chargees. Fonction a part (pas imbriquee) : un seul
# niveau de closure (Add_Click directement ici, pas de fonction/closure intermediaire), donc
# $pictureBox/$cle passes en parametre suffisent, pas besoin de la recapture locale habituelle.
function Ajouter-MenuContextuelApercu([System.Windows.Forms.PictureBox]$pictureBox, [string]$cle) {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $itemExporter = New-Object System.Windows.Forms.ToolStripMenuItem
    $itemExporter.Text = "Exporter l'apercu en PNG..."
    $itemExporter.Add_Click({
        if (-not $pictureBox.Image) {
            Ecrire-Journal "Rien a exporter (case '$cle') : aucun apercu affiche."
            return
        }
        $dialogue = New-Object System.Windows.Forms.SaveFileDialog
        $dialogue.Filter = "Image PNG (*.png)|*.png"
        $dialogue.FileName = "apercu_$cle.png"
        if ($dialogue.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                # Cloner avant Save() (10/10/2026) - PictureBox.Image peut etre remplace par un
                # redessin en arriere-plan PENDANT que ce dialogue est ouvert ; sauvegarder une
                # copie plutot que l'objet encore attache evite d'ecrire une image a moitie
                # remplacee/disposee si cette situation precise se produit.
                $copie = $pictureBox.Image.Clone()
                try {
                    $copie.Save($dialogue.FileName, [System.Drawing.Imaging.ImageFormat]::Png)
                } finally {
                    $copie.Dispose()
                }
                Ecrire-Journal "Apercu exporte : $($dialogue.FileName)"
            } catch {
                Ecrire-Journal "(Export de l'apercu impossible : $_)"
            }
        }
    }.GetNewClosure())
    [void]$menu.Items.Add($itemExporter)
    $pictureBox.ContextMenuStrip = $menu
}

# Raccourcis clavier (10/10/2026, Tomyn : "toutes stp") - cliquer sur un apercu lui donne le focus
# (TabStop active ci-dessous), puis les fleches gauche/droite tournent (meme pas que les boutons
# "<"/">", 15 deg) et haut/bas inclinent (meme pas que "^"/"v", 10 deg). Un racourci en plus des
# boutons, pas un remplacement - les boutons restent utiles pour les gros pas ("<<"/">>"/"^^"/"vv")
# ou pour qui prefere la souris. Pas d'indicateur visuel de focus sur la case (PictureBox n'affiche
# pas de rectangle de focus par defaut) - il faut cliquer dessus avant d'utiliser les fleches.
function Ajouter-RaccourcisClavierApercu([System.Windows.Forms.PictureBox]$pictureBox, [string]$cle) {
    $pictureBox.TabStop = $true
    $pictureBox.Add_KeyDown({
        param($sender, $e)
        $gere = $true
        switch ($e.KeyCode) {
            "Left"  { Redessiner-Apercu-AvecRotation $pictureBox $cle -15.0 0.0 }
            "Right" { Redessiner-Apercu-AvecRotation $pictureBox $cle 15.0 0.0 }
            "Up"    { Redessiner-Apercu-AvecRotation $pictureBox $cle 0.0 10.0 }
            "Down"  { Redessiner-Apercu-AvecRotation $pictureBox $cle 0.0 -10.0 }
            default { $gere = $false }
        }
        if ($gere) { $e.Handled = $true; $e.SuppressKeyPress = $true }
    }.GetNewClosure())
}

# Zoom au double-clic (10/10/2026, Tomyn : "toutes stp") - double-clic sur un apercu pour l'ouvrir
# en grand dans une fenetre separee, redimensionnable. Double-clic plutot que simple clic : le
# simple clic est deja pris par Ajouter-RaccourcisClavierApercu ci-dessus pour donner le focus a la
# case (necessaire pour les fleches) - un double-clic reste un geste naturel pour "agrandir" sans
# rien enlever au clic simple.
function Ajouter-ZoomApercu([System.Windows.Forms.PictureBox]$pictureBox, [string]$cle) {
    $pictureBox.Add_DoubleClick({
        if (-not $pictureBox.Image) {
            Ecrire-Journal "Rien a agrandir (case '$cle') : aucun apercu affiche."
            return
        }
        $popup = New-Object System.Windows.Forms.Form
        $popup.Text = "Apercu agrandi - $cle"
        $popup.StartPosition = "CenterParent"
        $popup.FormBorderStyle = "Sizable"
        $popup.ClientSize = New-Object System.Drawing.Size(900, 700)
        $popup.BackColor = $THEME.Surface
        $popup.KeyPreview = $true

        $grandPicture = New-Object System.Windows.Forms.PictureBox
        $grandPicture.Dock = "Fill"
        $grandPicture.SizeMode = "Zoom"
        $grandPicture.BackColor = $THEME.Surface
        # Cloner (meme precaution que l'export PNG plus haut) - evite d'afficher une image qui
        # pourrait etre remplacee/disposee par un redessin en arriere-plan pendant que cette fenetre
        # de zoom reste ouverte.
        $grandPicture.Image = $pictureBox.Image.Clone()
        $popup.Controls.Add($grandPicture)

        # Pas de recapture necessaire ici : $popup/$grandPicture sont definis dans le CORPS de ce
        # closure (pas des parametres de la fonction englobante), donc visibles sans probleme par
        # les closures imbriquees ci-dessous (voir la note sur le piege des closures imbriquees dans
        # Afficher-SelecteurVignettes, plus bas, pour le cas ou ca NE marche PAS).
        $popup.Add_FormClosed({ try { $grandPicture.Image.Dispose() } catch { } }.GetNewClosure())
        $popup.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq "Escape") { $popup.Close() } }.GetNewClosure())

        [void]$popup.ShowDialog($form)
    }.GetNewClosure())
}

# Petite rangee de boutons sous un apercu : tourner (gauche/droite), pencher (haut/bas), et revenir
# a l'angle choisi automatiquement (10/10/2026, cf. Redessiner-Apercu-AvecRotation plus bas - les
# fonctions appelees par ces boutons ne doivent exister qu'au moment du CLIC, pas au moment ou ce
# bouton est cree, donc leur definition peut rester plus bas dans le script).
function Ajouter-BoutonsRotationApercu([System.Windows.Forms.Form]$formulaire, [System.Windows.Forms.PictureBox]$pictureBox, [string]$cle, [int]$x, [int]$y, [int]$largeur, [int]$hauteur) {
    # Reference LOCALE (voir la note sur $script:ApercuEtat plus haut) - indispensable ici, ces
    # boutons sont geres par des closures GetNewClosure().
    $etatPartage = $script:ApercuEtat
    # Pas large + pas fin, pour la ROTATION (10/10/2026, Tomyn : a 15 deg par clic, faire tout le
    # tour pour trouver le bon angle "j'en ai pour une demi-heure") ET pour l'INCLINAISON (meme
    # remarque de Tomyn appliquee a "^"/"v" juste apres) - "<<"/">>"/"^^"/"vv" avancent de 45/30 deg
    # pour explorer vite, "<"/">"/"^"/"v" de 15/10 deg pour affiner une fois proche. Deux rangees
    # (rotation, puis inclinaison+Auto) : 7 boutons sur 300px de large commencaient a etre vraiment
    # serres une fois les gros pas d'inclinaison ajoutes.
    $rangeeRotation = @(
        @{ Texte = "<<"; DeltaY = -45.0; DeltaX = 0.0 },
        @{ Texte = "<"; DeltaY = -15.0; DeltaX = 0.0 },
        @{ Texte = ">"; DeltaY = 15.0; DeltaX = 0.0 },
        @{ Texte = ">>"; DeltaY = 45.0; DeltaX = 0.0 }
    )
    $rangeeInclinaison = @(
        @{ Texte = "vv"; DeltaY = 0.0; DeltaX = -30.0 },
        @{ Texte = "v"; DeltaY = 0.0; DeltaX = -10.0 },
        @{ Texte = "^"; DeltaY = 0.0; DeltaX = 10.0 },
        @{ Texte = "^^"; DeltaY = 0.0; DeltaX = 30.0 },
        @{ Texte = "Auto"; DeltaY = $null; DeltaX = $null }
    )
    # Troisieme rangee (10/10/2026, Tomyn : bleu trop uniforme pour juger un angle a l'oeil, et
    # "Auto" qui retombe toujours sur le meme angle) - ouvre une planche de plusieurs vignettes
    # d'un coup au lieu de tatonner clic par clic, voir Afficher-SelecteurVignettes plus bas.
    # "Stop" (10/10/2026, Tomyn : "go les amelio") : desactive au repos, actif seulement pendant un
    # calcul en cours (Mettre-A-Jour-Apercu/Redessiner-Apercu-AvecRotation/Afficher-SelecteurVignettes
    # l'activent et le desactivent eux-memes). "Defaire" : un seul cran d'historique, voir la note
    # sur AngleYPrecedent/AngleXPrecedent dans Redessiner-Apercu-AvecRotation.
    $rangeeOutils = @(
        @{ Texte = "Vignettes..."; DeltaY = $null; DeltaX = $null },
        @{ Texte = "Stop"; DeltaY = $null; DeltaX = $null },
        @{ Texte = "Defaire"; DeltaY = $null; DeltaX = $null }
    )

    # Fonction IMBRIQUEE (10/10/2026) : attention, un piege PowerShell deja rencontre plus tot dans
    # ce projet (voir model_settings.config/evaluateurExtrudeur) - un scriptblock ferme par
    # GetNewClosure() A L'INTERIEUR d'une fonction imbriquee ne capture PAS les parametres de la
    # fonction EXTERIEURE (confirme par un test isole : seul le parametre de la fonction imbriquee
    # elle-meme passe). D'ou TOUT ce dont les boutons ont besoin ($formulaire, $pictureBox, $cle,
    # $etatPartage, $x, $largeur, $hauteur) est passe ICI en parametre EXPLICITE de
    # Ajouter-UneRangeeBoutons, plutot que lu depuis la fonction parente.
    function Ajouter-UneRangeeBoutons($boutons, [int]$yRangee, [System.Windows.Forms.Form]$formulaire, [System.Windows.Forms.PictureBox]$pictureBox, [string]$cle, $etatPartage, [int]$x, [int]$largeur, [int]$hauteur) {
        $largeurBouton = [Math]::Floor(($largeur - 4 * ($boutons.Count - 1)) / $boutons.Count)
        $xActuel = $x
        foreach ($b in $boutons) {
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $b.Texte
            $btn.Location = New-Object System.Drawing.Point($xActuel, $yRangee)
            $btn.Size = New-Object System.Drawing.Size($largeurBouton, $hauteur)
            $btn.Font = New-Object System.Drawing.Font($btn.Font.FontFamily, 8)
            $btn.Anchor = "Top, Right"
            if ($b.Texte -eq "Auto") {
                $btn.Add_Click({
                    $etat = $etatPartage[$cle]
                    if (-not $etat -or -not $etat.Chemin) { return }
                    # Reference memorisee (10/10/2026, Tomyn : "Auto" doit reappliquer l'angle de
                    # reference quand il y en a un, au lieu de toujours relancer la recherche
                    # complete) - rangee sous une cle speciale dans LE MEME hashtable partage que
                    # les etats "avant"/"apres", donc visible depuis les deux cases et toujours a
                    # jour meme si la fenetre vignettes l'a changee APRES la creation de ce bouton
                    # (lue ICI, a chaque clic - pas capturee une fois pour toutes par la closure).
                    $reference = $etatPartage['__ReferenceGlobale__']
                    if ($reference -and $etat.Triangles) {
                        $deltaY = $reference.AngleY - $etat.AngleY
                        $deltaX = $reference.AngleX - $etat.AngleX
                        Redessiner-Apercu-AvecRotation $pictureBox $cle $deltaY $deltaX
                    } else {
                        Mettre-A-Jour-Apercu $pictureBox $cle $etat.Chemin
                    }
                }.GetNewClosure())
            } elseif ($b.Texte -eq "Vignettes...") {
                $btn.Add_Click({
                    Afficher-SelecteurVignettes $pictureBox $cle $etatPartage
                }.GetNewClosure())
            } elseif ($b.Texte -eq "Stop") {
                # Desactive au repos - rien a arreter. Active par les trois fonctions qui lancent un
                # calcul en arriere-plan (elles le desactivent elles-memes a la fin, succes ou echec).
                $btn.Enabled = $false
                $etatPartage["__BoutonStop_$cle__"] = $btn
                $btn.Add_Click({
                    # Perime le resultat a venir (le Timer qui le recupere verra $estPerime = vrai et
                    # n'affichera rien) AVANT de demander l'arret - sinon un resultat qui arrive juste
                    # entre les deux lignes pourrait encore s'afficher.
                    $pictureBox.Tag = ([int]$pictureBox.Tag) + 1
                    $psActif = $etatPartage["__PSActif_$cle__"]
                    if ($psActif) {
                        try { [void]$psActif.BeginStop($null, $null) } catch { }
                    }
                    $pictureBox.Cursor = [System.Windows.Forms.Cursors]::Default
                    Ecrire-Journal "Calcul annule par l'utilisateur (case '$cle')."
                }.GetNewClosure())
            } elseif ($b.Texte -eq "Defaire") {
                $btn.Add_Click({
                    $etat = $etatPartage[$cle]
                    if (-not $etat -or -not $etat.Triangles) {
                        Ecrire-Journal "Rien a defaire (case '$cle') : aucun apercu charge en memoire."
                        return
                    }
                    $deltaY = $etat.AngleYPrecedent - $etat.AngleY
                    $deltaX = $etat.AngleXPrecedent - $etat.AngleX
                    if ([Math]::Abs($deltaY) -lt 0.01 -and [Math]::Abs($deltaX) -lt 0.01) {
                        Ecrire-Journal "Rien a defaire (case '$cle') : pas de changement d'angle recent."
                        return
                    }
                    Redessiner-Apercu-AvecRotation $pictureBox $cle $deltaY $deltaX
                }.GetNewClosure())
            } else {
                $dY = $b.DeltaY; $dX = $b.DeltaX
                $btn.Add_Click({
                    Redessiner-Apercu-AvecRotation $pictureBox $cle $dY $dX
                }.GetNewClosure())
            }
            $formulaire.Controls.Add($btn)
            $xActuel += $largeurBouton + 4
        }
    }

    Ajouter-UneRangeeBoutons $rangeeRotation $y $formulaire $pictureBox $cle $etatPartage $x $largeur $hauteur
    Ajouter-UneRangeeBoutons $rangeeInclinaison ($y + $hauteur + 3) $formulaire $pictureBox $cle $etatPartage $x $largeur $hauteur
    Ajouter-UneRangeeBoutons $rangeeOutils ($y + 2 * ($hauteur + 3)) $formulaire $pictureBox $cle $etatPartage $x $largeur $hauteur
}

$labelApercuAvant = New-Object System.Windows.Forms.Label
$labelApercuAvant.Text = "Apercu - couleurs detectees :"
$labelApercuAvant.Location = New-Object System.Drawing.Point($xApercu, ($THEME.HauteurBanniere + 18))
$labelApercuAvant.AutoSize = $true
$labelApercuAvant.ForeColor = $THEME.Texte
$labelApercuAvant.Anchor = "Top, Right"
$form.Controls.Add($labelApercuAvant)

$yPictureAvant = $THEME.HauteurBanniere + 38
$pictureAvant = New-Object System.Windows.Forms.PictureBox
$pictureAvant.Location = New-Object System.Drawing.Point($xApercu, $yPictureAvant)
$pictureAvant.Size = New-Object System.Drawing.Size($largeurApercu, $hauteurApercu)
$pictureAvant.BackColor = $THEME.Surface
$pictureAvant.SizeMode = "Zoom"
$pictureAvant.BorderStyle = "FixedSingle"
$pictureAvant.Anchor = "Top, Right"
$form.Controls.Add($pictureAvant)
Ajouter-MenuContextuelApercu $pictureAvant "avant"
Ajouter-RaccourcisClavierApercu $pictureAvant "avant"
Ajouter-ZoomApercu $pictureAvant "avant"

# Affiche l'angle actuellement applique (10/10/2026, Tomyn : "go les amelio") - evite d'avoir a
# remonter dans le journal pour savoir ou on en est. Mis a jour par Mettre-A-Jour-Apercu et
# Redessiner-Apercu-AvecRotation, qui retrouvent ce controle via $script:ApercuEtat["__Label_<cle>__"]
# (meme logique que la reference d'angle globale : range dans le hashtable partage plutot que
# passe en parametre explicite partout, pour ne pas toucher a la signature de fonctions deja
# nombreuses a appeler).
$hauteurLabelAngle = 16
$labelAngleAvant = New-Object System.Windows.Forms.Label
$labelAngleAvant.Text = "Rotation : --  /  Inclinaison : --"
$labelAngleAvant.Location = New-Object System.Drawing.Point($xApercu, ($yPictureAvant + $hauteurApercu + 4))
$labelAngleAvant.Size = New-Object System.Drawing.Size($largeurApercu, $hauteurLabelAngle)
$labelAngleAvant.ForeColor = $THEME.TexteSecondaire
$labelAngleAvant.Font = New-Object System.Drawing.Font($labelAngleAvant.Font.FontFamily, 8)
$labelAngleAvant.Anchor = "Top, Right"
$form.Controls.Add($labelAngleAvant)
$script:ApercuEtat["__Label_avant__"] = $labelAngleAvant

# Boutons de rotation manuelle (10/10/2026, Tomyn : "ANGLE TOUJOURS PAS BON" - l'angle choisi
# automatiquement reste parfois faux, une heuristique geometrique ne peut pas toujours deviner quel
# cote du modele est "la face". Ces boutons laissent Tomyn corriger lui-meme, sans tout relire.
$hauteurBoutonsRotation = 26
# Trois rangees de boutons desormais (rotation, inclinaison+Auto, puis Vignettes) - l'espace
# reserve doit donc compter 3x la hauteur d'une rangee + les deux petits interstices entre elles
# (3px chacun, voir Ajouter-BoutonsRotationApercu).
$hauteurBlocBoutons = 3 * $hauteurBoutonsRotation + 2 * 3
$yBoutonsAvant = $yPictureAvant + $hauteurApercu + 4 + $hauteurLabelAngle + 4
Ajouter-BoutonsRotationApercu $form $pictureAvant "avant" $xApercu $yBoutonsAvant $largeurApercu $hauteurBoutonsRotation

$yLabelApres = $yBoutonsAvant + $hauteurBlocBoutons + 14
$labelApercuApres = New-Object System.Windows.Forms.Label
$labelApercuApres.Text = "Apercu - apres melange :"
$labelApercuApres.Location = New-Object System.Drawing.Point($xApercu, $yLabelApres)
$labelApercuApres.AutoSize = $true
$labelApercuApres.ForeColor = $THEME.Texte
$labelApercuApres.Anchor = "Top, Right"
$form.Controls.Add($labelApercuApres)

$yPictureApres = $yLabelApres + 20
$pictureApres = New-Object System.Windows.Forms.PictureBox
$pictureApres.Location = New-Object System.Drawing.Point($xApercu, $yPictureApres)
$pictureApres.Size = New-Object System.Drawing.Size($largeurApercu, $hauteurApercu)
$pictureApres.BackColor = $THEME.Surface
$pictureApres.SizeMode = "Zoom"
$pictureApres.BorderStyle = "FixedSingle"
$pictureApres.Anchor = "Top, Right"
$form.Controls.Add($pictureApres)
Ajouter-MenuContextuelApercu $pictureApres "apres"
Ajouter-RaccourcisClavierApercu $pictureApres "apres"
Ajouter-ZoomApercu $pictureApres "apres"

$labelAngleApres = New-Object System.Windows.Forms.Label
$labelAngleApres.Text = "Rotation : --  /  Inclinaison : --"
$labelAngleApres.Location = New-Object System.Drawing.Point($xApercu, ($yPictureApres + $hauteurApercu + 4))
$labelAngleApres.Size = New-Object System.Drawing.Size($largeurApercu, $hauteurLabelAngle)
$labelAngleApres.ForeColor = $THEME.TexteSecondaire
$labelAngleApres.Font = New-Object System.Drawing.Font($labelAngleApres.Font.FontFamily, 8)
$labelAngleApres.Anchor = "Top, Right"
$form.Controls.Add($labelAngleApres)
$script:ApercuEtat["__Label_apres__"] = $labelAngleApres

$yBoutonsApres = $yPictureApres + $hauteurApercu + 4 + $hauteurLabelAngle + 4
Ajouter-BoutonsRotationApercu $form $pictureApres "apres" $xApercu $yBoutonsApres $largeurApercu $hauteurBoutonsRotation

# Correctif du 10/10/2026 - Tomyn a signale "l'appli ne repond pas" avec la version precedente de
# l'apercu : tout le calcul (lecture du maillage + rendu de l'image) se faisait directement sur le
# thread de la fenetre, qui ne pouvait donc plus traiter ses messages (redessiner, bouger, etc.)
# pendant tout ce temps - sur un gros fichier, bien assez longtemps pour que Windows affiche "ne
# repond pas", meme si le calcul finissait par se terminer tout seul. Desormais, le calcul tourne
# dans un Runspace separe (un second "interpreteur PowerShell", sur un autre thread) via
# PowerShell.BeginInvoke(), et un Timer WinForms (qui, lui, tourne sur le thread de la fenetre
# sans la bloquer) verifie regulierement si c'est termine pour recuperer le resultat. La fenetre
# reste utilisable pendant tout le calcul.
#
# Un Runspace flambant neuf ne connait aucune des fonctions deja chargees dans celui-ci : on lui
# donne donc leur code source (recupere via ${function:...}.ToString(), qui inclut la liste de
# parametres) pour qu'il les redefinisse lui-meme avant de s'en servir.
# Construit un message de diagnostic aussi complet que possible pour une erreur survenue DANS le
# Runspace d'arriere-plan (10/10/2026, Tomyn : toujours la meme erreur generique "Indexation
# impossible dans un tableau Null" sans aucun detail exploitable). PowerShell.EndInvoke() propage
# directement l'exception d'origine quand le script embarque plante (pas seulement une erreur non
# bloquante dans $ps.Streams.Error) - dans ce cas le "throw" avec PositionMessage ecrit plus bas
# dans Mettre-A-Jour-Apercu/Redessiner-Apercu-AvecRotation n'est jamais atteint, d'ou le message
# reste generique. Cette fonction essaie plusieurs chemins (ErrorRecord imbrique dans l'exception,
# InvocationInfo direct, puis en dernier recours $ps.Streams.Error s'il contient malgre tout
# quelque chose) pour remonter la ligne exacte qui a plante a l'interieur du Runspace.
function Obtenir-DetailErreurApercu($enregistrementErreur, $psInstance) {
    $morceaux = @("$enregistrementErreur")
    try {
        if ($enregistrementErreur.Exception.ErrorRecord -and $enregistrementErreur.Exception.ErrorRecord.InvocationInfo) {
            $morceaux += $enregistrementErreur.Exception.ErrorRecord.InvocationInfo.PositionMessage
        } elseif ($enregistrementErreur.InvocationInfo) {
            $morceaux += $enregistrementErreur.InvocationInfo.PositionMessage
        }
    } catch { }
    try {
        if ($psInstance -and $psInstance.Streams.Error.Count -gt 0) {
            $morceaux += ("[flux] " + $psInstance.Streams.Error[0].InvocationInfo.PositionMessage)
        }
    } catch { }
    return ($morceaux -join " || ")
}

function Mettre-A-Jour-Apercu([System.Windows.Forms.PictureBox]$pictureBox, [string]$cle, [string]$chemin3mf) {
    $pictureBox.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

    # Feedback immediat (10/10/2026, Tomyn : "le bouton Auto ne donne rien meme pas dans
    # Avancement") : lecture + recherche d'angle + dessin prend facilement 30s sur un gros fichier,
    # et jusqu'ici RIEN ne s'affichait avant la toute fin - de quoi croire que le clic n'a servi a
    # rien alors que ca tourne juste en fond. Desormais, meme chose que Redessiner-Apercu-AvecRotation.
    Ecrire-Journal "Chargement de l'apercu (case '$cle')..."

    # Reference LOCALE (voir la note sur $script:ApercuEtat plus haut) - indispensable, le Timer
    # Add_Tick plus bas est une closure GetNewClosure().
    $etatPartage = $script:ApercuEtat

    # Jeton de "fraicheur" : si on relance un apercu sur la meme case avant que le precedent soit
    # fini (fichier choisi deux fois rapidement, par ex.), le resultat tardif du premier calcul ne
    # doit pas ecraser le second - on compare ce jeton a celui en cours au moment ou le calcul se
    # termine.
    $generation = ([int]$pictureBox.Tag) + 1
    $pictureBox.Tag = $generation

    # Angle deja connu pour CE fichier (10/10/2026, Tomyn : "go les amelio") - evite de refaire la
    # recherche complete si ce .3mf (meme chemin) a deja ete ouvert ici avant. Different de la
    # reference GLOBALE : celle-ci est specifique au fichier, prioritaire sur elle.
    $angleFichierConnu = Obtenir-AngleFichier $chemin3mf
    if ($angleFichierConnu) {
        Ecrire-Journal ("Angle deja connu pour ce fichier : recherche automatique sautee (rotation {0:N0} deg, inclinaison {1:N0} deg)." -f $angleFichierConnu.AngleY, $angleFichierConnu.AngleX)
    }

    $corpsFonctions = @(
        "function Decoder-EtatPaintColor { " + (${function:Decoder-EtatPaintColor}.ToString()) + " }",
        "function Lire-TrianglesPourApercu { " + (${function:Lire-TrianglesPourApercu}.ToString()) + " }",
        "function Choisir-MeilleurAngleVue { " + (${function:Choisir-MeilleurAngleVue}.ToString()) + " }",
        "function Nouvelle-ImageApercu { " + (${function:Nouvelle-ImageApercu}.ToString()) + " }"
    ) -join "`r`n"

    # Chronometrage (10/10/2026, Tomyn signale un chargement "ultra long") : separe le temps de
    # LECTURE du fichier (parcours du maillage, jamais chronometre sur une vraie machine Windows)
    # du temps de DESSIN (GDI+, jamais non plus chronometrable ici, System.Drawing n'existe pas
    # sous Linux) - le journal affichera les deux une fois l'apercu pret, pour savoir lequel des
    # deux est reellement le goulot chez Tomyn plutot que de deviner.
    # `$args[3]`/`$args[4]` : angle deja connu pour ce fichier (ou `$null`/`$null` si aucun) - evite
    # de rappeler Choisir-MeilleurAngleVue (le plus lent des trois temps mesures) quand on le connait deja.
    $script = @"
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$corpsFonctions
`$chrono1 = [System.Diagnostics.Stopwatch]::StartNew()
`$triangles = Lire-TrianglesPourApercu `$args[0]
`$chrono1.Stop()
`$chronoAngle = [System.Diagnostics.Stopwatch]::StartNew()
if (`$null -ne `$args[3] -and `$null -ne `$args[4]) {
    `$meilleurAngle = [PSCustomObject]@{ AngleY = [double]`$args[3]; AngleX = [double]`$args[4] }
} else {
    `$meilleurAngle = Choisir-MeilleurAngleVue `$triangles
}
`$chronoAngle.Stop()
`$chrono2 = [System.Diagnostics.Stopwatch]::StartNew()
`$resultatImage = Nouvelle-ImageApercu `$triangles ([int]`$args[1]) ([int]`$args[2]) `$meilleurAngle.AngleY `$meilleurAngle.AngleX
`$chrono2.Stop()
[PSCustomObject]@{ Image = `$resultatImage.Bitmap; DureeLecture = `$chrono1.Elapsed.TotalSeconds; DureeAngle = `$chronoAngle.Elapsed.TotalSeconds; DureeDessin = `$chrono2.Elapsed.TotalSeconds; NombreTriangles = `$triangles.Count; NombreDessines = `$resultatImage.NombreDessines; NombreGroupes = `$resultatImage.NombreGroupes; AngleYChoisi = `$meilleurAngle.AngleY; AngleXChoisi = `$meilleurAngle.AngleX; Triangles = `$triangles }
"@

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($script)
    [void]$ps.AddArgument($chemin3mf)
    [void]$ps.AddArgument($largeurApercu)
    [void]$ps.AddArgument($hauteurApercu)
    if ($angleFichierConnu) {
        [void]$ps.AddArgument($angleFichierConnu.AngleY)
        [void]$ps.AddArgument($angleFichierConnu.AngleX)
    } else {
        [void]$ps.AddArgument($null)
        [void]$ps.AddArgument($null)
    }

    # Pour le bouton "Stop" (10/10/2026, Tomyn : "go les amelio") - range l'instance PowerShell
    # en cours dans le hashtable partage pour que le clic sur "Stop" puisse l'arreter (BeginStop),
    # et active ce bouton pendant le calcul (desactive dans le "finally" plus bas).
    $etatPartage["__PSActif_$cle__"] = $ps
    $boutonStop = $etatPartage["__BoutonStop_$cle__"]
    if ($boutonStop) { $boutonStop.Enabled = $true }

    $resultatAsync = $ps.BeginInvoke()

    $minuteur = New-Object System.Windows.Forms.Timer
    $minuteur.Interval = 200
    $minuteur.Add_Tick({
        if (-not $resultatAsync.IsCompleted) { return }
        $minuteur.Stop()
        $minuteur.Dispose()
        $estPerime = ($pictureBox.Tag -ne $generation)
        $image = $null
        try {
            $resultats = $ps.EndInvoke($resultatAsync)
            if ($ps.Streams.Error.Count -gt 0) { $errRec = $ps.Streams.Error[0]; throw "$($errRec.Exception.Message) | $($errRec.InvocationInfo.PositionMessage)" }
            $resultat = $resultats | Select-Object -Last 1
            $image = $resultat.Image
            if (-not $estPerime) {
                if ($pictureBox.Image) { $pictureBox.Image.Dispose() }
                $pictureBox.Image = $image
                # Force le reaffichage (10/10/2026, Tomyn : rotation "reussie" dans le journal mais
                # case visuellement inchangee) - assigner .Image devrait suffire en theorie, mais
                # jamais verifiable ici (pas de GDI+ sous Linux) ; Invalidate+Update force sans
                # risque un repaint immediat au cas ou WinForms ne l'ait pas declenche tout seul.
                $pictureBox.Invalidate()
                $pictureBox.Update()
                $etatPartage[$cle] = [PSCustomObject]@{
                    Triangles        = $resultat.Triangles
                    AngleY           = $resultat.AngleYChoisi
                    AngleX           = $resultat.AngleXChoisi
                    Chemin           = $chemin3mf
                    # Historique a un seul niveau pour le bouton "Defaire" (10/10/2026) - initialise
                    # au MEME angle qu'a l'arrivee, donc "Defaire" juste apres un chargement ne fait
                    # rien (rien a annuler encore), plutot que de planter sur un champ absent.
                    AngleYPrecedent  = $resultat.AngleYChoisi
                    AngleXPrecedent  = $resultat.AngleXChoisi
                }
                Enregistrer-AngleFichier $chemin3mf $resultat.AngleYChoisi $resultat.AngleXChoisi
                $labelAngle = $etatPartage["__Label_$cle__"]
                if ($labelAngle) { $labelAngle.Text = "Rotation : {0:N0} deg  /  Inclinaison : {1:N0} deg" -f $resultat.AngleYChoisi, $resultat.AngleXChoisi }
                Ecrire-Journal ("Apercu : lecture {0:N1} s + angle {1:N1} s + dessin {2:N1} s ({3} triangles, {4} dessines en {5} groupe(s), rotation {6} deg, inclinaison {7} deg)" -f $resultat.DureeLecture, $resultat.DureeAngle, $resultat.DureeDessin, $resultat.NombreTriangles, $resultat.NombreDessines, $resultat.NombreGroupes, $resultat.AngleYChoisi, $resultat.AngleXChoisi)
            } elseif ($image) {
                $image.Dispose()
            }
        } catch {
            # Un apercu qui echoue ne doit jamais bloquer le reste de l'outil (melange y compris) -
            # on se contente de vider la case et de noter l'echec dans le journal. Un arret demande
            # via le bouton "Stop" finit aussi ici (PipelineStoppedException) - $estPerime est alors
            # deja vrai (le bouton Stop a bascule le jeton de fraicheur), donc rien ne s'affiche.
            if (-not $estPerime) {
                if ($pictureBox.Image) { $pictureBox.Image.Dispose() }
                $pictureBox.Image = $null
                Ecrire-Journal ("(Apercu indisponible : " + (Obtenir-DetailErreurApercu $_ $ps) + ")")
            }
        } finally {
            if (-not $estPerime) { $pictureBox.Cursor = [System.Windows.Forms.Cursors]::Default }
            if ($boutonStop) { $boutonStop.Enabled = $false }
            $ps.Dispose()
            $runspace.Close()
        }
    }.GetNewClosure())
    $minuteur.Start()
}

# Rotation manuelle de l'apercu (10/10/2026, Tomyn : l'angle choisi automatiquement reste mauvais sur
# certains modeles - sans notion de "visage"/"avant", une heuristique purement geometrique ne peut
# pas toujours deviner le bon cote a montrer). Reutilise les triangles DEJA LUS (caches dans
# $script:ApercuEtat par Mettre-A-Jour-Apercu) pour ne redessiner QUE l'image, sans relire tout le
# fichier .3mf ni relancer la recherche d'angle a chaque clic.
function Redessiner-Apercu-AvecRotation([System.Windows.Forms.PictureBox]$pictureBox, [string]$cle, [double]$deltaAngleY, [double]$deltaAngleX) {
    # Diagnostic (10/10/2026, Tomyn : "les fleches ne fonctionnent pas") : avant meme de verifier
    # l'etat memorise, on confirme que le clic est bien recu et par quelle case/delta - si ce
    # message n'apparait jamais dans le journal, le probleme est dans le bouton/la closure, pas ici.
    Ecrire-Journal "Rotation demandee (case '$cle', deltaY=$deltaAngleY, deltaX=$deltaAngleX)..."
    $etat = $script:ApercuEtat[$cle]
    if (-not $etat -or -not $etat.Triangles) {
        Ecrire-Journal "Rotation annulee : aucun apercu charge en memoire pour la case '$cle' (relance d'abord l'apercu normal)."
        return
    }
    # Capture AVANT le Timer (lecture simple, hors closure, donc $script: est sans risque ici) -
    # sert a mettre a jour l'affichage "Rotation : ... / Inclinaison : ..." une fois le redessin fini.
    $labelAngle = $script:ApercuEtat["__Label_$cle__"]
    $boutonStop = $script:ApercuEtat["__BoutonStop_$cle__"]

    # Historique a un seul niveau pour "Defaire" (10/10/2026, Tomyn : "go les amelio") - memorise
    # l'angle d'AVANT ce changement precis. Ecrase a chaque rotation (manuelle, "Auto" qui reapplique
    # la reference, ou clic sur une vignette - tout passe par cette fonction) : un seul cran de recul,
    # cliquer "Defaire" deux fois de suite revient donc a l'etat de depart (bascule, pas une pile).
    $etat.AngleYPrecedent = $etat.AngleY
    $etat.AngleXPrecedent = $etat.AngleX

    $nouvelAngleY = (($etat.AngleY + $deltaAngleY) % 360 + 360) % 360
    # Inclinaison plafonnee pour eviter une vue totalement a plat (0, vue de dessus pure) ou
    # retournee (negatif au-dela de -80, qui recommencerait a montrer le dessous) - une plage large
    # mais qui reste une vue en perspective exploitable.
    $nouvelAngleX = [Math]::Max(-80, [Math]::Min(10, $etat.AngleX + $deltaAngleX))

    $pictureBox.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $generation = ([int]$pictureBox.Tag) + 1
    $pictureBox.Tag = $generation

    # Resolution reduite pour la rotation INTERACTIVE uniquement (10/10/2026, Tomyn : ~20s par clic,
    # trop long pour du tatonnement) - PictureBox en SizeMode "Zoom" agrandit automatiquement a
    # l'affichage, donc la taille a l'ecran ne change pas, seule la finesse baisse un peu. Diviser
    # largeur/hauteur par 2 divise l'echelle par 2, donc l'aire ecran de chaque triangle (qui depend
    # du CARRE de l'echelle, cf. Nouvelle-ImageApercu) par 4 - beaucoup plus de triangles passent
    # sous le seuil de culling et sont ignores, ce qui devrait reduire nettement le temps de dessin.
    # Le chargement initial (Mettre-A-Jour-Apercu, Auto compris) reste en pleine resolution.
    $largeurRotation = [Math]::Max(60, [Math]::Floor($largeurApercu / 2))
    $hauteurRotation = [Math]::Max(52, [Math]::Floor($hauteurApercu / 2))

    $corpsFonctions = "function Nouvelle-ImageApercu { " + (${function:Nouvelle-ImageApercu}.ToString()) + " }"
    $script = @"
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$corpsFonctions
`$resultatImage = Nouvelle-ImageApercu `$args[0] ([int]`$args[1]) ([int]`$args[2]) `$args[3] `$args[4]
`$resultatImage
"@

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($script)
    [void]$ps.AddArgument($etat.Triangles)
    [void]$ps.AddArgument($largeurRotation)
    [void]$ps.AddArgument($hauteurRotation)
    [void]$ps.AddArgument($nouvelAngleY)
    [void]$ps.AddArgument($nouvelAngleX)

    $script:ApercuEtat["__PSActif_$cle__"] = $ps
    if ($boutonStop) { $boutonStop.Enabled = $true }

    $resultatAsync = $ps.BeginInvoke()

    $minuteur = New-Object System.Windows.Forms.Timer
    $minuteur.Interval = 200
    $minuteur.Add_Tick({
        if (-not $resultatAsync.IsCompleted) { return }
        $minuteur.Stop()
        $minuteur.Dispose()
        $estPerime = ($pictureBox.Tag -ne $generation)
        $image = $null
        try {
            $resultats = $ps.EndInvoke($resultatAsync)
            if ($ps.Streams.Error.Count -gt 0) { $errRec = $ps.Streams.Error[0]; throw "$($errRec.Exception.Message) | $($errRec.InvocationInfo.PositionMessage)" }
            $resultat = $resultats | Select-Object -Last 1
            $image = $resultat.Bitmap
            if (-not $estPerime) {
                if ($pictureBox.Image) { $pictureBox.Image.Dispose() }
                $pictureBox.Image = $image
                $pictureBox.Invalidate()
                $pictureBox.Update()
                # $etat est deja une REFERENCE vers l'objet stocke dans $script:ApercuEtat[$cle] (un
                # PSCustomObject, type reference) - le modifier directement suffit, pas besoin (et
                # pas sans danger, voir la note sur $script: dans une closure plus haut) de
                # re-indexer le hashtable ici.
                $etat.AngleY = $nouvelAngleY
                $etat.AngleX = $nouvelAngleX
                if ($etat.Chemin) { Enregistrer-AngleFichier $etat.Chemin $nouvelAngleY $nouvelAngleX }
                if ($labelAngle) { $labelAngle.Text = "Rotation : {0:N0} deg  /  Inclinaison : {1:N0} deg" -f $nouvelAngleY, $nouvelAngleX }
                Ecrire-Journal ("Apercu : rotation manuelle ({0} dessines en {1} groupe(s), rotation {2:N0} deg, inclinaison {3:N0} deg) - hash image={4}, hash sur la case={5}, taille={6}x{7}" -f $resultat.NombreDessines, $resultat.NombreGroupes, $nouvelAngleY, $nouvelAngleX, $image.GetHashCode(), $pictureBox.Image.GetHashCode(), $image.Width, $image.Height)
            } elseif ($image) {
                $image.Dispose()
            }
        } catch {
            if (-not $estPerime) { Ecrire-Journal ("(Rotation d'apercu impossible : " + (Obtenir-DetailErreurApercu $_ $ps) + ")") }
        } finally {
            if (-not $estPerime) { $pictureBox.Cursor = [System.Windows.Forms.Cursors]::Default }
            if ($boutonStop) { $boutonStop.Enabled = $false }
            $ps.Dispose()
            $runspace.Close()
        }
    }.GetNewClosure())
    $minuteur.Start()
}

# Planche de vignettes (10/10/2026, Tomyn : "le bleu c'est trop flashy, difficile de juger un angle
# a l'oeil" + "Auto" qui retombe toujours sur le meme resultat) - calcule plusieurs angles candidats
# d'un coup (grille de 4 rotations x 2 inclinaisons, voir plus bas) a partir des triangles deja
# en memoire, les affiche en petit dans une fenetre a part, et Tomyn clique directement celui qui
# montre le bon cote au lieu de tatonner clic par clic avec les fleches. Avertissement honnete : ce
# n'est pas instantane - meme en miniature, le calcul reparcourt TOUT le maillage pour chacune des 8
# vignettes (le gros du cout est la boucle de projection/filtrage, pas le dessin GDI+ en lui-meme),
# donc attends-toi a un temps total proche de 8x le cout d'un seul redessin manuel.
function Afficher-SelecteurVignettes([System.Windows.Forms.PictureBox]$pictureBox, [string]$cle, $etatPartage) {
    $etat = $etatPartage[$cle]
    if (-not $etat -or -not $etat.Triangles) {
        Ecrire-Journal "Vignettes impossible : aucun apercu charge en memoire pour la case '$cle' (relance d'abord l'apercu normal)."
        return
    }
    Ecrire-Journal "Calcul des vignettes (case '$cle')... ca va prendre un moment, le journal affichera la suite une fois pret."

    # Grille rotation x inclinaison (10/10/2026, Tomyn : "go les amelio") - avant, les 8 vignettes
    # ne faisaient varier que la rotation, a l'inclinaison actuelle fixe. Desormais, rangee 1 =
    # inclinaison actuelle, rangee 2 = une inclinaison alternative (actuelle - 20 deg, plafonnee
    # comme Redessiner-Apercu-AvecRotation) - au prix d'un pas de rotation plus grossier (90 deg au
    # lieu de 45) pour garder le meme nombre total de vignettes (8) et donc le meme temps de calcul.
    $angleXFixe = $etat.AngleX
    $angleXAlt = [Math]::Max(-80, [Math]::Min(10, $angleXFixe - 20))
    $rotationsCandidates = @(0, 90, 180, 270)
    $anglesCandidats = @($rotationsCandidates | ForEach-Object { , @($_, $angleXFixe) }) + @($rotationsCandidates | ForEach-Object { , @($_, $angleXAlt) })
    $largeurVignette = 220
    $hauteurVignette = 190

    $corpsFonctions = "function Nouvelle-ImageApercu { " + (${function:Nouvelle-ImageApercu}.ToString()) + " }"
    $script = @"
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$corpsFonctions
`$resultats = New-Object System.Collections.Generic.List[object]
foreach (`$a in `$args[1]) {
    `$img = Nouvelle-ImageApercu `$args[0] ([int]`$args[2]) ([int]`$args[3]) ([double]`$a[0]) ([double]`$a[1])
    [void]`$resultats.Add([PSCustomObject]@{ AngleY = `$a[0]; AngleX = `$a[1]; Bitmap = `$img.Bitmap })
}
`$resultats
"@

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($script)
    [void]$ps.AddArgument($etat.Triangles)
    [void]$ps.AddArgument($anglesCandidats)
    [void]$ps.AddArgument($largeurVignette)
    [void]$ps.AddArgument($hauteurVignette)

    $etatPartage["__PSActif_$cle__"] = $ps
    $boutonStopAvantTick = $etatPartage["__BoutonStop_$cle__"]
    if ($boutonStopAvantTick) { $boutonStopAvantTick.Enabled = $true }

    $resultatAsync = $ps.BeginInvoke()

    $pictureBox.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $minuteur = New-Object System.Windows.Forms.Timer
    $minuteur.Interval = 300
    $minuteur.Add_Tick({
        if (-not $resultatAsync.IsCompleted) { return }
        $minuteur.Stop()
        $minuteur.Dispose()
        $pictureBox.Cursor = [System.Windows.Forms.Cursors]::Default
        # IMPORTANT (3e variante du bug de fermeture decouverte dans ce fichier) : une
        # closure .GetNewClosure() CONSTRUITE A L'INTERIEUR d'une autre closure
        # .GetNewClosure() (ici : les Add_Click des vignettes, construits a l'interieur
        # de ce Add_Tick) NE RECUPERE PAS les variables que CETTE closure externe avait
        # elle-meme capturees depuis les PARAMETRES de la fonction (ici $pictureBox,
        # $cle, $etatPartage, parametres de Afficher-SelecteurVignettes). Verifie par
        # test isole : la closure interne les voit $null/vides. En revanche, une
        # variable simplement DEFINIE ICI (comme $popup, $chkReference, $candAngleY...
        # plus bas) est bien visible depuis la closure imbriquee, sans recapture.
        # D'ou cette recapture locale explicite, AVANT toute closure imbriquee :
        $cleLocale = $cle
        $etatPartageLocal = $etatPartage
        $pictureBoxLocal = $pictureBox
        try {
            $resultats = $ps.EndInvoke($resultatAsync)
            if ($ps.Streams.Error.Count -gt 0) { $errRec = $ps.Streams.Error[0]; throw "$($errRec.Exception.Message) | $($errRec.InvocationInfo.PositionMessage)" }
            Ecrire-Journal "Vignettes pretes (case '$cle')."

            $popup = New-Object System.Windows.Forms.Form
            $popup.Text = "Choisir un angle"
            $popup.StartPosition = "CenterParent"
            $popup.FormBorderStyle = "FixedDialog"
            $popup.MaximizeBox = $false
            $popup.MinimizeBox = $false
            $margeVignette = 8
            $colonnes = 4
            $largeurPopup = $colonnes * ($largeurVignette + $margeVignette) + $margeVignette
            # IMPORTANT : piege de syntaxe PowerShell verifie dans ce fichier - ecrire une
            # expression arithmetique DIRECTEMENT comme argument d'un "New-Object Type(...)"
            # (ex: New-Object System.Drawing.Size($a, 2 * ($b + $c) + 50)) fait parfois planter
            # la resolution du constructeur ("Cannot find an overload ... argument count : 285")
            # car le "*" suivi d'une parenthese se fait reinterpreter au lieu d'une multiplication
            # normale, dans ce contexte d'arguments de commande. Teste et confirme reproductible.
            # Correctif : toujours precalculer l'expression dans une variable AVANT de la passer
            # a New-Object.
            $yRangeeVignettes = $hauteurVignette + 30 + $margeVignette
            $hauteurClientPopup = 2 * $yRangeeVignettes + 50
            $yCaseReference = 2 * $yRangeeVignettes
            $popup.ClientSize = New-Object System.Drawing.Size($largeurPopup, $hauteurClientPopup)

            $chkReference = New-Object System.Windows.Forms.CheckBox
            $chkReference.Text = "Garder comme reference pour les prochains imports"
            $chkReference.AutoSize = $true
            $chkReference.Location = New-Object System.Drawing.Point($margeVignette, $yCaseReference)
            $popup.Controls.Add($chkReference)

            $i = 0
            foreach ($r in $resultats) {
                $col = $i % $colonnes
                $ligne = [Math]::Floor($i / $colonnes)
                $xV = $margeVignette + $col * ($largeurVignette + $margeVignette)
                $yV = $margeVignette + $ligne * $yRangeeVignettes
                $yLabel = $yV + $hauteurVignette + 2

                # Vignette correspondant a l'angle DEJA applique sur l'apercu principal (10/10/2026,
                # Tomyn : "go les amelio") - repere visuel simple (texte en gras, couleur d'accent,
                # mention "(actuel)") plutot qu'une bordure coloree, que PictureBox ne permet pas de
                # personnaliser facilement sans dessin GDI+ sur-mesure. Tolerance de 0.01 deg : les
                # deux valeurs viennent du meme calcul deterministe, un ecart plus grand signifierait
                # vraiment un angle different.
                $estAngleActuel = ([Math]::Abs($r.AngleY - $etat.AngleY) -lt 0.01) -and ([Math]::Abs($r.AngleX - $etat.AngleX) -lt 0.01)

                $pic = New-Object System.Windows.Forms.PictureBox
                $pic.Location = New-Object System.Drawing.Point($xV, $yV)
                $pic.Size = New-Object System.Drawing.Size($largeurVignette, $hauteurVignette)
                $pic.SizeMode = "Zoom"
                $pic.BorderStyle = "FixedSingle"
                $pic.Image = $r.Bitmap
                $pic.Cursor = [System.Windows.Forms.Cursors]::Hand
                $popup.Controls.Add($pic)

                $lbl = New-Object System.Windows.Forms.Label
                # Forme compacte (deg en symbole) pour tenir sur une ligne dans la largeur d'une
                # vignette (220px) - "Rotation 270 deg / Inclinaison -30 deg" deborderait.
                $lbl.Text = "{0:N0} deg / {1:N0} deg" -f $r.AngleY, $r.AngleX
                if ($estAngleActuel) { $lbl.Text += " (actuel)" }
                $lbl.Location = New-Object System.Drawing.Point($xV, $yLabel)
                $lbl.Size = New-Object System.Drawing.Size($largeurVignette, 18)
                $lbl.TextAlign = "MiddleCenter"
                $lbl.Font = New-Object System.Drawing.Font($lbl.Font.FontFamily, 7.5)
                if ($estAngleActuel) {
                    $lbl.ForeColor = $THEME.AccentPrincipal
                    $lbl.Font = New-Object System.Drawing.Font($lbl.Font, [System.Drawing.FontStyle]::Bold)
                }
                $popup.Controls.Add($lbl)

                # Capture LOCALE (une par iteration, voir toutes les notes de fermeture plus haut
                # dans ce fichier) - $candAngleY/$candAngleX sont a CE pictureBox-vignette, pas a une
                # reference qui changerait a la prochaine iteration de la boucle.
                $candAngleY = $r.AngleY
                $candAngleX = $r.AngleX
                $pic.Add_Click({
                    $etatActuel = $etatPartageLocal[$cleLocale]
                    if ($etatActuel) {
                        $deltaY = $candAngleY - $etatActuel.AngleY
                        $deltaX = $candAngleX - $etatActuel.AngleX
                        if ($chkReference.Checked) {
                            $nouvelleReference = [PSCustomObject]@{ AngleY = $candAngleY; AngleX = $candAngleX }
                            $etatPartageLocal['__ReferenceGlobale__'] = $nouvelleReference
                            # Enregistree sur disque (10/10/2026, Tomyn : "go les amelio") - sinon
                            # perdue a la fermeture de l'appli, cf. Sauvegarder-ReferenceGlobale plus
                            # haut. Un appel de fonction par son nom reste sans risque ici, meme a
                            # cette profondeur de closures imbriquees (seule la capture de VARIABLE
                            # pose probleme, pas la resolution de nom de fonction).
                            Sauvegarder-ReferenceGlobale $nouvelleReference
                            Ecrire-Journal "Angle memorise comme reference pour les prochains imports (rotation $candAngleY deg, inclinaison $candAngleX deg)."
                        } else {
                            $etatPartageLocal['__ReferenceGlobale__'] = $null
                            Sauvegarder-ReferenceGlobale $null
                        }
                        Redessiner-Apercu-AvecRotation $pictureBoxLocal $cleLocale $deltaY $deltaX
                    }
                    $popup.Close()
                }.GetNewClosure())
                $i++
            }

            $popup.ShowDialog($form) | Out-Null
            # Les Bitmaps restent references par les PictureBox vignettes jusqu'a la fermeture de
            # cette fenetre - les liberer maintenant qu'elle est fermee (sauf celui qui vient d'etre
            # applique a l'apercu principal, qui est un DOUBLON genere separement par
            # Redessiner-Apercu-AvecRotation, pas le meme objet que ces vignettes).
            foreach ($r in $resultats) { if ($r.Bitmap) { $r.Bitmap.Dispose() } }
        } catch {
            Ecrire-Journal ("(Vignettes indisponibles : " + (Obtenir-DetailErreurApercu $_ $ps) + ")")
        } finally {
            if ($boutonStopAvantTick) { $boutonStopAvantTick.Enabled = $false }
            $ps.Dispose()
            $runspace.Close()
        }
    }.GetNewClosure())
    $minuteur.Start()
}

$btnLancer.Add_Click({
    $cheminEntree = $txtFichier.Text.Trim('"').Trim()
    if (-not $cheminEntree -or -not (Test-Path $cheminEntree)) {
        Afficher-Boite "Choisis d'abord un fichier .3mf valide." "Fichier manquant" "OK" "Error" | Out-Null
        return
    }
    $txtJournal.Clear()
    $btnLancer.Enabled = $false
    $btnParcourir.Enabled = $false
    $menuTrio.Enabled = $false
    $btnLotDossier.Enabled = $false
    $btnLotFichiers.Enabled = $false
    $testRapide = $caseTestRapide.Checked
    $cheminSortieTemporaire = $null
    try {
        $nomTrio = $menuTrio.SelectedItem.ToString()
        $trio = $TRIOS[$nomTrio]
        $pasChoisi = [int]$selecteurPrecision.Value

        # Verification automatique de la couverture AVANT de lancer (13/10/2026, idee "vaut le
        # coup" validee par Tomyn : "OK POUR 'VAUT LE COUP'") - reutilise Verifier-CouvertureFichier
        # (deja utilisee par "Verifier la couverture du fichier..." et les suggestions de trios) pour
        # avertir si le trio choisi rend mal sur CE fichier precis, avant de lancer le melange pour
        # de vrai. Non bloquant en cas d'echec de lecture : Verifier-CouvertureFichier protege deja
        # ses propres erreurs par un try/catch interne et renvoie $null dans ce cas, donc pas
        # d'avertissement affiche (pas de donnee fiable a montrer) mais le melange se lance quand
        # meme - jamais empeche de travailler a cause d'une couleur illisible dans le fichier.
        $resultatCouvertureAvantLancement = Verifier-CouvertureFichier $cheminEntree $trio
        if ($resultatCouvertureAvantLancement -and $resultatCouvertureAvantLancement.NombreMalCouvertes -gt 0) {
            $messageCouvertureAvantLancement = "Attention : avec le trio '$nomTrio', $($resultatCouvertureAvantLancement.NombreMalCouvertes) couleur(s) sur $($resultatCouvertureAvantLancement.NombreCouleurs) dans ce fichier risquent d'etre visiblement mal rendues (ecart Lab moyen $([Math]::Round($resultatCouvertureAvantLancement.EcartMoyen, 1)), max $([Math]::Round($resultatCouvertureAvantLancement.EcartMax, 1))).`r`n`r`nLancer quand meme le melange avec ce trio ?"
            if ((Afficher-Boite $messageCouvertureAvantLancement "Couverture a verifier" "YesNo" "Warning") -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }

        if ($testRapide) {
            # Fichier TEMPORAIRE (supprime dans le finally) plutot que le "..._melange.3mf" habituel
            # - voir le commentaire sur $caseTestRapide plus haut.
            $cheminSortieTemporaire = Join-Path ([System.IO.Path]::GetTempPath()) ("test_rapide_" + [guid]::NewGuid().ToString("N") + ".3mf")
            $cheminSortie = $cheminSortieTemporaire
        } else {
            $cheminSortie = [System.IO.Path]::Combine(
                [System.IO.Path]::GetDirectoryName((Resolve-Path $cheminEntree)),
                ([System.IO.Path]::GetFileNameWithoutExtension($cheminEntree) + "_melange.3mf")
            )
            # Confirmation avant d'ecraser un resultat deja present (11/10/2026, Tomyn : "1-2-3-4")
            # - si on relance sur le meme fichier (trio different, reglages differents...), le
            # precedent "..._melange.3mf" serait sinon ecrase sans prevenir. Meme principe deja en
            # place pour le lot (fichiers deja traites decoches par defaut dans Afficher-ConfirmationLot).
            if (Test-Path $cheminSortie) {
                if ((Afficher-Boite "Le fichier de sortie existe deja :`r`n$cheminSortie`r`n`r`nL'ecraser avec ce nouveau resultat ?" "Fichier deja existant" "YesNo" "Warning") -ne [System.Windows.Forms.DialogResult]::Yes) {
                    return
                }
            }
        }

        Ecrire-Journal "Trio choisi : $nomTrio"
        if ($testRapide) { Ecrire-Journal "(Test rapide - rien ne sera enregistre a cote du fichier d'origine)" }
        Ecrire-Journal ""
        Traiter-Fichier3MF $cheminEntree $cheminSortie $trio $pasChoisi ${function:Ecrire-Journal} ([int]$selecteurMelanges.Value)

        if ($testRapide) {
            Afficher-Boite "Test rapide termine - rien n'a ete enregistre.`r`n`r`nLe detail des melanges est dans le journal ci-contre." "Test rapide termine" "OK" "Info" | Out-Null
        } else {
            Ajouter-LigneHistorique $nomTrio $cheminEntree "OK -> $cheminSortie"
            Mettre-A-Jour-AlerteDejaTraite $cheminEntree
            Mettre-A-Jour-Apercu $pictureApres "apres" $cheminSortie
            # Demande par Tomyn (10/10/2026) : plus besoin d'aller chercher le dossier de sortie a la
            # main - l'explorateur Windows s'ouvre directement sur le fichier cree, selectionne. Dans
            # un try/catch silencieux : si explorer.exe n'est pas trouve pour une raison ou une autre,
            # ca ne doit surtout pas empecher d'afficher la confirmation ci-dessous.
            try { Start-Process "explorer.exe" -ArgumentList "/select,`"$cheminSortie`"" } catch { }
            Afficher-Boite "Fichier cree :`r`n$cheminSortie`r`n`r`nRappel : le dosage est une approximation maison, pas garantie identique a celle de Bambu Studio - a verifier avant un gros lot (voir le README)." "Melange termine" "OK" "Info" | Out-Null
        }
    } catch {
        Ecrire-Journal "ERREUR : $_"
        if ($nomTrio -and -not $testRapide) { Ajouter-LigneHistorique $nomTrio $cheminEntree "ECHEC : $_" }
        Afficher-Boite "$_" "Erreur" "OK" "Error" | Out-Null
    } finally {
        if ($cheminSortieTemporaire -and (Test-Path $cheminSortieTemporaire)) {
            Remove-Item -Path $cheminSortieTemporaire -Force -ErrorAction SilentlyContinue
        }
        $btnLancer.Enabled = $true
        $btnParcourir.Enabled = $true
        $menuTrio.Enabled = $true
        $btnLotDossier.Enabled = $true
        $btnLotFichiers.Enabled = $true
    }
})

function Obtenir-CheminSortieLot([string]$fichier) {
    [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName((Resolve-Path $fichier)),
        ([System.IO.Path]::GetFileNameWithoutExtension($fichier) + "_melange.3mf")
    )
}

# Fenetre de confirmation avant de lancer un lot (10/10/2026, Tomyn : "go les amelio") - montre la
# liste des fichiers trouves AVANT de foncer, avec une case par fichier pour en exclure certains.
# Les fichiers dont la sortie "_melange.3mf" existe deja sont DECOCHES par defaut (pas re-traites
# sans le demander explicitement - mais cochables a la main si Tomyn veut vraiment les refaire).
function Afficher-ConfirmationLot([string[]]$fichiers, [string]$nomTrio, $trio) {
    if (-not $fichiers -or $fichiers.Count -eq 0) {
        Afficher-Boite "Aucun fichier .3mf a traiter." "Lot vide" "OK" "Warning" | Out-Null
        return
    }
    $popup = New-Object System.Windows.Forms.Form
    $popup.Text = "Confirmer le lot ($($fichiers.Count) fichier(s))"
    $popup.StartPosition = "CenterParent"
    $popup.FormBorderStyle = "Sizable"
    $popup.MinimizeBox = $false
    $popup.ClientSize = New-Object System.Drawing.Size(520, 460)

    $liste = New-Object System.Windows.Forms.CheckedListBox
    $liste.Location = New-Object System.Drawing.Point(10, 10)
    $liste.Size = New-Object System.Drawing.Size(500, 360)
    $liste.Anchor = "Top, Bottom, Left, Right"
    $liste.CheckOnClick = $true
    $popup.Controls.Add($liste)

    # Correspondance affichage -> chemin complet (CheckedListBox n'affiche que du texte) - tableau
    # parallele, dans le MEME ordre d'ajout que les items, pour retrouver le chemin complet d'un
    # item coche au moment de lancer le lot.
    $cheminsParIndex = New-Object System.Collections.Generic.List[string]
    foreach ($fichier in $fichiers) {
        $cheminSortie = Obtenir-CheminSortieLot $fichier
        $dejaTraite = Test-Path $cheminSortie
        $texte = [System.IO.Path]::GetFileName($fichier)
        if ($dejaTraite) { $texte += "  (deja traite - sortie existante)" }
        [void]$liste.Items.Add($texte, (-not $dejaTraite))
        [void]$cheminsParIndex.Add($fichier)
    }

    $btnTout = New-Object System.Windows.Forms.Button
    $btnTout.Text = "Tout cocher"
    $btnTout.Location = New-Object System.Drawing.Point(10, 378)
    $btnTout.Size = New-Object System.Drawing.Size(120, 28)
    Rendre-BoutonPlat $btnTout "secondaire"
    $btnTout.Anchor = "Bottom, Left"
    $btnTout.Add_Click({
        for ($k = 0; $k -lt $liste.Items.Count; $k++) { $liste.SetItemChecked($k, $true) }
    }.GetNewClosure())
    $popup.Controls.Add($btnTout)

    $btnAucun = New-Object System.Windows.Forms.Button
    $btnAucun.Text = "Tout decocher"
    $btnAucun.Location = New-Object System.Drawing.Point(140, 378)
    $btnAucun.Size = New-Object System.Drawing.Size(120, 28)
    Rendre-BoutonPlat $btnAucun "secondaire"
    $btnAucun.Anchor = "Bottom, Left"
    $btnAucun.Add_Click({
        for ($k = 0; $k -lt $liste.Items.Count; $k++) { $liste.SetItemChecked($k, $false) }
    }.GetNewClosure())
    $popup.Controls.Add($btnAucun)

    $btnLancerLot = New-Object System.Windows.Forms.Button
    $btnLancerLot.Text = "Lancer le lot"
    $btnLancerLot.Location = New-Object System.Drawing.Point(290, 414)
    $btnLancerLot.Size = New-Object System.Drawing.Size(110, 32)
    Rendre-BoutonPlat $btnLancerLot "principal"
    $btnLancerLot.Anchor = "Bottom, Right"
    $btnLancerLot.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $popup.Controls.Add($btnLancerLot)

    $btnAnnulerLot = New-Object System.Windows.Forms.Button
    $btnAnnulerLot.Text = "Annuler"
    $btnAnnulerLot.Location = New-Object System.Drawing.Point(405, 414)
    $btnAnnulerLot.Size = New-Object System.Drawing.Size(105, 32)
    Rendre-BoutonPlat $btnAnnulerLot "discret"
    $btnAnnulerLot.Anchor = "Bottom, Right"
    $btnAnnulerLot.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $popup.Controls.Add($btnAnnulerLot)

    $popup.AcceptButton = $btnLancerLot
    $popup.CancelButton = $btnAnnulerLot

    if ($popup.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $fichiersChoisis = New-Object System.Collections.Generic.List[string]
        for ($k = 0; $k -lt $liste.Items.Count; $k++) {
            if ($liste.GetItemChecked($k)) { [void]$fichiersChoisis.Add($cheminsParIndex[$k]) }
        }
        Traiter-LotDeFichiers $fichiersChoisis $nomTrio $trio
    }
}

# Scan d'un dossier (bouton "Lot : un dossier..." ET glisser-deposer d'un dossier) - factorise ici
# pour que les deux points d'entree partagent exactement la meme logique de filtrage.
function Lancer-LotDepuisDossier([string]$dossier) {
    # Non recursif (10/10/2026) - seulement les .3mf directement dans ce dossier, pas les
    # sous-dossiers (pas demande par Tomyn ; facile a changer plus tard si besoin, -Recurse sur
    # Get-ChildItem). Exclut les "*_melange.3mf" deja produits par un lot precedent de la liste
    # PROPOSEE - ceux geres par la case a cocher "deja traite" sont filtres plus loin dans
    # Afficher-ConfirmationLot, celle-ci exclut en plus les melanges eux-memes (jamais a re-melanger).
    $fichiers = Get-ChildItem -Path $dossier -Filter "*.3mf" -File |
        Where-Object { $_.Name -notlike "*_melange.3mf" } |
        ForEach-Object { $_.FullName }
    if (-not $fichiers -or $fichiers.Count -eq 0) {
        Afficher-Boite "Aucun fichier .3mf trouve dans ce dossier (les fichiers '*_melange.3mf' deja produits sont ignores)." "Dossier vide" "OK" "Warning" | Out-Null
        return
    }
    $nomTrio = $menuTrio.SelectedItem.ToString()
    $trio = $TRIOS[$nomTrio]
    Afficher-ConfirmationLot $fichiers $nomTrio $trio
}

# Traitement en lot (10/10/2026, Tomyn : "je voudrais arriver a terme ... voir un dossier complet")
# - meme logique que le traitement fichier unique ci-dessus (Traiter-Fichier3MF), mais en boucle sur
# plusieurs fichiers, APPELE SEQUENTIELLEMENT (pas en parallele - plus simple, et Traiter-Fichier3MF
# fait deja ses propres DoEvents via Ecrire-Journal donc la fenetre reste reactive entre deux
# fichiers). Decisions prises avec Tomyn : meme trio pour tout le lot ; un fichier en echec est
# note dans le journal et le lot CONTINUE sur les suivants (pas d'arret global) ; l'apercu avant/
# apres reste desactive PENDANT le lot (sinon un calcul d'angle/rendu en plus par fichier, inutile
# pour un simple traitement en masse) - seul le dernier fichier reussi est affiche en "apres" une
# fois le lot entierement termine, pour un controle visuel rapide. La selection des fichiers (et le
# filtrage des "deja traites") se fait en AMONT, dans Afficher-ConfirmationLot - cette fonction
# traite tel quel ce qu'on lui donne.
function Traiter-LotDeFichiers([string[]]$fichiers, [string]$nomTrio, $trio) {
    if (-not $fichiers -or $fichiers.Count -eq 0) {
        Afficher-Boite "Aucun fichier .3mf a traiter." "Lot vide" "OK" "Warning" | Out-Null
        return
    }
    $txtJournal.Clear()
    $btnLancer.Enabled = $false
    $btnParcourir.Enabled = $false
    $menuTrio.Enabled = $false
    $btnLotDossier.Enabled = $false
    $btnLotFichiers.Enabled = $false
    $labelProgresLot.Visible = $true
    $barreProgresLot.Visible = $true
    $barreProgresLot.Minimum = 0
    $barreProgresLot.Maximum = $fichiers.Count
    $barreProgresLot.Value = 0
    # Chronometre le lot de bout en bout (10/10/2026, Tomyn : "toutes stp") - affiche dans le resume
    # final, pratique pour estimer la duree d'un prochain lot de taille comparable.
    $chronoLot = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $reussis = New-Object System.Collections.Generic.List[string]
        $echecs = New-Object System.Collections.Generic.List[string]
        $dernierCheminSortie = $null

        Ecrire-Journal "Lot de $($fichiers.Count) fichier(s) avec le trio '$nomTrio'."
        Ecrire-Journal ""

        $i = 0
        foreach ($fichier in $fichiers) {
            $i++
            $nomCourt = [System.IO.Path]::GetFileName($fichier)
            $labelProgresLot.Text = "Fichier $i / $($fichiers.Count) : $nomCourt"
            [System.Windows.Forms.Application]::DoEvents()
            Ecrire-Journal "--- [$i/$($fichiers.Count)] $nomCourt ---"
            try {
                if (-not (Test-Path $fichier)) { throw "fichier introuvable" }
                $cheminSortie = Obtenir-CheminSortieLot $fichier
                # Nombre de melanges auto-detecte PAR FICHIER (10/10/2026) - contrairement au mode
                # fichier unique, le reglage manuel du selecteur ne correspond qu'a UN fichier ; en
                # lot, chaque fichier peut avoir un nombre de couleurs different a regrouper.
                $nombreMelanges = 29
                try {
                    $detecte = Obtenir-NombreCouleursDetectees $fichier
                    if ($detecte -gt 0) { $nombreMelanges = [Math]::Min($detecte, 29) }
                } catch { }
                Traiter-Fichier3MF $fichier $cheminSortie $trio ([int]$selecteurPrecision.Value) ${function:Ecrire-Journal} $nombreMelanges
                $reussis.Add($cheminSortie)
                $dernierCheminSortie = $cheminSortie
                Ajouter-LigneHistorique $nomTrio $fichier "OK -> $cheminSortie"
                # Nombre de couleurs detectees par fichier (10/10/2026, Tomyn : "toutes stp") - 3
                # primaires fixes + les melanges auto-detectes juste au-dessus ; affiche ici dans le
                # journal (deja visible a l'ecran pendant le lot, pas besoin d'ouvrir le .log).
                Ecrire-Journal "OK : $cheminSortie (3 primaires + $nombreMelanges melange(s) detecte(s))"
            } catch {
                # Un fichier en echec ne doit pas arreter le lot (decide avec Tomyn) - note et
                # continue sur le suivant.
                $echecs.Add("$nomCourt : $_")
                Ajouter-LigneHistorique $nomTrio $fichier "ECHEC : $_"
                Ecrire-Journal "ECHEC : $_"
            }
            $barreProgresLot.Value = $i
            Ecrire-Journal ""
        }

        $chronoLot.Stop()
        $dureeLot = $chronoLot.Elapsed
        $dureeTexte = if ($dureeLot.TotalHours -ge 1) {
            "{0:00}h{1:00}m{2:00}s" -f [int]$dureeLot.TotalHours, $dureeLot.Minutes, $dureeLot.Seconds
        } else {
            "{0:00}m{1:00}s" -f $dureeLot.Minutes, $dureeLot.Seconds
        }

        Ecrire-Journal "=== Lot termine en $dureeTexte : $($reussis.Count) reussi(s), $($echecs.Count) echec(s) ==="
        if ($echecs.Count -gt 0) {
            Ecrire-Journal "Fichiers en echec :"
            foreach ($e in $echecs) { Ecrire-Journal "  - $e" }
        }

        if ($dernierCheminSortie) { Mettre-A-Jour-Apercu $pictureApres "apres" $dernierCheminSortie }

        # Export du journal (10/10/2026, Tomyn : "go les amelio") - trace ecrite du lot, pratique si
        # un echec se reproduit plus tard et qu'il faut montrer l'historique. Enregistre a cote du
        # PREMIER fichier traite (jamais bloquant si l'ecriture echoue - dossier en lecture seule,
        # etc.). Capture le texte AVANT cette ligne de journal elle-meme, donc le fichier ne contient
        # pas la mention de sa propre creation - sans consequence.
        try {
            $dossierJournal = [System.IO.Path]::GetDirectoryName((Resolve-Path $fichiers[0]))
            $nomJournal = "lot_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
            $cheminJournal = [System.IO.Path]::Combine($dossierJournal, $nomJournal)
            $txtJournal.Text | Set-Content -Path $cheminJournal -Encoding UTF8 -ErrorAction Stop
            Ecrire-Journal "Journal du lot enregistre : $cheminJournal"
        } catch {
            Ecrire-Journal "(Impossible d'enregistrer le journal du lot sur le disque : $_)"
        }

        # Petit signal sonore a la fin d'un lot (10/10/2026, Tomyn : "go les amelio") - pratique si
        # on lance un gros lot et qu'on s'occupe d'autre chose en attendant. Deux sons differents
        # selon qu'il y a eu des echecs ou non. System.Media fait partie du socle .NET (pas besoin
        # d'Add-Type), mais dans un try/catch par precaution - un son manquant ne doit jamais faire
        # echouer l'affichage du resume qui suit.
        try {
            if ($echecs.Count -gt 0) { [System.Media.SystemSounds]::Exclamation.Play() } else { [System.Media.SystemSounds]::Asterisk.Play() }
        } catch { }

        $messageResume = "Lot termine en $dureeTexte.`r`n`r`nReussis : $($reussis.Count)`r`nEchecs : $($echecs.Count)"
        if ($echecs.Count -gt 0) { $messageResume += "`r`n`r`nVoir le journal pour le detail des echecs." }
        $messageResume += "`r`n`r`nRappel : le dosage est une approximation maison - a verifier avant un gros lot (voir le README)."
        Afficher-Boite $messageResume "Lot termine" "OK" "Info" | Out-Null
    } finally {
        $btnLancer.Enabled = $true
        $btnParcourir.Enabled = $true
        $menuTrio.Enabled = $true
        $btnLotDossier.Enabled = $true
        $btnLotFichiers.Enabled = $true
        $labelProgresLot.Visible = $false
        $barreProgresLot.Visible = $false
    }
}

$btnLotDossier.Add_Click({
    $dialogueDossier = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialogueDossier.Description = "Choisir le dossier contenant les fichiers .3mf a traiter"
    if ($dialogueDossier.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Lancer-LotDepuisDossier $dialogueDossier.SelectedPath
    }
})

$btnLotFichiers.Add_Click({
    $dialogueFichiers = New-Object System.Windows.Forms.OpenFileDialog
    $dialogueFichiers.Filter = "Fichiers 3MF (*.3mf)|*.3mf"
    $dialogueFichiers.Multiselect = $true
    $dialogueFichiers.Title = "Choisir les fichiers .3mf a traiter"
    if ($dialogueFichiers.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $nomTrio = $menuTrio.SelectedItem.ToString()
        $trio = $TRIOS[$nomTrio]
        Afficher-ConfirmationLot $dialogueFichiers.FileNames $nomTrio $trio
    }
})

# Recharge le dernier fichier .3mf utilise (12/10/2026, idee d'amelioration validee "vaut le
# coup") - tous les controles necessaires ($txtFichier, $pictureAvant, Mettre-A-Jour-*) existent
# deja a ce stade. Test-Path d'abord : si le fichier a ete deplace/renomme/supprime depuis, on ne
# fait simplement rien (pas de message d'erreur au demarrage pour si peu).
# 16/10/2026 : -FichierInitial (passerelle depuis Coloriser-STL) passe devant le dernier fichier
# utilise s'il est fourni et existe toujours - c'est le resultat que Tomyn vient d'obtenir dans
# l'autre outil, donc plus pertinent que l'ancien fichier. Sauvegarde aussi comme "dernier fichier"
# pour que ce choix survive au prochain lancement normal (sans argument) de l'outil.
# 16/10/2026 : trace explicite dans le journal de ce qui a ete recu comme -FichierInitial (Tomyn :
# "il prend toujours pas le bon fichier") - permet de verifier d'un coup d'oeil, sans devoir
# deviner, si l'argument arrive bien jusqu'ici depuis Coloriser-STL (et si "oui mais le chemin est
# faux" ou carrement "non, rien recu" - les deux ont la meme consequence visible mais pas la meme
# cause/correction).
if ($FichierInitial) {
    if (Test-Path $FichierInitial) {
        Ecrire-Journal "Fichier initial recu de Coloriser-STL : $FichierInitial"
    } else {
        Ecrire-Journal "Fichier initial recu de Coloriser-STL mais introuvable sur le disque : $FichierInitial"
    }
} else {
    Ecrire-Journal "Aucun fichier initial recu (lancement normal, ou -FichierInitial non transmis) - reprise du dernier fichier utilise si disponible."
}

$fichierADemarrer = $null
if ($FichierInitial -and (Test-Path $FichierInitial)) {
    $fichierADemarrer = $FichierInitial
    Sauvegarder-DernierFichier $fichierADemarrer
} else {
    $dernierFichierCharge = Charger-DernierFichier
    if ($dernierFichierCharge -and (Test-Path $dernierFichierCharge)) { $fichierADemarrer = $dernierFichierCharge }
}
if ($fichierADemarrer) {
    try {
        $txtFichier.Text = $fichierADemarrer
        Mettre-A-Jour-Apercu $pictureAvant "avant" $fichierADemarrer
        Mettre-A-Jour-SelecteurMelanges $fichierADemarrer
        Mettre-A-Jour-AlerteDejaTraite $fichierADemarrer
    } catch { }
}

# Ferme l'ecran de lancement juste avant d'afficher le formulaire principal - tout le travail
# de construction des controles ci-dessus a eu le temps de se faire pendant que le splash etait
# affiche, donc la transition se fait sans trou visible entre les deux fenetres.
try { $splash.Close(); $splash.Dispose() } catch { }

# Meme correctif que Coloriser-STL-GUI (10/10/2026) pour la taille de fenetre : plutot que de
# calculer une taille/position a la main (deux tentatives ratees sur l'autre projet), on maximise
# directement - fiable quel que soit l'ecran/le DPI.
$form.WindowState = "Maximized"
[void]$form.ShowDialog()
