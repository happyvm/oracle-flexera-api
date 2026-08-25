Set-StrictMode -Version Latest

function Get-RequiredEnvironmentVariable {
    param([Parameter(Mandatory)][string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "La variable d'environnement $Name est obligatoire en mode API."
    }
    return $value
}

function Get-FlexeraAccessToken {
    <#
        Récupère un jeton OAuth client-credentials Flexera à partir des
        variables d'environnement FLEXERA_CLIENT_ID / FLEXERA_CLIENT_SECRET,
        et éventuellement FLEXERA_AUDIENCE / FLEXERA_SCOPE / FLEXERA_TOKEN_URL.
    #>
    [CmdletBinding()]
    param()

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

function Get-FlexeraPagedValues {
    <#
        Appelle un endpoint FNMS v1 et suit la pagination "nextPage" (URL
        relative ou absolue) jusqu'à épuisement. Accepte aussi bien une
        réponse qui est directement un tableau JSON (ex. /licenses) qu'une
        réponse enveloppée dans une propriété "values" (ex. /consumption,
        /license-entitlements, /license-attributes).

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
