# Exportar GPOs do Windows AD para migração

param(
    [string]$ExportPath = "C:\GPO-Migration",
    [switch]$IncludeUsers,
    [switch]$IncludeGroups
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "EXPORTANDO CONFIGURAÇÕES DO AD PARA MIGRAÇÃO" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Criar estrutura de diretórios
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $ExportPath "AD-Backup-$Timestamp"

$Directories = @(
    "$BackupDir\GPOs",
    "$BackupDir\Users",
    "$BackupDir\Groups",
    "$BackupDir\OUs",
    "$BackupDir\DNS",
    "$BackupDir\Reports"
)

foreach ($dir in $Directories) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Write-Host "[1/8] Exportando GPOs..." -ForegroundColor Yellow

# Exportar todas as GPOs
$GPOs = Get-GPO -All
$GPOReport = @()

foreach ($GPO in $GPOs) {
    Write-Host "  Exportando: $($GPO.DisplayName)" -ForegroundColor Gray
    
    # Backup da GPO
    $GPOPath = Join-Path "$BackupDir\GPOs" $GPO.DisplayName
    Backup-Gpo -Guid $GPO.Id -Path "$BackupDir\GPOs" -ErrorAction SilentlyContinue
    
    # Relatório HTML
    $GPO | Export-GPOReport -Path "$GPOPath.html" -ReportType Html
    
    # Relatório XML para análise
    $GPO | Export-GPOReport -Path "$GPOPath.xml" -ReportType Xml
    
    # Análise de compatibilidade com Samba
    $Compatibility = @{
        "Auditing Policy" = "Partial"
        "DNS Query Timeout" = "High"
        "HORA_ALMT" = "High"
        "Firewall_Windows" = "None"
        "*RESTRICAO*" = "None"
        "*Install*" = "Script"
        "*Script*" = "Script"
        "*Wallpaper*" = "None"
    }
    
    $CompatLevel = "Unknown"
    foreach ($key in $Compatibility.Keys) {
        if ($GPO.DisplayName -like $key) {
            $CompatLevel = $Compatibility[$key]
            break
        }
    }
    
    $GPOReport += [PSCustomObject]@{
        Name = $GPO.DisplayName
        GUID = $GPO.Id.ToString()
        Created = $GPO.CreationTime
        Modified = $GPO.ModificationTime
        Compatibility = $CompatLevel
        MigrationMethod = switch ($CompatLevel) {
            "High" { "Native Samba Policy" }
            "Partial" { "Alternative Script" }
            "Script" { "PowerShell Script" }
            "None" { "Not Migratable" }
            default { "Needs Analysis" }
        }
    }
}

# Exportar relatório CSV
$GPOReport | Export-Csv -Path "$BackupDir\Reports\gpo-analysis.csv" -NoTypeInformation -Encoding UTF8

Write-Host "[2/8] Exportando estrutura de OUs..." -ForegroundColor Yellow

# Exportar OUs
$OUs = Get-ADOrganizationalUnit -Filter * -Properties *
$OUs | Export-Clixml -Path "$BackupDir\OUs\organizational-units.xml"
$OUs | Select-Object Name, DistinguishedName, Description | Export-Csv -Path "$BackupDir\OUs\ous.csv" -NoTypeInformation

Write-Host "[3/8] Exportando usuários..." -ForegroundColor Yellow

if ($IncludeUsers) {
    $Users = Get-ADUser -Filter * -Properties *
    $Users | Export-Clixml -Path "$BackupDir\Users\all-users.xml"
    
    # Exportar dados básicos para CSV
    $UserData = $Users | Select-Object @(
        "SamAccountName",
        "UserPrincipalName",
        "GivenName",
        "Surname",
        "DisplayName",
        "Enabled",
        "PasswordNeverExpires",
        "PasswordLastSet",
        "LastLogonDate",
        "EmailAddress",
        "Department",
        "Title",
        "DistinguishedName"
    )
    
    $UserData | Export-Csv -Path "$BackupDir\Users\users.csv" -NoTypeInformation -Encoding UTF8
}

Write-Host "[4/8] Exportando grupos..." -ForegroundColor Yellow

if ($IncludeGroups) {
    $Groups = Get-ADGroup -Filter * -Properties *
    $Groups | Export-Clixml -Path "$BackupDir\Groups\all-groups.xml"
    
    # Exportar membros dos grupos
    $GroupMembers = foreach ($Group in $Groups) {
        $Members = Get-ADGroupMember -Identity $Group -Recursive
        foreach ($Member in $Members) {
            [PSCustomObject]@{
                GroupName = $Group.Name
                GroupDN = $Group.DistinguishedName
                MemberName = $Member.Name
                MemberDN = $Member.DistinguishedName
                MemberType = $Member.ObjectClass
            }
        }
    }
    
    $GroupMembers | Export-Csv -Path "$BackupDir\Groups\group-members.csv" -NoTypeInformation -Encoding UTF8
}

Write-Host "[5/8] Exportando políticas de senha..." -ForegroundColor Yellow

# Exportar políticas de domínio
$PasswordPolicy = Get-ADDefaultDomainPasswordPolicy
$PasswordPolicy | Export-Clixml -Path "$BackupDir\Reports\domain-password-policy.xml"

# Exportar em formato legível
$PolicyText = @"
DOMAIN PASSWORD POLICY
======================
Complexity Enabled: $($PasswordPolicy.ComplexityEnabled)
Lockout Duration: $($PasswordPolicy.LockoutDuration)
Lockout Threshold: $($PasswordPolicy.LockoutThreshold)
Max Password Age: $($PasswordPolicy.MaxPasswordAge)
Min Password Age: $($PasswordPolicy.MinPasswordAge)
Min Password Length: $($PasswordPolicy.MinPasswordLength)
Password History Count: $($PasswordPolicy.PasswordHistoryCount)
"@

$PolicyText | Out-File -FilePath "$BackupDir\Reports\password-policy.txt" -Encoding UTF8

Write-Host "[6/8] Exportando DNS Zones..." -ForegroundColor Yellow

# Exportar zonas DNS
try {
    $Zones = Get-DnsServerZone
    $Zones | Export-Clixml -Path "$BackupDir\DNS\dns-zones.xml"
    
    # Exportar registros A
    $ARecords = foreach ($Zone in $Zones | Where-Object {$_.ZoneType -eq "Primary"}) {
        Get-DnsServerResourceRecord -ZoneName $Zone.ZoneName -RRType A -ErrorAction SilentlyContinue
    }
    
    $ARecords | Export-Clixml -Path "$BackupDir\DNS\dns-a-records.xml"
}
catch {
    Write-Host "  Aviso: Não foi possível exportar DNS: $_" -ForegroundColor Yellow
}

Write-Host "[7/8] Exportando relações de confiança..." -ForegroundColor Yellow

# Exportar trusts
$Trusts = Get-ADTrust -Filter *
$Trusts | Export-Clixml -Path "$BackupDir\Reports\domain-trusts.xml"

Write-Host "[8/8] Gerando relatório de migração..." -ForegroundColor Yellow

# Gerar relatório HTML
$HTMLReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Relatório de Migração AD → Samba AD</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #2c3e50; }
        h2 { color: #3498db; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f2f2f2; }
        .compatible { background-color: #d4edda; }
        .partial { background-color: #fff3cd; }
        .incompatible { background-color: #f8d7da; }
        .stats { background-color: #e9ecef; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Relatório de Migração AD DS → Samba AD</h1>
    <p><strong>Data:</strong> $(Get-Date)</p>
    <p><strong>Domínio Origem:</strong> $((Get-ADDomain).DNSRoot)</p>
    <p><strong>Backup ID:</strong> $Timestamp</p>
    
    <div class="stats">
        <h2>Estatísticas</h2>
        <p><strong>GPOs Exportadas:</strong> $($GPOs.Count)</p>
        <p><strong>OUs Exportadas:</strong> $($OUs.Count)</p>
        <p><strong>Usuários Exportados:</strong> $(if($IncludeUsers){$Users.Count}else{"N/A"})</p>
        <p><strong>Grupos Exportados:</strong> $(if($IncludeGroups){$Groups.Count}else{"N/A"})</p>
    </div>
    
    <h2>Análise de Compatibilidade GPO</h2>
    <table>
        <tr>
            <th>GPO</th>
            <th>Compatibilidade</th>
            <th>Método de Migração</th>
        </tr>
"@

foreach ($gpo in $GPOReport) {
    $CssClass = switch ($gpo.Compatibility) {
        "High" { "compatible" }
        "Partial" { "partial" }
        "Script" { "partial" }
        "None" { "incompatible" }
        default { "" }
    }
    
    $HTMLReport += @"
        <tr class="$CssClass">
            <td>$($gpo.Name)</td>
            <td>$($gpo.Compatibility)</td>
            <td>$($gpo.MigrationMethod)</td>
        </tr>
"@
}

$HTMLReport += @"
    </table>
    
    <h2>Arquivos Exportados</h2>
    <ul>
        <li>GPOs: $BackupDir\GPOs\</li>
        <li>Usuários: $BackupDir\Users\</li>
        <li>Grupos: $BackupDir\Groups\</li>
        <li>OUs: $BackupDir\OUs\</li>
        <li>DNS: $BackupDir\DNS\</li>
        <li>Relatórios: $BackupDir\Reports\</li>
    </ul>
    
    <h2>Próximos Passos</h2>
    <ol>
        <li>Analisar compatibilidade das GPOs com Samba AD</li>
        <li>Converter scripts VBS para PowerShell (se aplicável)</li>
        <li>Migrar usuários e grupos</li>
        <li>Configurar políticas equivalentes no Samba</li>
        <li>Testar integração com aplicações</li>
    </ol>
</body>
</html>
"@

$HTMLReport | Out-File -FilePath "$BackupDir\Reports\migration-report.html" -Encoding UTF8

# Copiar para pasta compartilhada com Vagrant
if (Test-Path "C:\vagrant\migration\reports") {
    Copy-Item "$BackupDir\Reports\*" -Destination "C:\vagrant\migration\reports\" -Recurse -Force
}

Write-Host "=========================================" -ForegroundColor Green
Write-Host "EXPORTAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
Write-Host "Local: $BackupDir" -ForegroundColor Yellow
Write-Host "Relatório: $BackupDir\Reports\migration-report.html" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Green