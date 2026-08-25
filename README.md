# Contrôle des écarts de licences Oracle avec Flexera One

Cette solution **PowerShell** produit un contrôle exploitable de conformité :
elle compare les droits Oracle acquis à la consommation calculée par Flexera,
puis classe chaque licence en **Déficit**, **Équilibre** ou **Surplus**.

Le fonctionnement nominal est **entièrement API uniquement si l'API ITAM de
votre tenant expose les positions de licences** : une fois les variables
d'environnement enregistrées, une exécution sans argument récupère les données,
suit la pagination, détecte les colonnes, calcule les écarts et écrit un rapport
daté.

Aucun faux endpoint universel n'est codé en dur. Flexera One est une plateforme
de plusieurs services : voir un rapport dans l'interface ITAM ne signifie pas
que ce rapport est une ressource REST. L'API doit au minimum fournir, directement
ou via une vue publiée, le nom de licence, la métrique, les droits et la
consommation.

## Réponse directe : si le licensing n'est pas exposé

Un script ne peut pas récupérer par API une donnée que le service ne publie pas.
Il existe alors trois solutions, par ordre de préférence :

1. **Endpoint ITAM de positions de licences activé** : utiliser directement cet
   endpoint avec le présent script. Il n'est pas nécessaire que le rapport UI
   lui-même soit exposé, seulement les quatre données nécessaires au calcul.
2. **Vue ou intégration API publiée par Flexera** : faire créer par
   l'administrateur Flexera une vue autorisée contenant ces quatre données, puis
   renseigner son URL dans `FLEXERA_LICENSE_API_URL`.
3. **Aucune API de licensing dans l'abonnement/tenant** : programmer un export
   du rapport depuis Flexera vers un emplacement contrôlé. Cette chaîne peut être
   automatisée, mais elle n'est pas « depuis l'API » et le mode CSV est alors le
   seul mode honnête.

Les API d'inventaire ne suffisent pas à reconstituer une position Oracle : le
calcul Flexera inclut les droits, métriques et règles de consommation. Le script
refuse donc de présenter l'inventaire brut comme un résultat de conformité.

## Résultat du contrôle

Pour chaque licence et métrique, le fichier de sortie contient :

| Colonne | Signification |
| --- | --- |
| `Licence` | Nom de la licence Oracle |
| `Metrique` | Métrique contractuelle (Processor, NUP, etc.) |
| `DroitsAcquis` | Quantité achetée disponible dans Flexera |
| `Consommation` | Quantité consommée calculée par Flexera |
| `Ecart` | `DroitsAcquis - Consommation` |
| `Statut` | `Déficit`, `Équilibre` ou `Surplus` |
| `Risque` | Quantité manquante, toujours positive en cas de déficit |
| `TauxCouverturePct` | Droits divisés par consommation, en pourcentage |

Si l'export contient plusieurs lignes pour une même combinaison licence / métrique
(par exemple plusieurs pools), les droits et consommations sont additionnés avant
le calcul afin d'éviter de signaler de faux écarts ligne par ligne.

Le script renvoie le code processus **2** si au moins un déficit est constaté.
Il peut donc être intégré à un ordonnanceur ou à une CI pour déclencher une
alerte. Un seuil, par exemple `-SeuilAlerte 5`, permet de tolérer un petit écart
avant de classer la ligne en déficit.

> Ce calcul est un contrôle opérationnel, pas un avis juridique. Pour Oracle,
> validez notamment les métriques, facteurs de cœur, règles de virtualisation,
> options/packs et populations NUP avec les contrats et un spécialiste SAM.

## Prérequis

- Windows PowerShell 5.1 ou PowerShell 7+ ;
- un rapport API contenant le nom de licence, la métrique, les droits acquis et
  la consommation ;
- un compte de service OAuth Flexera en lecture seule, l'URL
  du token, l'URL exacte du rapport et éventuellement l'audience/scope indiqués
  par l'administrateur Flexera.

Les secrets sont lus depuis l'environnement et ne sont jamais passés en
argument ou écrits dans les rapports.

## 1. Configuration initiale de l'exécution autonome

Enregistrer les variables au niveau du compte qui exécutera la tâche :

```powershell
$env:FLEXERA_CLIENT_ID = '...'
$env:FLEXERA_CLIENT_SECRET = '...'
$env:FLEXERA_LICENSE_API_URL = 'https://URL-API-ITAM/endpoint-positions-licences'

# Seulement si les valeurs fournies par Flexera diffèrent ou sont requises :
$env:FLEXERA_TOKEN_URL = 'https://login.flexera.com/oidc/token'
$env:FLEXERA_AUDIENCE = 'audience-fournie-par-flexera'
$env:FLEXERA_SCOPE = 'scope-fourni-par-flexera'
```

`FLEXERA_TOKEN_URL` utilise `https://login.flexera.com/oidc/token` par défaut.
Le secret doit être stocké dans le gestionnaire de secrets de l'ordonnanceur en
production, puis injecté dans l'environnement du processus.

Lancer ensuite simplement :

```powershell
.\scripts\Invoke-OracleLicenseControl.ps1
```

Le rapport est créé automatiquement sous
`reports/controle-ecarts-oracle-AAAAMMJJ-HHMMSS.csv`. Le code de sortie vaut
`0` en l'absence de déficit, `2` en présence d'au moins un déficit et `1` en cas
d'erreur PowerShell non interceptée.

## 2. Détection automatique des colonnes

Le script reconnaît plusieurs noms courants pour la licence, la métrique, les
droits et la consommation. Utiliser `-Verbose` pour voir le mapping retenu :

```powershell
.\scripts\Invoke-OracleLicenseControl.ps1 -Verbose
```

Copier [`config/column-map.example.json`](config/column-map.example.json), puis
adapter les valeurs aux propriétés JSON réelles de votre endpoint :

```json
{
  "Licence": "LicenseName",
  "Metrique": "Metric",
  "DroitsAcquis": "PurchasedEntitlements",
  "Consommation": "ConsumedEntitlements"
}
```

Utiliser alors ce mapping lors des exécutions :

```powershell
.\scripts\Invoke-OracleLicenseControl.ps1 -ColumnMap .\config\column-map.json
```

Une URL ou une destination ponctuelle peut toujours remplacer les valeurs par
défaut :

```powershell
.\scripts\Invoke-OracleLicenseControl.ps1 `
  -ApiUri 'https://URL-API-FLEXERA/chemin/rapport-oracle?status=Active' `
  -RawExportCsv .\exports\oracle-flexera-api.csv `
  -OutputCsv .\reports\controle-ecarts-oracle.csv
```

Le client suit les champs de pagination `next`, `nextLink` ou `next_page`, et
les collections `data`, `items`, `results` ou `records`. Une URL de page
suivante située sur un autre hôte est refusée afin de ne pas divulguer le jeton.

## 3. Exploiter le résultat

Afficher uniquement les déficits :

```powershell
Import-Csv .\reports\controle-ecarts-oracle.csv |
  Where-Object Statut -eq 'Déficit' |
  Sort-Object {[decimal]$_.Risque} -Descending
```

Points à investiguer en priorité :

1. licences avec `Statut = Déficit`, triées par `Risque` décroissant ;
2. lignes sans métrique ou avec des données non numériques (le script les
   bloque au lieu de produire un résultat trompeur) ;
3. licences Oracle option/packs dont la consommation dépend du socle installé ;
4. changements de périmètre entre deux extractions Flexera.

## Automatisation

Exemple de tâche planifiée qui conserve un rapport daté :

```powershell
$date = Get-Date -Format 'yyyyMMdd-HHmmss'
& .\scripts\Invoke-OracleLicenseControl.ps1 `
  -OutputCsv ".\reports\controle-oracle-$date.csv"

if ($LASTEXITCODE -eq 2) {
    Write-Warning 'Des écarts Oracle déficitaires ont été détectés.'
}
```

## Vérifier que l'endpoint est utilisable

Avant l'automatisation, appeler une page avec le même compte de service :

```powershell
$tokenResponse = Invoke-RestMethod -Method Post `
  -Uri 'https://login.flexera.com/oidc/token' `
  -ContentType 'application/x-www-form-urlencoded' `
  -Body @{
    grant_type = 'client_credentials'
    client_id = $env:FLEXERA_CLIENT_ID
    client_secret = $env:FLEXERA_CLIENT_SECRET
  }

Invoke-RestMethod -Uri $env:FLEXERA_LICENSE_API_URL `
  -Headers @{ Authorization = "Bearer $($tokenResponse.access_token)" } |
  ConvertTo-Json -Depth 10
```

La réponse doit contenir une collection et quatre informations mappables : nom
de licence, métrique, droits acquis et consommation. Une réponse `401` indique
un problème d'authentification, `403` un droit/scope manquant, et `404` que l'URL
n'est pas un endpoint disponible pour ce tenant. Si les propriétés existent
mais portent d'autres noms, utiliser `-ColumnMap`.

## Limite importante de l'API

Un rapport affiché dans Flexera One ITAM n'est pas automatiquement exposé via
API. Si aucun endpoint de positions de licences n'est disponible pour votre
tenant, planifiez l'export CSV dans Flexera et utilisez le mode de secours :

```powershell
.\scripts\Invoke-OracleLicenseControl.ps1 `
  -FlexeraCsv .\exports\oracle-flexera.csv `
  -OutputCsv .\reports\controle-ecarts-oracle.csv
```

Le séparateur du CSV est configurable avec `-Delimiter ';'`. Les valeurs
numériques utilisent la culture choisie avec `-Culture`.

## Tests

Les tests d'intégration nécessitent PowerShell et Pester 5 :

```powershell
Invoke-Pester .\tests\Invoke-OracleLicenseControl.Tests.ps1 -Output Detailed
```
