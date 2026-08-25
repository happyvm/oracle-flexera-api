BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Compare-OracleLicenseUsage.ps1'
    $fixturePath = Join-Path $PSScriptRoot 'fixtures'
    $outputPath = Join-Path $TestDrive 'diff.csv'

    # Le script utilise un code de sortie métier ; on l'exécute donc dans un
    # processus enfant pour ne pas interrompre Pester.
    $shell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile', '-File', $scriptPath,
        '-BeforeCsv', (Join-Path $fixturePath 'usage-j1.csv'),
        '-AfterCsv', (Join-Path $fixturePath 'usage-j2.csv'),
        '-OutputCsv', $outputPath
    )
    $process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
    $rows = @(Import-Csv -LiteralPath $outputPath)
}

Describe 'Compare-OracleLicenseUsage' {
    It 'renvoie le code 2 lorsqu''un nouvel usage est détecté' {
        $process.ExitCode | Should -Be 2
    }

    It 'détecte un nouvel usage (base absente en J1, présente en J2)' {
        $row = $rows | Where-Object Instance -eq 'prod03~PDB3'
        $row.PresentJ1 | Should -Be 'Non'
        $row.PresentJ2 | Should -Be 'Oui'
        $row.Evenement | Should -Be 'NouvelUsage'
    }

    It 'détecte un arrêt d''usage (base présente en J1, absente en J2)' {
        $row = $rows | Where-Object Instance -eq 'test01~PDB2'
        $row.PresentJ1 | Should -Be 'Oui'
        $row.PresentJ2 | Should -Be 'Non'
        $row.Evenement | Should -Be 'UsageArrete'
    }

    It 'classe les usages inchangés' {
        $row = $rows | Where-Object Instance -eq 'thsm01d~CDB_ROOT'
        $row.Evenement | Should -Be 'Inchange'
    }

    It 'trie les nouveaux usages en premier' {
        $rows[0].Evenement | Should -Be 'NouvelUsage'
    }
}

Describe 'Compare-OracleLicenseUsage -KeyColumns Licence,Instance,Option' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Compare-OracleLicenseUsage.ps1'
        $fixturePath = Join-Path $PSScriptRoot 'fixtures'
        $outputPath = Join-Path $TestDrive 'diff-options.csv'

        $shell = (Get-Process -Id $PID).Path
        $arguments = @(
            '-NoProfile', '-File', $scriptPath,
            '-BeforeCsv', (Join-Path $fixturePath 'usage-options-j1.csv'),
            '-AfterCsv', (Join-Path $fixturePath 'usage-options-j2.csv'),
            '-KeyColumns', 'Licence,Instance,Option',
            '-OutputCsv', $outputPath
        )
        $process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
        $optionRows = @(Import-Csv -LiteralPath $outputPath)
    }

    It 'renvoie le code 2 lorsqu''une nouvelle option est détectée sur une instance' {
        $process.ExitCode | Should -Be 2
    }

    It 'détecte une option nouvellement utilisée sur une instance déjà connue' {
        $row = $optionRows | Where-Object Option -eq 'Oracle Partitioning'
        $row.Instance | Should -Be 'thsm01d~CDB_ROOT'
        $row.PresentJ1 | Should -Be 'Non'
        $row.PresentJ2 | Should -Be 'Oui'
        $row.Evenement | Should -Be 'NouvelUsage'
    }

    It 'ne signale pas l''option de base comme un nouvel usage' {
        $row = $optionRows | Where-Object Option -eq 'Oracle Database Enterprise Edition'
        $row.Evenement | Should -Be 'Inchange'
    }
}

Describe 'Compare-OracleLicenseUsage -KeyColumns Instance,Fonctionnalite (rapports Get-OracleDatabaseFeatureUsage)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Compare-OracleLicenseUsage.ps1'
        $fixturePath = Join-Path $PSScriptRoot 'fixtures'
        $outputPath = Join-Path $TestDrive 'diff-features.csv'

        $shell = (Get-Process -Id $PID).Path
        $arguments = @(
            '-NoProfile', '-File', $scriptPath,
            '-BeforeCsv', (Join-Path $fixturePath 'features-j1.csv'),
            '-AfterCsv', (Join-Path $fixturePath 'features-j2.csv'),
            '-KeyColumns', 'Instance,Fonctionnalite',
            '-OutputCsv', $outputPath
        )
        $process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
        $featureRows = @(Import-Csv -LiteralPath $outputPath)
    }

    It 'fonctionne sur des colonnes de clé sans Licence ni Instance imposées par défaut' {
        $process.ExitCode | Should -Be 2
    }

    It 'détecte une fonctionnalité nouvellement utilisée sur une instance déjà connue' {
        $row = $featureRows | Where-Object Fonctionnalite -eq 'Diagnostics Pack Usage'
        $row.Instance | Should -Be 'thsm01d~CDB_ROOT'
        $row.Evenement | Should -Be 'NouvelUsage'
    }

    It 'classe la fonctionnalité déjà observée comme inchangée' {
        $row = $featureRows | Where-Object Fonctionnalite -eq 'Partitioning (user)'
        $row.Evenement | Should -Be 'Inchange'
    }
}
