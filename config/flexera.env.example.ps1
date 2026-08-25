# Modèle des variables d'environnement des scripts Flexera.
#
# Utilisation :
#   1. Copier ce fichier vers config/flexera.env.ps1 (ignoré par git).
#   2. Ne jamais committer un vrai secret / refresh token.
#   3. Charger les variables avant l'exécution :
#        . .\config\flexera.env.ps1

# --- Authentification utilisateur (recommandée pour un compte personnel) ---
# Créer le token dans Flexera One > API Credentials.
# Si cette variable est définie, elle est prioritaire sur client_id/client_secret.
$env:FLEXERA_REFRESH_TOKEN = ''

# --- Authentification service account (alternative) ---
# Utilisée uniquement si FLEXERA_REFRESH_TOKEN est vide/non défini.
$env:FLEXERA_CLIENT_ID     = ''
$env:FLEXERA_CLIENT_SECRET = ''

# --- Zone Flexera ---
# Valeurs : EU, NAM, APAC. Get-FlexeraOracleInventory.ps1 utilise EU par défaut.
$env:FLEXERA_ZONE = 'EU'

# URL API utilisée par les scripts basés sur FlexeraApiClient.psm1.
$env:FLEXERA_API_BASE_URL = 'https://api.flexera.eu'

# Organization ID Flexera One.
$env:FLEXERA_ORG_ID = ''

# --- Endpoint de positions de licences ---
# Utilisé par Invoke-OracleLicenseControl.ps1 lorsqu'un endpoint/vues de
# positions de licences est disponible dans le tenant.
$env:FLEXERA_LICENSE_API_URL = ''

# --- Override OAuth optionnel ---
# Normalement inutile avec Get-FlexeraOracleInventory.ps1 : la zone sélectionne
# automatiquement login.flexera.com / .eu / .au.
# Pour les autres scripts, définir cette valeur si nécessaire.
# $env:FLEXERA_TOKEN_URL = 'https://login.flexera.eu/oidc/token'

# --- Optionnel : seulement pour certains service accounts ---
# $env:FLEXERA_AUDIENCE = ''
# $env:FLEXERA_SCOPE    = ''
