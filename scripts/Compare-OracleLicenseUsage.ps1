[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $BeforeCsv,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $AfterCsv,

    [string[]] $KeyColumns = @('Licence', 'Instance'),

    [string] $OutputCsv = (Join-Path 'reports' ("diff-usage-instances-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [char] $Delimiter = ','
)

<#
    Compare deux rapports CSV quelconques et classe chaque combinaison de
    -KeyColumns observée dans au moins un des deux rapports :

      - NouvelUsage  : absente avant, présente après ;
      - UsageArrete  : présente avant, absente après ;
      - Inchange     : présente dans les deux.

    Une ligne dont l'une des colonnes de -KeyColumns est vide est ignorée
    (une valeur inconnue n'est pas diffusable de façon significative).

    -KeyColumns par défaut à Licence,Instance, pour les rapports produits par
    Export-OracleLicenseUsage.ps1 (comportement historique : « cette licence
    a-t-elle été utilisée sur cette base »). Passer -KeyColumns
    Licence,Instance,Option compare au niveau de l'option/du produit détecté
    (voir la limite de granularité machine/instance décrite dans
    Export-OracleLicenseUsage.ps1 et le README). Le script est générique :
    -KeyColumns Instance,Fonctionnalite compare de la même façon deux
    rapports produits par Get-OracleDatabaseFeatureUsage.ps1.

    Renvoie le code processus 2 si au moins un NouvelUsage est détecté (à
    surveiller en priorité), 0 sinon. Ce code est prévu pour être consommé
    par un ordonnanceur ou une supervision de type Nagios/Centreon, sans que
    ce script ne pousse lui-même de résultat vers un quelconque système de
    supervision.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Une invocation en ligne de commande (ex. depuis un ordonnanceur) passe
# souvent "-KeyColumns Licence,Instance,Option" comme une unique chaîne :
# contrairement à un appel PowerShell natif, la virgule n'y est alors pas
# réinterprétée comme opérateur de construction de tableau. On la découpe
# donc explicitement ici, ce qui ne change rien pour un appel qui fournit
# déjà des éléments séparés.
$KeyColumns = @($KeyColumns | ForEach-Object { $_ -split ',' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })

if ($KeyColumns.Count -eq 0) { throw 'KeyColumns ne peut pas être vide.' }

function Get-UsageKeyMap {
    <#
        Une ligne dont l'une des colonnes de clé est vide est ignorée : une
        valeur inconnue ne peut pas être diffusée de façon significative à la
        granularité demandée (ex. une option non identifiée avec
        -KeyColumns Licence,Instance,Option).
    #>
    param(
        [Parameter(Mandatory)] [object[]] $Rows,
        [Parameter(Mandatory)] [string[]] $Columns
    )

    # Séparateur de contrôle (0x1F), improbable dans une valeur métier, pour
    # combiner sans ambiguïté les colonnes de clé en une seule chaîne.
    $separator = [char] 0x1F
    $map = [Collections.Generic.Dictionary[string, string[]]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Rows) {
        $values = @($Columns | ForEach-Object { [string] $row.$_ })
        if ($values | Where-Object { [string]::IsNullOrWhiteSpace($_) }) { continue }
        $key = $values -join $separator
        if (-not $map.ContainsKey($key)) { $map[$key] = $values }
    }
    return $map
}

$beforeRows = @(Import-Csv -LiteralPath $BeforeCsv -Delimiter $Delimiter)
$afterRows = @(Import-Csv -LiteralPath $AfterCsv -Delimiter $Delimiter)

$beforeMap = Get-UsageKeyMap -Rows $beforeRows -Columns $KeyColumns
$afterMap = Get-UsageKeyMap -Rows $afterRows -Columns $KeyColumns

$allKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $beforeMap.Keys) { [void] $allKeys.Add($key) }
foreach ($key in $afterMap.Keys) { [void] $allKeys.Add($key) }

$results = [Collections.Generic.List[object]]::new()
foreach ($key in $allKeys) {
    $wasPresent = $beforeMap.ContainsKey($key)
    $isPresent = $afterMap.ContainsKey($key)
    $values = if ($isPresent) { $afterMap[$key] } else { $beforeMap[$key] }

    $evenement = if (-not $wasPresent -and $isPresent) { 'NouvelUsage' }
        elseif ($wasPresent -and -not $isPresent) { 'UsageArrete' }
        else { 'Inchange' }

    $entry = [ordered] @{}
    for ($i = 0; $i -lt $KeyColumns.Count; $i++) { $entry[$KeyColumns[$i]] = $values[$i] }
    $entry['PresentJ1'] = if ($wasPresent) { 'Oui' } else { 'Non' }
    $entry['PresentJ2'] = if ($isPresent) { 'Oui' } else { 'Non' }
    $entry['Evenement'] = $evenement

    $results.Add([pscustomobject] $entry)
}

$eventOrder = @{ NouvelUsage = 0; UsageArrete = 1; Inchange = 2 }
$sortProperties = @(@{ Expression = { $eventOrder[$_.Evenement] } }) + $KeyColumns
$sortedResults = $results | Sort-Object -Property $sortProperties

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$sortedResults | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

$newUsages = @($results | Where-Object Evenement -eq 'NouvelUsage')
$stoppedUsages = @($results | Where-Object Evenement -eq 'UsageArrete')
Write-Host "Comparaison terminée : $($newUsages.Count) nouvel(aux) usage(s), $($stoppedUsages.Count) arrêt(s) d'usage."
Write-Host "Rapport : $OutputCsv"

if ($newUsages.Count -gt 0) { exit 2 }
exit 0
