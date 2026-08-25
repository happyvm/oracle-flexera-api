Set-StrictMode -Version Latest

function Get-RequiredEnvironmentVariable {
    param([Parameter(Mandatory)][string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "La variable d'environnement $Name est obligatoire en mode API."
    }
    return $value
}

function Get-FlexeraTokenUrl {
    if ($env:FLEXERA_TOKEN_URL) { return [string] $env:FLEXERA_TOKEN_URL }

    # Le client partagé ne reçoit pas la zone explicitement. On l'infère donc
    # de l'URL API lorsqu'elle est disponible, puis on conserve NAM par défaut.
    $apiBase = [string] $env:FLEXERA_API_BASE_URL
    if ($apiBase -match '\.flexera\.eu(?:/|$)') { return 'https://login.flexera.eu/oidc/token' }
    if ($apiBase -match '\.flexera\.au(?:/|$)') { return 'https://login.flexera.au/oidc/token' }
    return 'https://login.flexera.com/oidc/token'
}

function Get-FlexeraAccessToken {
    <#
        Récupère un jeton OAuth Flexera.

        Deux modes sont supportés :
          1. utilisateur/API Credentials : FLEXERA_REFRESH_TOKEN ;
          2. service account : FLEXERA_CLIENT_ID + FLEXERA_CLIENT_SECRET.

        Si FLEXERA_REFRESH_TOKEN est défini, il est prioritaire. Le secret ou
        refresh token n'est jamais écrit dans les logs ou rapports.
    #>
    [CmdletBinding()]
    param()

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

    $response = Invoke-RestMethod -Method Post `
        -Uri (Get-FlexeraTokenUrl) `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $body

    if ([string]::IsNullOrWhiteSpace([string] $response.access_token)) {
        throw 'La réponse OAuth Flexera ne contient pas de jeton access_token.'
    }
    return [string] $response.access_token
}

function Get-FlexeraPagedValues {
    <#
        Appelle un endpoint FNMS v1 et suit la pagination "nextPage" (URL
        relative ou absolue) jusqu'à épuisement. Accepte aussi bien une
        réponse qui est directement un tableau JSON qu'une réponse enveloppée
        dans une propriété "values".

        Une URL de page suivante située sur un autre hôte que l'URL de départ
        est refusée afin de ne pas divulguer le jeton porteur.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri] $Uri,
        [Parameter(Mandatory)][string] $Token,
        [int] $MaxPages = 1000
    )

    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $origin = $Uri.Host
    $nextUri = $Uri.AbsoluteUri
    $rows = [Collections.Generic.List[object]]::new()

    for ($page = 1; $page -le $MaxPages -and $nextUri; $page++) {
        $response = Invoke-RestMethod -Method Get -Uri $nextUri -Headers $headers

        if ($response -is [array]) {
            foreach ($row in $response) { $rows.Add($row) }
        }
        elseif ($response.PSObject.Properties.Name -contains 'values') {
            foreach ($row in @($response.values)) { $rows.Add($row) }
        }
        else {
            $rows.Add($response)
        }

        $next = $null
        if (($response -isnot [array]) -and ($response.PSObject.Properties.Name -contains 'nextPage') -and $response.nextPage) {
            $next = [string] $response.nextPage
        }
        if (-not $next) { $nextUri = $null; continue }

        $resolved = [uri]::new([uri] $nextUri, $next)
        if ($resolved.Scheme -ne 'https' -or $resolved.Host -ne $origin) {
            throw "La pagination a retourné une URL non sûre : $resolved"
        }
        $nextUri = $resolved.AbsoluteUri
    }

    if ($nextUri) { throw "Pagination interrompue après $MaxPages pages." }
    return $rows.ToArray()
}

Export-ModuleMember -Function Get-FlexeraAccessToken, Get-FlexeraPagedValues
