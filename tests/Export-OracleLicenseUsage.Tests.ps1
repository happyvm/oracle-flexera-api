BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Export-OracleLicenseUsage.ps1'
    $fixturePath = Join-Path $PSScriptRoot 'fixtures'
    $outputPath = Join-Path $TestDrive 'usage.csv'

    $shell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile', '-File', $scriptPath,
        '-LicensesJson', (Join-Path $fixturePath 'licenses.json'),
        '-ConsumptionJsonDir', (Join-Path $fixturePath 'consumption'),
        '-OutputCsv', $outputPath
    )
    $process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
    $rows = @(Import-Csv -LiteralPath $outputPath)
}

Describe 'Export-OracleLicenseUsage' {
    It 'se termine sans erreur' {
        $process.ExitCode | Should -Be 0
    }

    It 'ne garde que les licences de l''éditeur filtré (Oracle par défaut)' {
        $rows | Where-Object Licence -like 'Microsoft*' | Should -BeNullOrEmpty
    }

    It 'liste une ligne par couple licence/instance/option, dédupliquée' {
        $ee = $rows | Where-Object Licence -eq 'Oracle Database Enterprise Edition'
        $ee.Count | Should -Be 3
        ($ee | Where-Object { $_.Instance -eq 'thsm01d~CDB_ROOT' -and $_.Option -eq 'Oracle Database Enterprise Edition' }).Count | Should -Be 1
    }

    It 'distingue une option supplémentaire du produit de base' {
        $partitioning = $rows | Where-Object Option -eq 'Oracle Partitioning'
        $partitioning.Instance | Should -Be 'thsm01d~CDB_ROOT'
        $partitioning.EstOptionSupplementaire | Should -Be 'Oui'

        $base = $rows | Where-Object { $_.Instance -eq 'thsm01d~CDB_ROOT' -and $_.Option -eq 'Oracle Database Enterprise Edition' }
        $base.EstOptionSupplementaire | Should -Be 'Non'
    }

    It 'ignore les consommations sans instance associée, sans option connue' {
        $diag = $rows | Where-Object Licence -eq 'Oracle Diagnostics Pack'
        $diag.Count | Should -Be 1
        $diag.Instance | Should -Be 'prod02~PDB1'
        $diag.Option | Should -BeNullOrEmpty
    }
}
