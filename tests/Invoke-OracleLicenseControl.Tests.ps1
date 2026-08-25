BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-OracleLicenseControl.ps1'
    $fixturePath = Join-Path $PSScriptRoot 'fixtures'
    $outputPath = Join-Path $TestDrive 'result.csv'

    # Le script utilise un code de sortie métier ; on l'exécute donc dans un
    # processus enfant pour ne pas interrompre Pester.
    $shell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile', '-File', $scriptPath,
        '-FlexeraCsv', (Join-Path $fixturePath 'flexera.csv'),
        '-ColumnMap', (Join-Path $fixturePath 'column-map.json'),
        '-OutputCsv', $outputPath,
        '-Culture', 'en-US'
    )
    $process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
    $rows = @(Import-Csv -LiteralPath $outputPath)
}

Describe 'Invoke-OracleLicenseControl' {
    It 'renvoie le code 2 lorsqu''un déficit existe' {
        $process.ExitCode | Should -Be 2
    }

    It 'calcule le déficit et le risque' {
        $database = $rows | Where-Object Licence -eq 'Oracle Database Enterprise Edition'
        $database.Ecart | Should -Be '-2'
        $database.Statut | Should -Be 'Déficit'
        $database.Risque | Should -Be '2'
    }

    It 'classe les écarts nuls et positifs' {
        ($rows | Where-Object Statut -eq 'Équilibre').Count | Should -Be 1
        ($rows | Where-Object Statut -eq 'Surplus').Count | Should -Be 1
    }

    It 'agrège les lignes de même licence et métrique' {
        $pack = $rows | Where-Object Licence -eq 'Oracle Diagnostics Pack'
        $pack.DroitsAcquis | Should -Be '120'
        $pack.Consommation | Should -Be '95'
        $pack.Ecart | Should -Be '25'
    }
}
