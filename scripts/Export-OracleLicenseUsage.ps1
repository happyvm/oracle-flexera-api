[CmdletBinding(DefaultParameterSetName = 'Api')]
param(
    [Parameter(ParameterSetName = 'Api')]
    [ValidatePattern('^https://')]
    [uri] $ApiBaseUri = $(if ($env:FLEXERA_API_BASE_URL) { $env:FLEXERA_API_BASE_URL }),

    [Parameter(ParameterSetName = 'Api')]
    [string] $OrgId = $env:FLEXERA_ORG_ID,

    [Parameter(ParameterSetName = 'Json', Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $LicensesJson,

    [Parameter(ParameterSetName = 'Json', Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $ConsumptionJsonDir,

    [string] $PublisherFilter = 'Oracle',

    [string] $OutputCsv = (Join-Path 'reports' ("usage-instances-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [char] $Delimiter = ','
)

<#
    Exporte, pour chaque licence dont l'éditeur correspond à -PublisherFilter
    (« Oracle » par défaut), la liste des instances (bases de données, le
    plus souvent) qui consomment effectivement cette licence à l'instant de
    l'extraction. S'appuie sur l'API FNMS v1 de Flexera One :

      GET {ApiBaseUri}/fnms/v1/orgs/{OrgId}/licenses
      GET {ApiBaseUri}/fnms/v1/orgs/{OrgId}/licenses/{licenseId}/consumption

    Ce rapport est la matière première de Compare-OracleLicenseUsage.ps1, qui
    diffuse deux extractions pour détecter les nouveaux usages ou arrêts
    d'usage d'une licence sur une base entre deux dates.

    Le mode -LicensesJson/-ConsumptionJsonDir permet de rejouer une capture
    hors-ligne (tests, débogage) sans appeler l'API réelle : -LicensesJson
    pointe vers le tableau JSON tel que retourné par /licenses, et
    -ConsumptionJsonDir contient un fichier "<licenseId>.json" par licence
    concernée, contenant le tableau JSON tel que retourné par
    /licenses/{licenseId}/consumption (propriété "values").
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Api' -and ($null -eq $ApiBaseUri -or [string]::IsNullOrWhiteSpace($OrgId))) {
    throw 'Définissez FLEXERA_API_BASE_URL et FLEXERA_ORG_ID (ou -ApiBaseUri/-OrgId), ou utilisez -LicensesJson/-ConsumptionJsonDir.'
}

function Test-PublisherMatch {
    param([Parameter(Mandatory)] $License, [Parameter(Mandatory)] [string] $Filter)

    $publisher = if ($License.PSObject.Properties.Name -contains 'company') { [string] $License.company.name } else { '' }
    $name = if ($License.PSObject.Properties.Name -contains 'name') { [string] $License.name } else { '' }
    return ($publisher -like "*$Filter*") -or ($name -like "*$Filter*")
}

if ($PSCmdlet.ParameterSetName -eq 'Api') {
    Import-Module (Join-Path $PSScriptRoot 'FlexeraApiClient.psm1') -Force
    $token = Get-FlexeraAccessToken
    $licensesUri = [uri]::new($ApiBaseUri, "/fnms/v1/orgs/$OrgId/licenses")
    $licenses = @(Get-FlexeraPagedValues -Uri $licensesUri -Token $token)
}
else {
    $licenses = @(Get-Content -LiteralPath $LicensesJson -Raw | ConvertFrom-Json)
}

$matchedLicenses = @($licenses | Where-Object { Test-PublisherMatch $_ $PublisherFilter })
if ($matchedLicenses.Count -eq 0) {
    throw "Aucune licence ne correspond au filtre éditeur '$PublisherFilter'."
}

$extractedAt = Get-Date -Format 'o'
$rows = [Collections.Generic.List[object]]::new()

foreach ($license in $matchedLicenses) {
    $licenseId = [string] $license.id
    $licenseName = [string] $license.name
    $licenseType = if ($license.PSObject.Properties.Name -contains 'type') { [string] $license.type } else { '' }

    if ($PSCmdlet.ParameterSetName -eq 'Api') {
        $consumptionUri = [uri]::new($ApiBaseUri, "/fnms/v1/orgs/$OrgId/licenses/$licenseId/consumption")
        $consumptionRecords = @(Get-FlexeraPagedValues -Uri $consumptionUri -Token $token)
    }
    else {
        $consumptionFile = Join-Path $ConsumptionJsonDir "$licenseId.json"
        $consumptionRecords = if (Test-Path -LiteralPath $consumptionFile -PathType Leaf) {
            @(Get-Content -LiteralPath $consumptionFile -Raw | ConvertFrom-Json)
        }
        else {
            @()
        }
    }

    # Seules les consommations rattachées à une instance (typiquement une
    # base de données) répondent au besoin « cette licence a-t-elle été
    # utilisée sur cette base ». Les consommations au seul niveau machine,
    # sans instance identifiée, ne sont pas reportées ici.
    $instanceKeys = [Collections.Generic.HashSet[string]]::new()
    foreach ($record in $consumptionRecords) {
        if ($record.PSObject.Properties.Name -notcontains 'instances') { continue }
        $machine = if ($record.PSObject.Properties.Name -contains 'device') { [string] $record.device.name } else { '' }
        foreach ($instance in @($record.instances)) {
            $instanceName = [string] $instance.name
            if ([string]::IsNullOrWhiteSpace($instanceName)) { continue }
            $key = "$licenseId|$instanceName|$machine"
            if (-not $instanceKeys.Add($key)) { continue }

            $rows.Add([pscustomobject] [ordered] @{
                Licence        = $licenseName
                LicenseId      = $licenseId
                Type           = $licenseType
                Instance       = $instanceName
                Machine        = $machine
                DateExtraction = $extractedAt
            })
        }
    }
}

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$rows | Sort-Object Licence, Instance |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

Write-Host "Export terminé : $($rows.Count) couple(s) licence/instance sur $($matchedLicenses.Count) licence(s) '$PublisherFilter'."
Write-Host "Rapport : $OutputCsv"
