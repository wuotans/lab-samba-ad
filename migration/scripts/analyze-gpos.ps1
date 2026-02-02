# Analisar compatibilidade detalhada das GPOs

param(
    [string]$BackupPath = "C:\GPO-Migration",
    [string]$OutputPath = "C:\GPO-Analysis"
)

$ErrorActionPreference = "Stop"

Write-Host "ANALISANDO COMPATIBILIDADE DETALHADA DE GPOS" -ForegroundColor Cyan

# Carregar GPOs exportadas
$GPOs = Get-ChildItem -Path $BackupPath -Filter "*.xml" -Recurse | 
    Where-Object {$_.Name -match "GPO" -and $_.Name -notmatch "report"}

$AnalysisResults = @()

foreach ($GPOFile in $GPOs) {
    [xml]$GPOXml = Get-Content $GPOFile.FullName
    
    $GPOName = $GPOXml.GPO.Name
    Write-Host "Analisando: $GPOName" -ForegroundColor Yellow
    
    # Analisar configurações
    $Settings = @{
        RegistrySettings = 0
        SecuritySettings = 0
        Scripts = 0
        Preferences = 0
        InternetExplorer = 0
        WindowsSpecific = 0
    }
    
    # Contar tipos de configurações
    if ($GPOXml.GPO.Computer.ExtensionData) {
        foreach ($ext in $GPOXml.GPO.Computer.ExtensionData.Extension) {
            switch -Wildcard ($ext.Type) {
                "*Registry*" { $Settings.RegistrySettings++ }
                "*Security*" { $Settings.SecuritySettings++ }
                "*Scripts*" { $Settings.Scripts++ }
                "*InternetExplorer*" { $Settings.InternetExplorer++ }
                "*Windows*" { $Settings.WindowsSpecific++ }
            }
        }
    }
    
    # Determinar compatibilidade
    $Compatibility = "Unknown"
    
    if ($Settings.InternetExplorer -gt 0) {
        $Compatibility = "None"
    }
    elseif ($Settings.WindowsSpecific -gt 10) {
        $Compatibility = "Low"
    }
    elseif ($Settings.RegistrySettings -gt 0 -and $Settings.SecuritySettings -gt 0) {
        $Compatibility = "Partial"
    }
    elseif ($Settings.SecuritySettings -gt 0) {
        $Compatibility = "High"
    }
    else {
        $Compatibility = "Medium"
    }
    
    $AnalysisResults += [PSCustomObject]@{
        GPOName = $GPOName
        File = $GPOFile.Name
        RegistrySettings = $Settings.RegistrySettings
        SecuritySettings = $Settings.SecuritySettings
        Scripts = $Settings.Scripts
        IESettings = $Settings.InternetExplorer
        WindowsSpecific = $Settings.WindowsSpecific
        Compatibility = $Compatibility
        Recommendation = Get-Recommendation -Compatibility $Compatibility -GPOName $GPOName
    }
}

# Exportar análise
$AnalysisResults | Export-Csv -Path "$OutputPath\gpo-detailed-analysis.csv" -NoTypeInformation

# Gerar relatório
$Report = @"
# Análise Detalhada de Compatibilidade GPO

## Data: $(Get-Date)

## Resumo:
- Total de GPOs analisadas: $($AnalysisResults.Count)
- Alta compatibilidade: $(($AnalysisResults | Where-Object {$_.Compatibility -eq 'High'}).Count)
- Compatibilidade parcial: $(($AnalysisResults | Where-Object {$_.Compatibility -eq 'Partial'}).Count)
- Baixa compatibilidade: $(($AnalysisResults | Where-Object {$_.Compatibility -eq 'Low'}).Count)
- Não compatível: $(($AnalysisResults | Where-Object {$_.Compatibility -eq 'None'}).Count)

## Recomendações por Categoria:

### 1. GPOs Totalmente Compatíveis (Alta)
$($AnalysisResults | Where-Object {$_.Compatibility -eq 'High'} | ForEach-Object {
    "- **$($_.GPOName)**: Pode ser migrada diretamente para políticas nativas do Samba"
})

### 2. GPOs Parcialmente Compatíveis
$($AnalysisResults | Where-Object {$_.Compatibility -eq 'Partial'} | ForEach-Object {
    "- **$($_.GPOName)**: Requer conversão para scripts ou configurações alternativas"
})

### 3. GPOs Não Compatíveis
$($AnalysisResults | Where-Object {$_.Compatibility -eq 'None'} | ForEach-Object {
    "- **$($_.GPOName)**: Não suportada pelo Samba. Requer solução alternativa completa"
})

## Matriz de Compatibilidade:
| GPO | Compatibilidade | Recomendação |
|-----|----------------|--------------|
$($AnalysisResults | ForEach-Object {
    "| $($_.GPOName) | $($_.Compatibility) | $($_.Recommendation) |"
})

## Conclusão:
Baseado na análise, $(($AnalysisResults | Where-Object {$_.Compatibility -in @('High','Partial')}).Count) de $($AnalysisResults.Count) GPOs podem ser migradas com algum nível de compatibilidade.
"@

$Report | Out-File -FilePath "$OutputPath\detailed-analysis-report.md" -Encoding UTF8

Write-Host "Análise concluída! Relatório em: $OutputPath" -ForegroundColor Green