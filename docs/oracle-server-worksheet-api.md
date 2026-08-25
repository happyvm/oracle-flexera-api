# Oracle Server Worksheet via Flexera One Reports API

`Get-FlexeraOracleInventory.ps1` récupère le rapport intégré **Oracle Server Worksheet for Oracle Database** par l'API ITAM Reports de Flexera One et normalise la colonne **Options & Mgmt packs in use**.

Contrairement à `Export-OracleLicenseUsage.ps1`, qui part de `/licenses/{licenseId}/consumption` et doit associer des produits et des instances au niveau d'une machine, le Server Worksheet contient une ligne par instance Oracle. Il est donc préférable lorsqu'on veut répondre à la question : **quelles options/packs Flexera considère-t-il en usage sur cette instance précise ?**

## API utilisée

Le script utilise les endpoints ITAM suivants :

```text
GET  /fnms/v1/orgs/{orgId}/reports
GET  /fnms/v1/orgs/{orgId}/reports/{id}/execute?limit=&skipToken=&searchText=
```

Le mode `-Async` utilise également :

```text
POST /fnms/v1/orgs/{orgId}/reports/{id}/execute-async
GET  /fnms/v1/orgs/{orgId}/reports/{id}/execute-async/{jobId}/status
GET  /fnms/v1/orgs/{orgId}/reports/{id}/execute-async/{jobId}/retrieve
```

Le script cherche automatiquement le rapport par son nom. `-ReportId` permet de forcer l'identifiant si plusieurs rapports ont le même nom.

## Authentification

Flexera One supporte deux modes, tous les deux transformés en `access_token` Bearer avant l'appel ITAM.

### Compte utilisateur : API Refresh Token

Pour un compte utilisateur, créer un **API Refresh Token** dans Flexera One > **API Credentials**, puis définir :

```powershell
$env:FLEXERA_REFRESH_TOKEN = '...'
```

Le script envoie alors :

```text
grant_type=refresh_token
refresh_token=<token>
```

vers l'endpoint OAuth de la zone. Si `FLEXERA_REFRESH_TOKEN` est défini, ce mode est **prioritaire** sur les identifiants de service account.

### Service account

Alternative pour une automatisation technique :

```powershell
$env:FLEXERA_CLIENT_ID = '...'
$env:FLEXERA_CLIENT_SECRET = '...'
```

Le script utilise alors `grant_type=client_credentials`.

### Zone

La zone sélectionne automatiquement les bons domaines API et OAuth :

```powershell
# Europe — valeur par défaut
$env:FLEXERA_ZONE = 'EU'

# Autres valeurs possibles : NAM, APAC
```

Correspondance :

| Zone | API | OAuth |
| --- | --- | --- |
| `NAM` | `https://api.flexera.com` | `https://login.flexera.com/oidc/token` |
| `EU` | `https://api.flexera.eu` | `https://login.flexera.eu/oidc/token` |
| `APAC` | `https://api.flexera.au` | `https://login.flexera.au/oidc/token` |

Une URL de token personnalisée peut toujours être imposée avec `FLEXERA_TOKEN_URL`.

> Ne jamais stocker le vrai refresh token dans Git. Utiliser `config/flexera.env.ps1` (ignoré par `.gitignore`) ou un gestionnaire de secrets.

## Exécution

Avec un compte utilisateur EU :

```powershell
$env:FLEXERA_REFRESH_TOKEN = '...'

.\scripts\Get-FlexeraOracleInventory.ps1 `
  -OrganizationId '12345' `
  -Zone EU `
  -OnlyOptions `
  -OutputCsv .\reports\oracle-options.csv
```

Le mode synchrone est utilisé par défaut et suit la pagination `skipToken`. La taille de page est configurable :

```powershell
.\scripts\Get-FlexeraOracleInventory.ps1 `
  -OrganizationId '12345' `
  -PageSize 2000
```

Pour demander l'exécution asynchrone du rapport :

```powershell
.\scripts\Get-FlexeraOracleInventory.ps1 `
  -OrganizationId '12345' `
  -Async
```

Pour conserver en plus la réponse tabulaire brute du rapport avant éclatement des options :

```powershell
.\scripts\Get-FlexeraOracleInventory.ps1 `
  -OrganizationId '12345' `
  -RawReportCsv .\reports\oracle-server-worksheet-raw.csv `
  -OutputCsv .\reports\oracle-options.csv
```

## Sortie

Le CSV normalisé contient :

```text
PhysicalServerName
VirtualServerName
InstanceName
ProductVersion
ProductEdition
EnvironmentUsage
LicenseMetric
DatabaseLicensesInUse
OptionOrManagementPack
OptionInUse
```

Une valeur Flexera telle que :

```text
Partitioning; Diagnostics Pack, Tuning Pack
```

est transformée en trois lignes distinctes pour la même instance.

Par défaut, les instances dont Flexera ne remonte aucune option/packs restent présentes avec `OptionOrManagementPack` vide et `OptionInUse=False`. Utiliser `-OnlyOptions` pour ne conserver que les lignes d'options/packs en usage.

## Sémantique importante

Dans l'Oracle Server Worksheet, **Options & Mgmt packs in use** ne signifie pas simplement « composant installé ». Flexera documente cette colonne comme contenant les options et management packs qui sont installés, en usage et licensables sur l'instance, sous réserve des règles de consommation et d'exemption de la licence.

Le résultat est donc une vue SAM/licensing de Flexera. Pour un contrôle technique indépendant, il reste pertinent de la croiser avec `Get-OracleDatabaseFeatureUsage.ps1` et les données interrogées directement dans Oracle.

## Test hors ligne

Le script accepte un export CSV du Worksheet pour tester le parsing sans tenant Flexera :

```powershell
.\scripts\Get-FlexeraOracleInventory.ps1 `
  -ReportCsv .\tests\fixtures\oracle-server-worksheet.csv `
  -OutputCsv .\reports\oracle-options-test.csv
```

Les tests Pester associés sont dans `tests/Get-FlexeraOracleInventory.Tests.ps1`.
