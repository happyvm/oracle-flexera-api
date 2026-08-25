# Modèle des variables d'environnement nécessaires à
# scripts/Get-OracleDatabaseFeatureUsage.ps1 (audit direct des instances
# Oracle via DBA_FEATURE_USAGE_STATISTICS).
#
# Utilisation :
#   1. Copier ce fichier vers config/oracle-audit.env.ps1 (ignoré par git,
#      ne jamais committer de secret).
#   2. Renseigner un compte en lecture seule (SELECT sur
#      DBA_FEATURE_USAGE_STATISTICS, ou rôle SELECT_CATALOG_ROLE) valable
#      pour les instances de config/oracle-instances.example.csv qui ne
#      précisent pas leurs propres Username/PasswordEnvVar.
#   3. Charger avant exécution : . .\config\oracle-audit.env.ps1

$env:ORACLE_AUDIT_USER     = ''
$env:ORACLE_AUDIT_PASSWORD = ''

# Le mot de passe ne peut pas contenir d'espace, ni l'un des caractères
# ' / @ (limite de la syntaxe "CONNECT user/password@connectString" de
# sqlplus — voir scripts/OracleSqlPlusClient.psm1).

# --- Comptes spécifiques à certaines instances (optionnel) ---
# Une ligne de config/oracle-instances.csv peut référencer un autre nom de
# variable via sa colonne PasswordEnvVar, par exemple :
# $env:ORACLE_AUDIT_PASSWORD_TEST = ''
