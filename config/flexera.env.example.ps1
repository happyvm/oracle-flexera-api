# Modèle des variables d'environnement nécessaires au script
# scripts/Invoke-OracleLicenseControl.ps1.
#
# Utilisation :
#   1. Copier ce fichier vers config/flexera.env.ps1 (ignoré par git, ne
#      jamais committer de secret).
#   2. Renseigner les valeurs ci-dessous pour votre zone Flexera (EU ou US).
#   3. Charger les variables dans la session avant d'exécuter le script :
#        . .\config\flexera.env.ps1
#        .\scripts\Invoke-OracleLicenseControl.ps1

# --- Compte de service Flexera (obligatoire) ---
# Fournis par l'administrateur Flexera, avec accès en lecture seule.
$env:FLEXERA_CLIENT_ID     = ''
$env:FLEXERA_CLIENT_SECRET = ''

# --- Endpoint ITAM des positions de licences (obligatoire) ---
# Doit exposer, directement ou via une vue publiée : nom de licence,
# métrique, droits acquis et consommation. Remplacer {orgId} et
# {licenseId} par les identifiants de votre tenant.
$env:FLEXERA_LICENSE_API_URL = ''

# --- Zone du tenant : décommenter UN SEUL des deux blocs ci-dessous ---
# Le portail où vous vous connectez (app.flexera.eu vs app.flexera.com)
# indique la zone de votre tenant.

# Zone Europe (EU)
# $env:FLEXERA_TOKEN_URL       = 'https://login.flexera.eu/oidc/token'
# $env:FLEXERA_LICENSE_API_URL = 'https://api.flexera.eu/fnms/v1/orgs/{orgId}/licenses/{licenseId}/consumption'

# Zone Amérique du Nord (US) — valeur par défaut du script si FLEXERA_TOKEN_URL
# est omis, à définir explicitement ici par cohérence avec le bloc EU.
# $env:FLEXERA_TOKEN_URL       = 'https://login.flexera.com/oidc/token'
# $env:FLEXERA_LICENSE_API_URL = 'https://api.flexera.com/fnms/v1/orgs/{orgId}/licenses/{licenseId}/consumption'

# --- Optionnel : uniquement si l'administrateur Flexera les impose ---
# $env:FLEXERA_AUDIENCE = ''
# $env:FLEXERA_SCOPE    = ''
