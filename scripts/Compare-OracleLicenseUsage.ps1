[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $BeforeCsv,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $AfterCsv,

    [string] $OutputCsv = (Join-Path 'reports' ("diff-usage-instances-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [char] $Delimiter = ','
)

<#
    Compare deux rapports produits par Export-OracleLicenseUsage.ps1 (colonnes
    Licence, Instance) et classe chaque couple licence/instance observé dans
    au moins un des deux rapports :

      - NouvelUsage  : absent avant, présent après (licence désormais
        utilisée sur cette base) ;
      - UsageArrete  : présent avant, absent après ;
      - Inchange     : présent dans les deux.

    Renvoie le code processus 2 si au moins un NouvelUsage est détecté (à
    surveiller en priorité), 0 sinon. Ce code est prévu pour être consommé
    par un ordonnanceur ou une supervision de type Nagios/Centreon, sans que
    ce script ne pousse lui-même de résultat vers un quelconque système de
    supervision.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UsageKeySet {
    param([Parameter(Mandatory)] [object[]] $Rows)

    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Rows) {
        if ([string]::IsNullOrWhiteSpace($row.Licence) -or [string]::IsNullOrWhiteSpace($row.Instance)) { continue }
        [void] $set.Add("$($row.Licence)|$($row.Instance)")
    }
    return $set
}

$beforeRows = @(Import-Csv -LiteralPath $BeforeCsv -Delimiter $Delimiter)
$afterRows = @(Import-Csv -LiteralPath $AfterCsv -Delimiter $Delimiter)

$beforeKeys = Get-UsageKeySet $beforeRows
$afterKeys = Get-UsageKeySet $afterRows

$allKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $beforeKeys) { [void] $allKeys.Add($key) }
foreach ($key in $afterKeys) { [void] $allKeys.Add($key) }

$results = [Collections.Generic.List[object]]::new()
foreach ($key in $allKeys) {
    $separatorIndex = $key.IndexOf('|')
    $licence = $key.Substring(0, $separatorIndex)
    $instance = $key.Substring($separatorIndex + 1)
    $wasPresent = $beforeKeys.Contains($key)
    $isPresent = $afterKeys.Contains($key)

    $evenement = if (-not $wasPresent -and $isPresent) { 'NouvelUsage' }
        elseif ($wasPresent -and -not $isPresent) { 'UsageArrete' }
        else { 'Inchange' }

    $results.Add([pscustomobject] [ordered] @{
        Licence   = $licence
        Instance  = $instance
        PresentJ1 = if ($wasPresent) { 'Oui' } else { 'Non' }
        PresentJ2 = if ($isPresent) { 'Oui' } else { 'Non' }
        Evenement = $evenement
    })
}

$eventOrder = @{ NouvelUsage = 0; UsageArrete = 1; Inchange = 2 }
$sortedResults = $results | Sort-Object @{ Expression = { $eventOrder[$_.Evenement] } }, Licence, Instance

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$sortedResults | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

$newUsages = @($results | Where-Object Evenement -eq 'NouvelUsage')
$stoppedUsages = @($results | Where-Object Evenement -eq 'UsageArrete')
Write-Host "Comparaison terminée : $($newUsages.Count) nouvel(aux) usage(s), $($stoppedUsages.Count) arrêt(s) d'usage."
Write-Host "Rapport : $OutputCsv"

if ($newUsages.Count -gt 0) { exit 2 }
exit 0
