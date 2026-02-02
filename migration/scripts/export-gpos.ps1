# Exportar GPOs do Windows AD para análise de migração

$ExportPath = "C:\GPO-Export"
$Date = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupPath = "$ExportPath\GPO-Backup-$Date"

# Criar diretório
New-Item -ItemType Directory -Path $BackupPath -Force

# Backup de todas as GPOs
Backup-Gpo -All -Path $BackupPath

# Exportar relatório HTML de cada GPO
$GPOs = Get-GPO -All
foreach ($GPO in $GPOs) {
    $GPO | Export-GPOReport -Path "$BackupPath\$($GPO.DisplayName).html" -ReportType Html
    $GPO | Export-GPOReport -Path "$BackupPath\$($GPO.DisplayName).xml" -ReportType Xml
}

# Exportar configurações do domínio
Get-ADDefaultDomainPasswordPolicy | Export-Clixml "$BackupPath\DomainPasswordPolicy.xml"
Get-ADFineGrainedPasswordPolicy -Filter * | Export-Clixml "$BackupPath\FineGrainedPolicies.xml"

Write-Host "GPOs exportadas para: $BackupPath" -ForegroundColor Green