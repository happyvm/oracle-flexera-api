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

### Zone du tenant Flexera (EU ou US)

Flexera One sépare ses tenants par zone géographique, avec des URL d'API et
d'authentification différentes. La zone se déduit du portail utilisé pour se
connecter :

| | Amérique du Nord (US) | Europe (EU) |
| --- | --- | --- |
| Portail | `app.flexera.com` | `app.flexera.eu` |
| API base | `api.flexera.com` | `api.flexera.eu` |
| Jeton OAuth | `https://login.flexera.com/oidc/token` | `https://login.flexera.eu/oidc/token` |

Le script utilise `https://login.flexera.com/oidc/token` par défaut si
`FLEXERA_TOKEN_URL` n'est pas défini : les tenants EU doivent donc **toujours**
renseigner explicitement `FLEXERA_TOKEN_URL` (et utiliser `api.flexera.eu` dans
`FLEXERA_LICENSE_API_URL`), sous peine d'authentification contre le mauvais
pays et d'échec `401`.

### Variables d'environnement

Copier [`config/flexera.env.example.ps1`](config/flexera.env.example.ps1) vers
`config/flexera.env.ps1` (fichier ignoré par git, jamais committé), renseigner
les valeurs, puis le charger dans la session avant chaque exécution :

```powershell
. .\config\flexera.env.ps1
.\scripts\Invoke-OracleLicenseControl.ps1
```

Le fichier modèle couvre toutes les variables reconnues par le script :

| Variable | Obligatoire | Rôle |
| --- | --- | --- |
| `FLEXERA_CLIENT_ID` | oui | Identifiant du compte de service OAuth Flexera. |
| `FLEXERA_CLIENT_SECRET` | oui | Secret associé, jamais passé en argument. |
| `FLEXERA_LICENSE_API_URL` | oui (mode API) | URL de l'endpoint ITAM des positions de licences. |
| `FLEXERA_TOKEN_URL` | recommandé (obligatoire en EU) | URL du endpoint OAuth token. Défaut : `https://login.flexera.com/oidc/token`. |
| `FLEXERA_AUDIENCE` | non | Audience OAuth, si imposée par l'admin Flexera. |
| `FLEXERA_SCOPE` | non | Scope OAuth, si imposé par l'admin Flexera. |

Alternative sans fichier de config, en définissant les variables directement
dans la session :

```powershell
$env:FLEXERA_CLIENT_ID = '...'
$env:FLEXERA_CLIENT_SECRET = '...'
$env:FLEXERA_LICENSE_API_URL = 'https://URL-API-ITAM/endpoint-positions-licences'

# Seulement si les valeurs fournies par Flexera diffèrent ou sont requises :
$env:FLEXERA_TOKEN_URL = 'https://login.flexera.com/oidc/token'
$env:FLEXERA_AUDIENCE = 'audience-fournie-par-flexera'
$env:FLEXERA_SCOPE = 'scope-fourni-par-flexera'
```

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

## Suivi de l'usage par base et alerte de supervision

Au-delà du contrôle global droits/consommation par licence, l'API FNMS v1 de
Flexera One expose le détail des objets qui consomment réellement chaque
licence — dont, pour les licences de bases de données, les **instances**
(bases) concernées. C'est confirmé directement dans le schéma OpenAPI publié
par Flexera (`https://developer.flexera.com/openapi/services/fnms/v1/openapi.json`) :

| Endpoint | Rôle |
| --- | --- |
| `GET /fnms/v1/orgs/{orgId}/licenses` | Liste des licences avec droits/consommation agrégés (`compliance.purchasedEntitlementCount`, `compliance.consumedEntitlementCount`). |
| `GET /fnms/v1/orgs/{orgId}/licenses/{licenseId}/consumption` | Détail par machine, avec un tableau `instances[].name` — pour Oracle, le nom d'instance/PDB (ex. `thsm01d~CDB_ROOT`). |

Chaque enregistrement de consommation porte aussi un tableau `products`, dont
chaque entrée a un indicateur `isSupplementary` : c'est le mécanisme générique
par lequel Flexera distingue un composant ou une **option** ajoutée au produit
de base (Partitioning, Diagnostics Pack, etc.) du produit de base lui-même.

**LIMITE IMPORTANTE** : `instances` et `products` sont tous deux portés au
niveau de la **machine**, sur un même enregistrement, sans lien explicite
entre eux. Si une machine n'héberge qu'une seule instance, l'attribution
option → base est fiable. Si elle en héberge plusieurs, Flexera ne permet pas
de savoir laquelle des instances utilise quelle option. La section suivante
(vérification directe en base) lève cette ambiguïté quand elle importe.

Deux scripts exploitent ce détail pour répondre à la question « telle licence
(ou telle option) a-t-elle été utilisée sur telle base, et est-ce nouveau
depuis la dernière extraction ? » :

**1. Extraction d'une photo à un instant T :**

```powershell
$env:FLEXERA_API_BASE_URL = 'https://api.flexera.eu'   # ou api.flexera.com en zone US
$env:FLEXERA_ORG_ID = '12345'

.\scripts\Export-OracleLicenseUsage.ps1 -OutputCsv .\reports\usage-instances-J1.csv
```

Produit un CSV `Licence, LicenseId, Type, Instance, Machine, Option,
EstOptionSupplementaire, DateExtraction` : une ligne par combinaison
licence/instance/option effectivement observée (`EstOptionSupplementaire` =
`Oui` pour une option, `Non` pour le produit de base). `-PublisherFilter`
(`Oracle` par défaut) restreint aux licences dont l'éditeur ou le nom
contiennent ce mot ; seules les consommations rattachées à une instance sont
retenues, les consommations au seul niveau machine sont ignorées.

**2. Comparaison entre deux extractions :**

```powershell
# Au niveau de la base (comportement par défaut) :
.\scripts\Compare-OracleLicenseUsage.ps1 `
  -BeforeCsv .\reports\usage-instances-J1.csv `
  -AfterCsv  .\reports\usage-instances-J2.csv `
  -OutputCsv .\reports\diff-usage-instances.csv

# Au niveau de l'option/du produit détecté sur chaque base :
.\scripts\Compare-OracleLicenseUsage.ps1 `
  -BeforeCsv .\reports\usage-instances-J1.csv `
  -AfterCsv  .\reports\usage-instances-J2.csv `
  -KeyColumns Licence,Instance,Option `
  -OutputCsv .\reports\diff-usage-options.csv
```

Classe chaque combinaison en `NouvelUsage` (absente en J1, présente en J2),
`UsageArrete` (inverse) ou `Inchange`. Le script renvoie le code processus
**2** si au moins un `NouvelUsage` est détecté, **0** sinon — même convention
que `Invoke-OracleLicenseControl.ps1`, directement exploitable par un
ordonnanceur ou un check actif Nagios/Centreon. Ce script ne pousse rien vers
Centreon lui-même : câbler l'envoi (check actif, ou passif via NSCA/NRDP)
reste à faire selon votre infrastructure de supervision.

`scripts/FlexeraApiClient.psm1` factorise l'authentification OAuth et la
pagination FNMS v1 (suivi du champ `nextPage`) utilisées par
`Export-OracleLicenseUsage.ps1`.

## Vérification directe en base (DBA_FEATURE_USAGE_STATISTICS)

Pour lever l'ambiguïté machine/instance de Flexera, ou tout simplement pour
disposer d'une source indépendante, `scripts/Get-OracleDatabaseFeatureUsage.ps1`
interroge directement chaque instance/PDB Oracle via `sqlplus`, en s'appuyant
sur la vue `DBA_FEATURE_USAGE_STATISTICS` qu'Oracle Database alimente
lui-même (job MMON, échantillonnage périodique) — c'est la même source que
la méthode officielle Oracle LMS. Fournir la liste des instances à auditer
dans un CSV (voir [`config/oracle-instances.example.csv`](config/oracle-instances.example.csv)) :

```csv
Instance,ConnectString,Username,PasswordEnvVar
thsm01d~CDB_ROOT,thsm01d.exemple.local:1521/CDBROOT,,
test01~PDB2,test01.exemple.local:1521/PDB2,sam_audit_test,ORACLE_AUDIT_PASSWORD_TEST
```

`Instance` doit reprendre le même nom que celui observé côté Flexera pour
pouvoir recouper les deux rapports. `Username`/`PasswordEnvVar` sont
optionnels par ligne ; à défaut, le script utilise `$env:ORACLE_AUDIT_USER` et
la variable désignée par `$env:ORACLE_AUDIT_PASSWORD` (voir
[`config/oracle-audit.env.example.ps1`](config/oracle-audit.env.example.ps1)).

```powershell
. .\config\oracle-audit.env.ps1
.\scripts\Get-OracleDatabaseFeatureUsage.ps1 `
  -InstancesCsv .\config\oracle-instances.csv `
  -OutputCsv .\reports\features-oracle-J1.csv
```

Produit un CSV `Instance, Fonctionnalite, Version, UsagesDetectes,
ActuellementUtilise, PremiereUtilisation, DerniereUtilisation,
DateExtraction` — une ligne par fonctionnalité dont l'usage a été détecté au
moins une fois. Ce même rapport, réextrait à J2, peut être diffusé avec
`Compare-OracleLicenseUsage.ps1 -KeyColumns Instance,Fonctionnalite` pour
détecter une fonctionnalité nouvellement utilisée sur une base précise.

**Sécurité** : le mot de passe n'est jamais passé en argument de processus ni
écrit sur disque — il est lu depuis la variable d'environnement désignée puis
transmis à `sqlplus -S /nolog` uniquement via son entrée standard
(`scripts/OracleSqlPlusClient.psm1`). Limite de la syntaxe `CONNECT
user/password@connectString` : un mot de passe contenant un espace, une
apostrophe, `/` ou `@` est refusé explicitement plutôt que d'être mal
interprété.

**Portée et limites** : ce dépôt ne prétend pas reproduire le mapping officiel
« fonctionnalité détectée → option/pack sous contrat » établi par Oracle (ce
mapping évolue par version et appartient à la documentation Oracle Support,
Doc ID 1317265.1, sans droit de redistribution ici) : la sortie liste les
fonctionnalités détectées telles que nommées par Oracle, à recouper avec vos
contrats et, pour un contrôle de conformité formel, avec le script officiel.
Une instance injoignable ou en échec d'authentification est consignée en
avertissement (code de sortie **1**) sans bloquer les autres instances de
l'inventaire. Ce script n'a pas pu être testé contre une vraie instance
Oracle dans cet environnement de développement (aucune base disponible) :
validez-le sur une instance de test avant un déploiement plus large — la
construction du script de connexion `sqlplus`, elle, est couverte par des
tests unitaires (`tests/OracleSqlPlusClient.Tests.ps1`).

## Tests

Les tests d'intégration nécessitent PowerShell et Pester 5 :

```powershell
Invoke-Pester .\tests -Output Detailed
```
