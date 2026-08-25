# Configuration centralisée des scripts Flexera.
#
# Utilisation recommandée :
#   1. Copier ce fichier vers config/flexera.env.ps1 (ignoré par git).
#   2. Renseigner les valeurs propres au tenant.
#   3. Lancer directement :
#        .\scripts\Get-FlexeraOracleInventory.ps1
#
# Get-FlexeraOracleInventory.ps1 charge automatiquement config/flexera.env.ps1.
# Les paramètres passés explicitement en ligne de commande restent prioritaires.
# Ne jamais committer un vrai secret / refresh token.

# -----------------------------------------------------------------------------
# Authentification
# -----------------------------------------------------------------------------

# Compte utilisateur Flexera One : API Refresh Token créé dans API Credentials.
# Prioritaire sur FLEXERA_CLIENT_ID/FLEXERA_CLIENT_SECRET lorsqu'il est défini.
$env:FLEXERA_REFRESH_TOKEN = ''

# Alternative : service account.
$env:FLEXERA_CLIENT_ID     = ''
$env:FLEXERA_CLIENT_SECRET = ''

# -----------------------------------------------------------------------------
# Tenant / zone
# -----------------------------------------------------------------------------

# Valeurs : EU, NAM ou APAC.
$env:FLEXERA_ZONE = 'EU'

# Organization ID Flexera One.
$env:FLEXERA_ORG_ID = ''

# URL API du tenant. Peut être omise pour Get-FlexeraOracleInventory.ps1 :
# la zone suffit alors à choisir api.flexera.eu/.com/.au.
$env:FLEXERA_API_BASE_URL = 'https://api.flexera.eu'

# Override OAuth optionnel. Peut être omis : la zone fournit l'URL par défaut.
$env:FLEXERA_TOKEN_URL = 'https://login.flexera.eu/oidc/token'

# Seulement pour certains service accounts.
# $env:FLEXERA_AUDIENCE = ''
# $env:FLEXERA_SCOPE    = ''

# -----------------------------------------------------------------------------
# Oracle Server Worksheet / Get-FlexeraOracleInventory.ps1
# -----------------------------------------------------------------------------

# Le nom suffit normalement : le script découvre automatiquement l'identifiant.
$env:FLEXERA_ORACLE_REPORT_NAME = 'Oracle Server Worksheet for Oracle Database'

# Facultatif : renseigner l'ID pour éviter la découverte par nom.
$env:FLEXERA_ORACLE_REPORT_ID = ''

# Pagination et polling.
$env:FLEXERA_ORACLE_PAGE_SIZE = '1000'
$env:FLEXERA_ORACLE_POLL_TIMEOUT_SECONDS = '600'
$env:FLEXERA_ORACLE_POLL_INTERVAL_SECONDS = '5'

# Facultatif : filtre searchText envoyé au rapport.
# $env:FLEXERA_ORACLE_SEARCH_TEXT = ''

# Répertoire de sortie par défaut. Le script crée un CSV daté dans ce dossier.
$env:FLEXERA_REPORT_DIR = (Join-Path $PSScriptRoot '..\reports')

# Facultatif : impose un chemin de sortie fixe à la place du fichier daté.
# $env:FLEXERA_ORACLE_OUTPUT_CSV = 'C:\Flexera\reports\oracle-options.csv'

# Facultatif : conserve également les lignes brutes du Worksheet avant éclatement.
# $env:FLEXERA_ORACLE_RAW_REPORT_CSV = 'C:\Flexera\reports\oracle-server-worksheet-raw.csv'

# Séparateur CSV commun.
$env:FLEXERA_CSV_DELIMITER = ','

# -----------------------------------------------------------------------------
# Invoke-OracleLicenseControl.ps1
# -----------------------------------------------------------------------------

# Endpoint/vues de positions de licences lorsqu'il est disponible dans le tenant.
$env:FLEXERA_LICENSE_API_URL = ''

# -----------------------------------------------------------------------------
# Fichier de configuration alternatif
# -----------------------------------------------------------------------------

# Au lieu de config/flexera.env.ps1, il est possible de définir globalement :
# $env:FLEXERA_CONFIG_FILE = 'C:\secure\flexera.env.ps1'
