BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'OracleSqlPlusClient.psm1') -Force
}

Describe 'New-SqlPlusLoginScript' {
    It 'inclut SET DEFINE OFF pour neutraliser la substitution SQL*Plus' {
        $script = New-SqlPlusLoginScript -Username 'sam_audit' -Password 'secret123' -ConnectString 'dbhost:1521/PDB1' -SqlScriptPath '/opt/sql/options-packs-usage.sql'
        $script | Should -Match '(?m)^SET DEFINE OFF$'
    }

    It 'construit la ligne CONNECT avec utilisateur, mot de passe et chaîne de connexion "easy connect"' {
        $script = New-SqlPlusLoginScript -Username 'sam_audit' -Password 'secret123' -ConnectString 'dbhost:1521/PDB1' -SqlScriptPath '/opt/sql/options-packs-usage.sql'
        $script | Should -Match '(?m)^CONNECT sam_audit/secret123@dbhost:1521/PDB1$'
    }

    It 'référence le script SQL fourni' {
        $script = New-SqlPlusLoginScript -Username 'u' -Password 'p' -ConnectString 'c' -SqlScriptPath '/opt/sql/options-packs-usage.sql'
        $script | Should -Match ([regex]::Escape('@"/opt/sql/options-packs-usage.sql"'))
    }

    It 'quitte sqlplus après exécution' {
        $script = New-SqlPlusLoginScript -Username 'u' -Password 'p' -ConnectString 'c' -SqlScriptPath '/opt/sql/options-packs-usage.sql'
        $script | Should -Match '(?m)^EXIT$'
    }

    It 'refuse un nom d''utilisateur contenant un caractère syntaxiquement ambigu' {
        { New-SqlPlusLoginScript -Username 'sam/audit' -Password 'p' -ConnectString 'c' -SqlScriptPath '/opt/sql/options-packs-usage.sql' } | Should -Throw
    }

    It 'refuse un mot de passe contenant une apostrophe' {
        { New-SqlPlusLoginScript -Username 'u' -Password "p'assword" -ConnectString 'c' -SqlScriptPath '/opt/sql/options-packs-usage.sql' } | Should -Throw
    }

    It 'refuse un mot de passe contenant une arobase (ambiguïté avec le séparateur de connexion)' {
        { New-SqlPlusLoginScript -Username 'u' -Password 'p@ssword' -ConnectString 'c' -SqlScriptPath '/opt/sql/options-packs-usage.sql' } | Should -Throw
    }

    It 'refuse une chaîne de connexion contenant un espace' {
        { New-SqlPlusLoginScript -Username 'u' -Password 'p' -ConnectString 'db host:1521/PDB1' -SqlScriptPath '/opt/sql/options-packs-usage.sql' } | Should -Throw
    }

    It 'accepte un slash dans la chaîne de connexion (syntaxe easy connect host:port/service)' {
        { New-SqlPlusLoginScript -Username 'u' -Password 'p' -ConnectString 'dbhost:1521/PDB1' -SqlScriptPath '/opt/sql/options-packs-usage.sql' } | Should -Not -Throw
    }
}
