[CmdletBinding(DefaultParameterSetName = 'Api')]
param(
    [Parameter(ParameterSetName = 'Csv')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $FlexeraCsv,

    [Parameter(ParameterSetName = 'Api')]
    [ValidatePattern('^https://')]
    [uri] $ApiUri = $(if ($env:FLEXERA_LICENSE_API_URL) { $env:FLEXERA_LICENSE_API_URL } else { $env:FLEXERA_ORACLE_REPORT_URL }),

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ColumnMap,

    [string] $OutputCsv = (Join-Path 'reports' ("controle-ecarts-oracle-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter(ParameterSetName = 'Api')]
    [string] $RawExportCsv,

    [char] $Delimiter = ',',
    [string] $Culture = [Globalization.CultureInfo]::CurrentCulture.Name,
    [decimal] $SeuilAlerte = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($SeuilAlerte -lt 0) { throw 'SeuilAlerte doit être supérieur ou égal à zéro.' }
if ($PSCmdlet.ParameterSetName -eq 'Api' -and $null -eq $ApiUri) {
    throw "Définissez FLEXERA_LICENSE_API_URL ou utilisez -ApiUri avec un endpoint ITAM qui expose réellement les positions de licences."
}

function Get-RequiredEnvironmentVariable {
    param([Parameter(Mandatory)][string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "La variable d'environnement $Name est obligatoire en mode API."
    }
    return $value
}

function Get-FlexeraAccessToken {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = Get-RequiredEnvironmentVariable 'FLEXERA_CLIENT_ID'
        client_secret = Get-RequiredEnvironmentVariable 'FLEXERA_CLIENT_SECRET'
    }
    if ($env:FLEXERA_AUDIENCE) { $body.audience = $env:FLEXERA_AUDIENCE }
    if ($env:FLEXERA_SCOPE) { $body.scope = $env:FLEXERA_SCOPE }

    $tokenUrl = if ($env:FLEXERA_TOKEN_URL) { $env:FLEXERA_TOKEN_URL } else { 'https://login.flexera.com/oidc/token' }
    $response = Invoke-RestMethod -Method Post `
        -Uri $tokenUrl `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $body
    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw 'La réponse OAuth Flexera ne contient pas de jeton access_token.'
    }
    return [string] $response.access_token
}

function Get-CollectionFromResponse {
    param([Parameter(Mandatory)] $Response)

    if ($Response -is [array]) { return @($Response) }
    foreach ($property in 'data', 'items', 'results', 'records') {
        if ($Response.PSObject.Properties.Name -contains $property) {
            return @($Response.$property)
        }
    }
    return @($Response)
}

function Get-NextPageUri {
    param([Parameter(Mandatory)] $Response)

    foreach ($property in 'next', 'nextLink', 'next_page') {
        if (($Response.PSObject.Properties.Name -contains $property) -and $Response.$property) {
            return [string] $Response.$property
        }
    }
    foreach ($container in 'links', 'pagination', 'meta') {
        if (($Response.PSObject.Properties.Name -contains $container) -and $Response.$container) {
            $nested = $Response.$container
            if (($nested.PSObject.Properties.Name -contains 'next') -and $nested.next) {
                return [string] $nested.next
            }
        }
    }
    return $null
}

function Resolve-SourceColumn {
    param(
        [Parameter(Mandatory)] $Sample,
        [Parameter(Mandatory)] [string] $Target,
        [Parameter(Mandatory)] [string[]] $Candidates
    )

    $available = @($Sample.PSObject.Properties.Name)
    foreach ($candidate in $Candidates) {
        $match = $available | Where-Object { $_ -ieq $candidate } | Select-Object -First 1
        if ($match) { return [string] $match }
    }
    throw "Impossible d'identifier automatiquement '$Target'. Colonnes reçues : $($available -join ', '). Utilisez -ColumnMap."
}

function Get-FlexeraApiRows {
    param([Parameter(Mandatory)][uri] $Uri)

    $token = Get-FlexeraAccessToken
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $origin = $Uri.Host
    $nextUri = $Uri.AbsoluteUri
    $rows = [Collections.Generic.List[object]]::new()

    for ($page = 1; $page -le 1000 -and $nextUri; $page++) {
        $response = Invoke-RestMethod -Method Get -Uri $nextUri -Headers $headers
        foreach ($row in (Get-CollectionFromResponse $response)) { $rows.Add($row) }

        $next = Get-NextPageUri $response
        if (-not $next) { $nextUri = $null; continue }
        $resolved = [uri]::new([uri] $nextUri, $next)
        if ($resolved.Scheme -ne 'https' -or $resolved.Host -ne $origin) {
            throw "La pagination a retourné une URL non sûre : $resolved"
        }
        $nextUri = $resolved.AbsoluteUri
    }
    if ($nextUri) { throw 'Pagination interrompue après 1 000 pages.' }
    return $rows.ToArray()
}

function Get-RequiredMappedValue {
    param(
        [Parameter(Mandatory)] $Row,
        [Parameter(Mandatory)] [string] $SourceColumn,
        [Parameter(Mandatory)] [string] $TargetName,
        [Parameter(Mandatory)] [int] $RowNumber
    )

    if ($Row.PSObject.Properties.Name -notcontains $SourceColumn) {
        throw "Colonne '$SourceColumn' absente (mapping $TargetName)."
    }
    $value = $Row.$SourceColumn
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string] $value)) {
        throw "Valeur $TargetName vide à la ligne $RowNumber."
    }
    return $value
}

function ConvertTo-DecimalValue {
    param(
        [Parameter(Mandatory)] $Value,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [int] $RowNumber,
        [Parameter(Mandatory)] [Globalization.CultureInfo] $NumberCulture
    )

    $number = 0D
    $styles = [Globalization.NumberStyles]::Number
    if (-not [decimal]::TryParse([string] $Value, $styles, $NumberCulture, [ref] $number)) {
        throw "Valeur non numérique pour $Name à la ligne $RowNumber : '$Value'."
    }
    return $number
}

if ($PSCmdlet.ParameterSetName -eq 'Api') {
    $sourceRows = @(Get-FlexeraApiRows -Uri $ApiUri)
    if ($RawExportCsv) {
        $rawDirectory = Split-Path -Parent $RawExportCsv
        if ($rawDirectory) { New-Item -ItemType Directory -Path $rawDirectory -Force | Out-Null }
        $sourceRows | Export-Csv -LiteralPath $RawExportCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
    }
}
else {
    $sourceRows = @(Import-Csv -LiteralPath $FlexeraCsv -Delimiter $Delimiter)
}

if ($sourceRows.Count -eq 0) { throw 'La source Flexera ne contient aucune ligne.' }
$map = if ($ColumnMap) {
    Get-Content -LiteralPath $ColumnMap -Raw | ConvertFrom-Json
}
else {
    [pscustomobject] @{
        Licence = Resolve-SourceColumn $sourceRows[0] 'Licence' @('LicenseName', 'LicenceName', 'name', 'license_name', 'licenseName')
        Metrique = Resolve-SourceColumn $sourceRows[0] 'Metrique' @('Metric', 'LicenseMetric', 'metric_name', 'metricName')
        DroitsAcquis = Resolve-SourceColumn $sourceRows[0] 'DroitsAcquis' @('PurchasedEntitlements', 'EntitlementCount', 'Purchased', 'entitlements', 'purchased_count')
        Consommation = Resolve-SourceColumn $sourceRows[0] 'Consommation' @('ConsumedEntitlements', 'Consumption', 'Consumed', 'consumed_count', 'consumed')
    }
    Write-Verbose "Mapping détecté : $($map | ConvertTo-Json -Compress)"
}
foreach ($requiredMap in 'Licence', 'Metrique', 'DroitsAcquis', 'Consommation') {
    if (($map.PSObject.Properties.Name -notcontains $requiredMap) -or
        [string]::IsNullOrWhiteSpace([string] $map.$requiredMap)) {
        throw "Le mapping '$requiredMap' est obligatoire."
    }
}
$numberCulture = [Globalization.CultureInfo]::GetCultureInfo($Culture)
$normalizedRows = @(for ($index = 0; $index -lt $sourceRows.Count; $index++) {
    $rowNumber = $index + 2
    $row = $sourceRows[$index]
    $licence = Get-RequiredMappedValue $row $map.Licence 'Licence' $rowNumber
    $metric = Get-RequiredMappedValue $row $map.Metrique 'Metrique' $rowNumber
    $rightsRaw = Get-RequiredMappedValue $row $map.DroitsAcquis 'DroitsAcquis' $rowNumber
    $consumptionRaw = Get-RequiredMappedValue $row $map.Consommation 'Consommation' $rowNumber
    $rights = ConvertTo-DecimalValue $rightsRaw 'DroitsAcquis' $rowNumber $numberCulture
    $consumption = ConvertTo-DecimalValue $consumptionRaw 'Consommation' $rowNumber $numberCulture
    [pscustomobject] @{
        Licence      = [string] $licence
        Metrique     = [string] $metric
        DroitsAcquis = $rights
        Consommation = $consumption
    }
})

# Un export peut contenir plusieurs lignes pour une même licence (par exemple
# plusieurs pools). Le contrôle se fait sur le total par licence et métrique.
$results = @($normalizedRows | Group-Object Licence, Metrique | ForEach-Object {
    $rights = ($_.Group | Measure-Object DroitsAcquis -Sum).Sum
    $consumption = ($_.Group | Measure-Object Consommation -Sum).Sum
    $gap = $rights - $consumption
    $status = if ($gap -lt -$SeuilAlerte) { 'Déficit' } elseif ($gap -gt $SeuilAlerte) { 'Surplus' } else { 'Équilibre' }
    $coverage = if ($consumption -eq 0) { $null } else { [math]::Round(($rights / $consumption) * 100, 2) }

    [pscustomobject] [ordered] @{
        Licence            = $_.Group[0].Licence
        Metrique           = $_.Group[0].Metrique
        DroitsAcquis       = $rights
        Consommation       = $consumption
        Ecart              = $gap
        Statut             = $status
        Risque             = if ($gap -lt 0) { [math]::Abs($gap) } else { 0 }
        TauxCouverturePct  = $coverage
    }
})

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$results | Sort-Object @{ Expression = { $_.Statut -ne 'Déficit' } }, @{ Expression = 'Risque'; Descending = $true } |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

$deficits = @($results | Where-Object Statut -eq 'Déficit')
Write-Host "Contrôle terminé : $($results.Count) licence(s), $($deficits.Count) déficit(s)."
Write-Host "Rapport : $OutputCsv"
if ($deficits.Count -gt 0) { exit 2 }
exit 0
