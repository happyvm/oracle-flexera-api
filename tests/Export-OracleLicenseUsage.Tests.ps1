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

    It 'liste une instance par couple licence/base, dédupliquée' {
        $ee = $rows | Where-Object Licence -eq 'Oracle Database Enterprise Edition'
        $ee.Count | Should -Be 2
        ($ee | Where-Object Instance -eq 'thsm01d~CDB_ROOT').Count | Should -Be 1
    }

    It 'ignore les consommations sans instance associée' {
        $diag = $rows | Where-Object Licence -eq 'Oracle Diagnostics Pack'
        $diag.Count | Should -Be 1
        $diag.Instance | Should -Be 'prod02~PDB1'
    }
}
