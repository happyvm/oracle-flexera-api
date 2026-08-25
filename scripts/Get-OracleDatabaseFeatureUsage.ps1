[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $InstancesCsv,

    [string] $OutputCsv = (Join-Path 'reports' ("features-oracle-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $SqlScript = (Join-Path $PSScriptRoot '..' 'sql' 'options-packs-usage.sql'),

    [string] $SqlplusPath = 'sqlplus',

    [char] $Delimiter = ','
)

<#
    Interroge DBA_FEATURE_USAGE_STATISTICS de chaque instance/PDB Oracle
    listée dans -InstancesCsv (colonnes : Instance, ConnectString, et
    optionnellement Username/PasswordEnvVar par ligne) via sqlplus, et
    consolide le résultat dans un rapport daté. C'est le complément direct
    (vérité de la base) au rapport produit par Export-OracleLicenseUsage.ps1
    côté Flexera : ce dernier ne peut pas toujours distinguer, sur une
    machine hébergeant plusieurs instances, quelle instance utilise quelle
    option — interroger directement chaque instance lève l'ambiguïté.

    Le mot de passe n'est jamais lu depuis la ligne de commande ni depuis le
    CSV : chaque ligne référence le NOM d'une variable d'environnement
    (colonne PasswordEnvVar, ou $env:ORACLE_AUDIT_PASSWORD par défaut) dont
    la valeur est lue au moment de l'exécution et transmise à sqlplus par son
    entrée standard uniquement (jamais en argument de processus, jamais
    écrite sur disque).

    Une instance en échec (connexion refusée, droits insuffisants, etc.) est
    consignée en avertissement et n'interrompt pas le traitement des autres
    instances ; le script renvoie 1 si au moins un échec a eu lieu, 0 sinon.

    Ce script n'a pas pu être testé de bout en bout contre une vraie base
    Oracle (aucune instance disponible dans l'environnement de
    développement) : validez-le sur une instance de test avant un usage en
    production. La construction du script de connexion sqlplus (fonction
    New-SqlPlusLoginScript du module OracleSqlPlusClient.psm1) est en
    revanche couverte par des tests unitaires.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'OracleSqlPlusClient.psm1') -Force

$inventory = @(Import-Csv -LiteralPath $InstancesCsv -Delimiter $Delimiter)
if ($inventory.Count -eq 0) { throw "L'inventaire '$InstancesCsv' ne contient aucune instance." }

$extractedAt = Get-Date -Format 'o'
$rows = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()

foreach ($entry in $inventory) {
    $instance = [string] $entry.Instance
    $connectString = [string] $entry.ConnectString
    if ([string]::IsNullOrWhiteSpace($instance) -or [string]::IsNullOrWhiteSpace($connectString)) {
        throw "Chaque ligne de l'inventaire doit renseigner Instance et ConnectString."
    }

    $username = if (($entry.PSObject.Properties.Name -contains 'Username') -and -not [string]::IsNullOrWhiteSpace($entry.Username)) {
        [string] $entry.Username
    }
    else {
        $env:ORACLE_AUDIT_USER
    }
    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Warning "Aucun utilisateur pour '$instance' : renseignez la colonne Username ou `$env:ORACLE_AUDIT_USER."
        $failures.Add("$instance : utilisateur manquant")
        continue
    }

    $passwordEnvVar = if (($entry.PSObject.Properties.Name -contains 'PasswordEnvVar') -and -not [string]::IsNullOrWhiteSpace($entry.PasswordEnvVar)) {
        [string] $entry.PasswordEnvVar
    }
    else {
        'ORACLE_AUDIT_PASSWORD'
    }
    $password = [Environment]::GetEnvironmentVariable($passwordEnvVar)
    if ([string]::IsNullOrWhiteSpace($password)) {
        Write-Warning "La variable d'environnement '$passwordEnvVar' (mot de passe pour '$instance') est vide ou absente."
        $failures.Add("$instance : mot de passe manquant ($passwordEnvVar)")
        continue
    }

    try {
        $featureRows = @(Invoke-OracleFeatureUsageQuery -Instance $instance -ConnectString $connectString `
            -Username $username -Password $password -SqlScriptPath $SqlScript -SqlplusPath $SqlplusPath)
        foreach ($row in $featureRows) {
            $rows.Add([pscustomobject] [ordered] @{
                Instance            = $instance
                Fonctionnalite      = $row.feature_name
                Version             = $row.version
                UsagesDetectes      = $row.detected_usages
                ActuellementUtilise = $row.actuellement_utilise
                PremiereUtilisation = $row.premiere_utilisation
                DerniereUtilisation = $row.derniere_utilisation
                DateExtraction      = $extractedAt
            })
        }
    }
    catch {
        Write-Warning "Échec sur '$instance' : $($_.Exception.Message)"
        $failures.Add("$instance : $($_.Exception.Message)")
    }
}

$outputDirectory = Split-Path -Parent $OutputCsv
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
$rows | Sort-Object Instance, Fonctionnalite |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

Write-Host "Extraction terminée : $($rows.Count) ligne(s) sur $($inventory.Count) instance(s), $($failures.Count) échec(s)."
Write-Host "Rapport : $OutputCsv"
if ($failures.Count -gt 0) { exit 1 }
exit 0
