Set-StrictMode -Version Latest

function New-SqlPlusLoginScript {
    <#
        Construit le script à transmettre à "sqlplus -S /nolog" sur son
        entrée standard : connexion puis exécution du script SQL fourni.

        Le mot de passe n'apparaît donc jamais dans les arguments du
        processus (visibles via ps/tasklist) ni dans un fichier sur disque —
        seulement dans le flux stdin du process sqlplus, en mémoire.

        SET DEFINE OFF désactive la substitution de variables SQL*Plus, pour
        qu'un mot de passe ou une chaîne de connexion contenant '&' ne soit
        pas altéré.

        LIMITE CONNUE : la syntaxe "CONNECT user/password@connectString" ne
        permet pas de distinguer un '/' ou un '@' littéral dans le nom
        d'utilisateur ou le mot de passe du séparateur syntaxique. Ces deux
        valeurs sont donc restreintes ; -ConnectString, elle, doit au
        contraire pouvoir contenir '/' pour la syntaxe "easy connect"
        standard (host:port/service_name) — seuls '@', les espaces et les
        apostrophes y sont refusés.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $Password,
        [Parameter(Mandatory)][string] $ConnectString,
        [Parameter(Mandatory)][string] $SqlScriptPath
    )

    foreach ($pair in @(
        @{ Name = 'Username'; Pattern = "['""/@\s]"; Hint = "d'espace ni l'un des caractères ' / @" }
        @{ Name = 'Password'; Pattern = "['""/@\s]"; Hint = "d'espace ni l'un des caractères ' / @" }
        @{ Name = 'ConnectString'; Pattern = "['""@\s]"; Hint = "d'espace ni l'un des caractères ' @" }
    )) {
        $value = Get-Variable -Name $pair.Name -ValueOnly
        if ($value -match $pair.Pattern) {
            throw "$($pair.Name) ne peut pas contenir $($pair.Hint)."
        }
    }

    return @"
SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE
CONNECT $Username/$Password@$ConnectString
@"$SqlScriptPath"
EXIT
"@
}

function Invoke-OracleFeatureUsageQuery {
    <#
        Exécute sql/options-packs-usage.sql sur l'instance/PDB désignée par
        -ConnectString, via sqlplus, et retourne les lignes CSV parsées.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Instance,
        [Parameter(Mandatory)][string] $ConnectString,
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $Password,
        [Parameter(Mandatory)][string] $SqlScriptPath,
        [string] $SqlplusPath = 'sqlplus'
    )

    $loginScript = New-SqlPlusLoginScript -Username $Username -Password $Password `
        -ConnectString $ConnectString -SqlScriptPath $SqlScriptPath

    $output = $loginScript | & $SqlplusPath -S /nolog 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "sqlplus a échoué pour l'instance '$Instance' (code $exitCode) : $($output -join ' ')"
    }

    $csvLines = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($csvLines.Count -eq 0) { return @() }
    return @($csvLines | ConvertFrom-Csv)
}

Export-ModuleMember -Function New-SqlPlusLoginScript, Invoke-OracleFeatureUsageQuery
