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
