-- Interroge DBA_FEATURE_USAGE_STATISTICS de l'instance/PDB connectée pour
-- lister les fonctionnalités Oracle Database dont l'usage a été détecté au
-- moins une fois. La vue est alimentée par Oracle Database lui-même (job
-- MMON, échantillonnage périodique) : elle ne nécessite aucun accès aux
-- données applicatives, seulement une connexion avec le rôle SELECT_CATALOG
-- (ou équivalent).
--
-- Fourni à titre indicatif : ce dépôt ne prétend PAS reproduire le mapping
-- officiel « fonctionnalité détectée -> option/pack sous contrat » établi
-- par Oracle. Pour un contrôle de conformité formel, recouper la sortie de
-- ce script avec le script Oracle Support officiel (Doc ID 1317265.1,
-- "Important Changes to Oracle Database Options/Management Packs Usage
-- Reporting"), auquel ce dépôt n'a pas de droit de redistribution.
--
-- En base multitenant (12c+), chaque PDB tient sa propre statistique :
-- connectez-vous directement au service de chaque PDB à auditer plutôt que
-- d'interroger la CDB racine seule.

SET PAGESIZE 50000
SET LINESIZE 32000
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET ECHO OFF
SET VERIFY OFF
SET HEADING ON
SET MARKUP CSV ON QUOTE ON

SELECT
    name                                                    AS feature_name,
    version                                                 AS version,
    detected_usages                                         AS detected_usages,
    CASE WHEN currently_used = 'TRUE' THEN 'Oui' ELSE 'Non' END AS actuellement_utilise,
    TO_CHAR(first_usage_date, 'YYYY-MM-DD"T"HH24:MI:SS')    AS premiere_utilisation,
    TO_CHAR(last_usage_date,  'YYYY-MM-DD"T"HH24:MI:SS')    AS derniere_utilisation
FROM dba_feature_usage_statistics
WHERE detected_usages > 0
ORDER BY name;
