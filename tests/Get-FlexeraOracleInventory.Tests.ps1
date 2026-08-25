BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Get-FlexeraOracleInventory.ps1'
    $fixturePath = Join-Path $PSScriptRoot 'fixtures'
    $outputPath = Join-Path $TestDrive 'oracle-options.csv'

    $shell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile', '-File', $scriptPath,
        '-ReportCsv', (Join-Path $fixturePath 'oracle-server-worksheet.csv'),
        '-OutputCsv', $outputPath
    )
    $process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
    $rows = @(Import-Csv -LiteralPath $outputPath)
}

Describe 'Get-FlexeraOracleInventory' {
    It 'termine sans erreur avec un export Oracle Server Worksheet' {
        $process.ExitCode | Should -Be 0
    }

    It 'éclate les options et management packs en une ligne chacun' {
        $prod = @($rows | Where-Object InstanceName -eq 'PROD1')
        $prod.Count | Should -Be 3
        $prod.OptionOrManagementPack | Should -Contain 'Partitioning'
        $prod.OptionOrManagementPack | Should -Contain 'Diagnostics Pack'
        $prod.OptionOrManagementPack | Should -Contain 'Tuning Pack'
    }

    It 'conserve les métadonnées de l instance' {
        $partitioning = $rows | Where-Object OptionOrManagementPack -eq 'Partitioning'
        $partitioning.PhysicalServerName | Should -Be 'esx01'
        $partitioning.VirtualServerName | Should -Be 'ora-vm01'
        $partitioning.ProductVersion | Should -Be '19c'
        $partitioning.ProductEdition | Should -Be 'Enterprise Edition'
        $partitioning.LicenseMetric | Should -Be 'Processor'
        $partitioning.DatabaseLicensesInUse | Should -Be '4'
        $partitioning.OptionInUse | Should -Be 'True'
    }

    It 'conserve les instances sans option par défaut' {
        $dev = @($rows | Where-Object InstanceName -eq 'DEV1')
        $dev.Count | Should -Be 1
        $dev.OptionOrManagementPack | Should -BeNullOrEmpty
        $dev.OptionInUse | Should -Be 'False'
    }

    It 'peut ne sortir que les options réellement en usage' {
        $onlyOptionsPath = Join-Path $TestDrive 'only-options.csv'
        $arguments = @(
            '-NoProfile', '-File', $scriptPath,
            '-ReportCsv', (Join-Path $fixturePath 'oracle-server-worksheet.csv'),
            '-OutputCsv', $onlyOptionsPath,
            '-OnlyOptions'
        )
        $onlyOptionsProcess = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
        $onlyOptionsRows = @(Import-Csv -LiteralPath $onlyOptionsPath)

        $onlyOptionsProcess.ExitCode | Should -Be 0
        $onlyOptionsRows.Count | Should -Be 3
        @($onlyOptionsRows | Where-Object InstanceName -eq 'DEV1').Count | Should -Be 0
    }

    It 'charge un fichier de configuration et utilise le répertoire de sortie configuré' {
        $configuredOutputDir = Join-Path $TestDrive 'configured-reports'
        $configPath = Join-Path $TestDrive 'flexera.env.ps1'
        Set-Content -LiteralPath $configPath -Encoding UTF8 -Value "`$env:FLEXERA_REPORT_DIR = '$configuredOutputDir'"

        $arguments = @(
            '-NoProfile', '-File', $scriptPath,
            '-ReportCsv', (Join-Path $fixturePath 'oracle-server-worksheet.csv'),
            '-ConfigFile', $configPath
        )
        $configuredProcess = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru
        $generated = @(Get-ChildItem -LiteralPath $configuredOutputDir -Filter 'oracle-options-*.csv' -File)

        $configuredProcess.ExitCode | Should -Be 0
        $generated.Count | Should -Be 1
    }

    It 'donne priorité à la ligne de commande sur le fichier de configuration' {
        $configuredOutputDir = Join-Path $TestDrive 'should-not-be-used'
        $explicitOutputPath = Join-Path $TestDrive 'explicit-output.csv'
        $configPath = Join-Path $TestDrive 'override.env.ps1'
        Set-Content -LiteralPath $configPath -Encoding UTF8 -Value "`$env:FLEXERA_REPORT_DIR = '$configuredOutputDir'"

        $arguments = @(
            '-NoProfile', '-File', $scriptPath,
            '-ReportCsv', (Join-Path $fixturePath 'oracle-server-worksheet.csv'),
            '-ConfigFile', $configPath,
            '-OutputCsv', $explicitOutputPath
        )
        $overrideProcess = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru

        $overrideProcess.ExitCode | Should -Be 0
        Test-Path -LiteralPath $explicitOutputPath | Should -BeTrue
        Test-Path -LiteralPath $configuredOutputDir | Should -BeFalse
    }
}
