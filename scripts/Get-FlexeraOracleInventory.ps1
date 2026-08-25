[CmdletBinding(DefaultParameterSetName = 'Api')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Api')]
    [string] $OrganizationId,

    [Parameter(ParameterSetName = 'Api')]
    [ValidateSet('NAM', 'EU', 'APAC')]
    [string] $Zone = $(if ($env:FLEXERA_ZONE) { $env:FLEXERA_ZONE } else { 'EU' }),

    [Parameter(ParameterSetName = 'Api')]
    [uri] $BaseUri,

    [Parameter(ParameterSetName = 'Api')]
    [string] $ReportId,

    [Parameter(ParameterSetName = 'Api')]
    [string] $ReportName = 'Oracle Server Worksheet for Oracle Database',

    [Parameter(ParameterSetName = 'Api')]
    [switch] $Async,

    [Parameter(ParameterSetName = 'Api')]
    [ValidateRange(1, 10000)]
    [int] $PageSize = 1000,

    [Parameter(ParameterSetName = 'Api')]
    [string] $SearchText,

    [Parameter(ParameterSetName = 'Api')]
    [ValidateRange(1, 3600)]
    [int] $PollTimeoutSeconds = 600,

    [Parameter(ParameterSetName = 'Api')]
    [ValidateRange(1, 300)]
    [int] $PollIntervalSeconds = 5,

    [Parameter(Mandatory, ParameterSetName = 'Csv')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ReportCsv,

    [string] $OutputCsv = (Join-Path 'reports' ("oracle-options-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [Parameter(ParameterSetName = 'Api')]
    [string] $RawReportCsv,

    [char] $Delimiter = ',',

    [switch] $OnlyOptions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FlexeraZoneConfig {
    param([Parameter(Mandatory)][string] $ZoneName)

    switch ($ZoneName.ToUpperInvariant()) {
        'NAM'  { return [pscustomobject]@{ Api = 'https://api.flexera.com'; Login = 'https://login.flexera.com' } }
        'EU'   { return [pscustomobject]@{ Api = 'https://api.flexera.eu';  Login = 'https://login.flexera.eu' } }
        'APAC' { return [pscustomobject]@{ Api = 'https://api.flexera.au';  Login = 'https://login.flexera.au' } }
        default { throw "Zone Flexera non prise en charge : $ZoneName" }
    }
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
    param([Parameter(Mandatory)][string] $DefaultLoginBaseUri)

    # Un API Refresh Token créé dans Flexera One > API Credentials est le mode
    # utilisateur officiel. Il est prioritaire lorsqu'il est défini. Le mode
    # service account reste disponible pour les automatisations techniques.
    if (-not [string]::IsNullOrWhiteSpace([string] $env:FLEXERA_REFRESH_TOKEN)) {
        $body = @{
            grant_type    = 'refresh_token'
            refresh_token = [string] $env:FLEXERA_REFRESH_TOKEN
        }
    }
    else {
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = Get-RequiredEnvironmentVariable 'FLEXERA_CLIENT_ID'
            client_secret = Get-RequiredEnvironmentVariable 'FLEXERA_CLIENT_SECRET'
        }
        if ($env:FLEXERA_AUDIENCE) { $body.audience = $env:FLEXERA_AUDIENCE }
        if ($env:FLEXERA_SCOPE) { $body.scope = $env:FLEXERA_SCOPE }
    }

    $tokenUrl = if ($env:FLEXERA_TOKEN_URL) {
        $env:FLEXERA_TOKEN_URL
    }
    else {
        "$DefaultLoginBaseUri/oidc/token"
    }

    $response = Invoke-RestMethod -Method Post `
        -Uri $tokenUrl `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $body

    if ([string]::IsNullOrWhiteSpace([string] $response.access_token)) {
        throw 'La réponse OAuth Flexera ne contient pas de jeton access_token.'
    }
    return [string] $response.access_token
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)][string[]] $Candidates
    )

    if ($null -eq $Object) { return $null }
    $properties = @($Object.PSObject.Properties)
    foreach ($candidate in $Candidates) {
        $property = $properties | Where-Object { $_.Name -ieq $candidate } | Select-Object -First 1
        if ($property) { return $property.Value }
    }
    return $null
}

function Get-CollectionFromResponse {
    param([Parameter(Mandatory)] $Response)

    if ($Response -is [array]) { return @($Response) }

    foreach ($property in 'rows', 'records', 'items', 'results', 'values', 'data', 'value') {
        if ($Response.PSObject.Properties.Name -contains $property) {
            $value = $Response.$property
            if ($value -is [array]) { return @($value) }
            if ($null -ne $value -and $value -isnot [string]) {
                foreach ($nestedProperty in 'rows', 'records', 'items', 'results', 'values', 'data', 'value') {
                    if ($value.PSObject.Properties.Name -contains $nestedProperty) {
                        return @(Get-CollectionFromResponse -Response $value)
                    }
                }
            }
        }
    }

    return @($Response)
}

function Get-NextPageUri {
    param([Parameter(Mandatory)] $Response)

    foreach ($property in 'nextPage', 'next', 'nextLink', 'next_page') {
        $value = Get-PropertyValue -Object $Response -Candidates @($property)
        if ($value) { return [string] $value }
    }

    foreach ($containerName in 'links', 'pagination', 'meta') {
        $container = Get-PropertyValue -Object $Response -Candidates @($containerName)
        if ($container) {
            $next = Get-PropertyValue -Object $container -Candidates @('nextPage', 'next', 'nextLink', 'next_page')
            if ($next) { return [string] $next }
        }
    }
    return $null
}

function Invoke-FlexeraPagedGet {
    param(
        [Parameter(Mandatory)][uri] $Uri,
        [Parameter(Mandatory)][hashtable] $Headers
    )

    $origin = $Uri.Host
    $nextUri = $Uri.AbsoluteUri
    $rows = [Collections.Generic.List[object]]::new()

    for ($page = 1; $page -le 1000 -and $nextUri; $page++) {
        $response = Invoke-RestMethod -Method Get -Uri $nextUri -Headers $Headers
        foreach ($row in (Get-CollectionFromResponse -Response $response)) { $rows.Add($row) }

        $next = Get-NextPageUri -Response $response
        if (-not $next) {
            $nextUri = $null
            continue
        }

        $resolved = [uri]::new([uri] $nextUri, $next)
        if ($resolved.Scheme -ne 'https' -or $resolved.Host -ne $origin) {
            throw "La pagination a retourné une URL non sûre : $resolved"
        }
        $nextUri = $resolved.AbsoluteUri
    }

    if ($nextUri) { throw 'Pagination interrompue après 1 000 pages.' }
    return $rows.ToArray()
}

function Resolve-FlexeraReportId {
    param(
        [Parameter(Mandatory)][uri] $ReportsUri,
        [Parameter(Mandatory)][hashtable] $Headers,
        [Parameter(Mandatory)][string] $RequestedName
    )

    $reports = @(Invoke-FlexeraPagedGet -Uri $ReportsUri -Headers $Headers)
    $matches = @($reports | Where-Object {
        $name = Get-PropertyValue -Object $_ -Candidates @('name', 'title', 'reportName', 'report_name')
        $name -and ([string] $name).Trim() -ieq $RequestedName.Trim()
    })

    if ($matches.Count -eq 0) {
        $available = @($reports | ForEach-Object {
            Get-PropertyValue -Object $_ -Candidates @('name', 'title', 'reportName', 'report_name')
        } | Where-Object { $_ } | Sort-Object -Unique)
        throw "Rapport '$RequestedName' introuvable. Rapports visibles : $($available -join ', ')"
    }
    if ($matches.Count -gt 1) {
        throw "Plusieurs rapports portent le nom '$RequestedName'. Utilisez -ReportId pour lever l'ambiguïté."
    }

    $id = Get-PropertyValue -Object $matches[0] -Candidates @('id', 'reportId', 'report_id')
    if ([string]::IsNullOrWhiteSpace([string] $id)) {
        throw "Le rapport '$RequestedName' ne contient pas d'identifiant exploitable."
    }
    return [string] $id
}

function Invoke-FlexeraReportSync {
    param(
        [Parameter(Mandatory)][uri] $ReportBaseUri,
        [Parameter(Mandatory)][hashtable] $Headers,
        [Parameter(Mandatory)][int] $Limit,
        [string] $FilterText
    )

    $executeUri = "$($ReportBaseUri.AbsoluteUri.TrimEnd('/'))/execute"
    $origin = $ReportBaseUri.Host
    $rows = [Collections.Generic.List[object]]::new()
    $skipToken = $null
    $nextPage = $null

    for ($page = 1; $page -le 1000; $page++) {
        if ($nextPage) {
            $requestUri = [uri]::new([uri] $executeUri, $nextPage)
            if ($requestUri.Scheme -ne 'https' -or $requestUri.Host -ne $origin) {
                throw "La pagination du rapport a retourné une URL non sûre : $requestUri"
            }
        }
        else {
            $query = "limit=$Limit"
            if (-not [string]::IsNullOrWhiteSpace($FilterText)) {
                $query += "&searchText=$([uri]::EscapeDataString($FilterText))"
            }
            if (-not [string]::IsNullOrWhiteSpace([string] $skipToken)) {
                $query += "&skipToken=$([uri]::EscapeDataString([string] $skipToken))"
            }
            $requestUri = [uri] "$executeUri`?$query"
        }

        $response = Invoke-RestMethod -Method Get -Uri $requestUri -Headers $Headers
        foreach ($row in (Get-CollectionFromResponse -Response $response)) { $rows.Add($row) }

        $nextPage = Get-NextPageUri -Response $response
        if ($nextPage) { continue }

        $skipToken = Get-PropertyValue -Object $response -Candidates @('skipToken', 'nextSkipToken', 'next_skip_token')
        if (-not $skipToken) {
            foreach ($containerName in 'pagination', 'meta') {
                $container = Get-PropertyValue -Object $response -Candidates @($containerName)
                if ($container) {
                    $skipToken = Get-PropertyValue -Object $container -Candidates @('skipToken', 'nextSkipToken', 'next_skip_token')
                    if ($skipToken) { break }
                }
            }
        }
        if (-not $skipToken) { return $rows.ToArray() }
    }

    throw 'Pagination du rapport interrompue après 1 000 pages.'
}

function Invoke-FlexeraReportAsync {
    param(
        [Parameter(Mandatory)][uri] $ReportBaseUri,
        [Parameter(Mandatory)][hashtable] $Headers,
        [Parameter(Mandatory)][int] $TimeoutSeconds,
        [Parameter(Mandatory)][int] $IntervalSeconds
    )

    $startUri = "$($ReportBaseUri.AbsoluteUri.TrimEnd('/'))/execute-async"
    $job = Invoke-RestMethod -Method Post -Uri $startUri -Headers $Headers -ContentType 'application/json'
    $jobId = Get-PropertyValue -Object $job -Candidates @('jobId', 'job_id', 'id')
    if ([string]::IsNullOrWhiteSpace([string] $jobId)) {
        throw "Flexera n'a pas retourné de jobId pour l'exécution asynchrone : $($job | ConvertTo-Json -Depth 8 -Compress)"
    }

    $statusUri = "$startUri/$([uri]::EscapeDataString([string] $jobId))/status"
    $retrieveUri = "$startUri/$([uri]::EscapeDataString([string] $jobId))/retrieve"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $statusResponse = Invoke-RestMethod -Method Get -Uri $statusUri -Headers $Headers
        $status = Get-PropertyValue -Object $statusResponse -Candidates @('status', 'state', 'jobStatus', 'job_status')
        $normalizedStatus = if ($status) { ([string] $status).Trim().ToLowerInvariant() } else { '' }

        if ($normalizedStatus -in @('completed', 'complete', 'succeeded', 'success', 'ready', 'finished')) {
            return Invoke-RestMethod -Method Get -Uri $retrieveUri -Headers $Headers
        }
        if ($normalizedStatus -in @('failed', 'error', 'cancelled', 'canceled')) {
            throw "L'exécution du rapport Flexera a échoué avec l'état '$status'."
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    throw "Délai dépassé après $TimeoutSeconds seconde(s) pendant l'exécution du rapport Flexera."
}

function Resolve-SourceColumn {
    param(
        [Parameter(Mandatory)] $Sample,
        [Parameter(Mandatory)][string] $Target,
        [Parameter(Mandatory)][string[]] $Candidates,
        [switch] $Optional
    )

    $available = @($Sample.PSObject.Properties.Name)
    foreach ($candidate in $Candidates) {
        $match = $available | Where-Object { $_ -ieq $candidate } | Select-Object -First 1
        if ($match) { return [string] $match }
    }

    if ($Optional) { return $null }
    throw "Impossible d'identifier automatiquement '$Target'. Colonnes reçues : $($available -join ', ')."
}

function Get-OptionalValue {
    param($Row, [string] $Column)
    if ([string]::IsNullOrWhiteSpace($Column)) { return $null }
    if ($Row.PSObject.Properties.Name -notcontains $Column) { return $null }
    return $Row.$Column
}

function Split-OracleOptions {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) { return @() }
    return @(([string] $Value -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Sort-Object -Unique)
}

if ($PSCmdlet.ParameterSetName -eq 'Api') {
    $zoneConfig = Get-FlexeraZoneConfig -ZoneName $Zone
    $apiRoot = if ($BaseUri) { $BaseUri.AbsoluteUri.TrimEnd('/') } else { $zoneConfig.Api }
    if (-not $apiRoot.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BaseUri doit utiliser HTTPS.'
    }

    $token = Get-FlexeraAccessToken -DefaultLoginBaseUri $zoneConfig.Login
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $reportsUri = [uri] "$apiRoot/fnms/v1/orgs/$([uri]::EscapeDataString($OrganizationId))/reports"

    $resolvedReportId = if ($ReportId) {
        $ReportId
    }
    else {
        Resolve-FlexeraReportId -ReportsUri $reportsUri -Headers $headers -RequestedName $ReportName
    }

    $reportBaseUri = [uri] "$($reportsUri.AbsoluteUri.TrimEnd('/'))/$([uri]::EscapeDataString($resolvedReportId))"
    $sourceRows = if ($Async) {
        $response = Invoke-FlexeraReportAsync -ReportBaseUri $reportBaseUri -Headers $headers -TimeoutSeconds $PollTimeoutSeconds -IntervalSeconds $PollIntervalSeconds
        @(Get-CollectionFromResponse -Response $response)
    }
    else {
        @(Invoke-FlexeraReportSync -ReportBaseUri $reportBaseUri -Headers $headers -Limit $PageSize -FilterText $SearchText)
    }

    if ($RawReportCsv) {
        $rawDirectory = Split-Path -Parent $RawReportCsv
        if ($rawDirectory) { New-Item -ItemType Directory -Path $rawDirectory -Force | Out-Null }
        $sourceRows | Export-Csv -LiteralPath $RawReportCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
    }
}
else {
    $sourceRows = @(Import-Csv -LiteralPath $ReportCsv -Delimiter $Delimiter)
}

if ($sourceRows.Count -eq 0) { throw 'Le rapport Oracle Flexera ne contient aucune ligne.' }

$sample = $sourceRows[0]
$columns = [pscustomobject]@{
    PhysicalServer = Resolve-SourceColumn $sample 'Physical server name' @('Physical server name', 'PhysicalServerName', 'Physical Server', 'Host server name') -Optional
    VirtualServer  = Resolve-SourceColumn $sample 'Virtual server name' @('Virtual server name', 'VirtualServerName', 'Virtual Server', 'Device name') -Optional
    Instance       = Resolve-SourceColumn $sample 'DB instance name' @('DB instance name', 'Instance name', 'InstanceName', 'Oracle instance', 'OracleInstanceName')
    Version        = Resolve-SourceColumn $sample 'Product version' @('Product version', 'ProductVersion', 'Version') -Optional
    Edition        = Resolve-SourceColumn $sample 'Product edition' @('Product edition', 'ProductEdition', 'Edition') -Optional
    Environment    = Resolve-SourceColumn $sample 'Environment usage' @('Environment usage', 'EnvironmentUsage', 'Environment') -Optional
    Metric         = Resolve-SourceColumn $sample 'License metric (NUP/Processor)' @('License metric (NUP/Processor)', 'License metric', 'LicenseMetric', 'Metric') -Optional
    Consumption    = Resolve-SourceColumn $sample 'Number of licenses in use' @('Number of licenses in use', 'NumberOfLicensesInUse', 'Licenses in use', 'Consumption') -Optional
    Options        = Resolve-SourceColumn $sample 'Options & Mgmt packs in use' @('Options & Mgmt packs in use', 'Options & Mgmt Packs in Use', 'OptionsAndMgmtPacksInUse', 'Options and Mgmt packs in use')
}

Write-Verbose "Mapping détecté : $($columns | ConvertTo-Json -Compress)"

$results = [Collections.Generic.List[object]]::new()
foreach ($row in $sourceRows) {
    $instance = Get-OptionalValue -Row $row -Column $columns.Instance
    if ([string]::IsNullOrWhiteSpace([string] $instance)) { continue }

    $rawOptions = Get-OptionalValue -Row $row -Column $columns.Options
    $options = @(Split-OracleOptions -Value $rawOptions)

    if ($options.Count -eq 0) {
        if (-not $OnlyOptions) {
            $results.Add([pscustomobject][ordered]@{
                PhysicalServerName      = Get-OptionalValue -Row $row -Column $columns.PhysicalServer
                VirtualServerName       = Get-OptionalValue -Row $row -Column $columns.VirtualServer
                InstanceName            = [string] $instance
                ProductVersion          = Get-OptionalValue -Row $row -Column $columns.Version
                ProductEdition          = Get-OptionalValue -Row $row -Column $columns.Edition
                EnvironmentUsage        = Get-OptionalValue -Row $row -Column $columns.Environment
                LicenseMetric           = Get-OptionalValue -Row $row -Column $columns.Metric
                DatabaseLicensesInUse   = Get-OptionalValue -Row $row -Column $columns.Consumption
                OptionOrManagementPack  = $null
                OptionInUse             = $false
            })
        }
        continue
    }

    foreach ($option in $options) {
        $results.Add([pscustomobject][ordered]@{
            PhysicalServerName      = Get-OptionalValue -Row $row -Column $columns.PhysicalServer
            VirtualServerName       = Get-OptionalValue -Row $row -Column $columns.VirtualServer
            InstanceName            = [string] $instance
            ProductVersion          = Get-OptionalValue -Row $row -Column $columns.Version
            ProductEdition          = Get-OptionalValue -Row $row -Column $columns.Edition
            EnvironmentUsage        = Get-OptionalValue -Row $row -Column $columns.Environment
            LicenseMetric           = Get-OptionalValue -Row $row -Column $columns.Metric
            DatabaseLicensesInUse   = Get-OptionalValue -Row $row -Column $columns.Consumption
            OptionOrManagementPack  = [string] $option
            OptionInUse             = $true
        })
    }
}

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$results |
    Sort-Object PhysicalServerName, VirtualServerName, InstanceName, OptionOrManagementPack |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

$optionRows = @($results | Where-Object OptionInUse)
$instanceCount = @($sourceRows | ForEach-Object { Get-OptionalValue -Row $_ -Column $columns.Instance } | Where-Object { $_ } | Sort-Object -Unique).Count
Write-Host "Inventaire terminé : $instanceCount instance(s), $($optionRows.Count) option(s)/management pack(s) en usage."
Write-Host "Rapport : $OutputCsv"
exit 0
