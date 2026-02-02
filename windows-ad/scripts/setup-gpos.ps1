# PowerShell Script - Criar as GPOs específicas da sua lista

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "CRIANDO GPOS DO AMBIENTE ALMT" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Função para criar GPO
function New-GPOWithSettings {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$Settings
    )
    
    Write-Host "Criando GPO: $Name" -ForegroundColor Yellow
    
    # Criar GPO
    $GPO = New-GPO -Name $Name -Comment $Description
    
    # Aplicar configurações
    & $Settings $GPO
    
    return $GPO
}

# 1. Auditing Policy
New-GPOWithSettings -Name "Auditing Policy" -Description "Audita conta, eventos, acessos" {
    param($GPO)
    
    # Configurar auditoria via registry
    $AuditSettings = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit]
"ProcessCreationIncludeCmdLine_Enabled"=dword:00000001
"@
    
    $TempFile = [System.IO.Path]::GetTempFileName()
    $AuditSettings | Out-File $TempFile -Encoding ASCII
    
    # Aplicar via regedit
    & regedit.exe /s $TempFile
    Remove-Item $TempFile
}

# 2. DNS Query Timeout
New-GPOWithSettings -Name "DNS Query Timeout" -Description "Configura timeout do DNS" {
    param($GPO)
    
    $RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
    
    # Configurar timeout de DNS
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key $RegistryPath `
        -ValueName "MaxCacheTtl" `
        -Type DWord `
        -Value 1
    
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key $RegistryPath `
        -ValueName "MaxNegativeCacheTtl" `
        -Type DWord `
        -Value 1
}

# 3. HORA_ALMT
New-GPOWithSettings -Name "HORA_ALMT" -Description "Corrige hora dos computadores" {
    param($GPO)
    
    # Configurar NTP
    $RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
    
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key $RegistryPath `
        -ValueName "NtpServer" `
        -Type String `
        -Value "time.windows.com,0x9"
    
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key $RegistryPath `
        -ValueName "Type" `
        -Type String `
        -Value "NTP"
}

# 4. Firewall_Windows (Desabilitar Firewall)
New-GPOWithSettings -Name "Firewall_Windows" -Description "Desabilita firewall do Windows" {
    param($GPO)
    
    $RegistryPath = "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile"
    
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key $RegistryPath `
        -ValueName "EnableFirewall" `
        -Type DWord `
        -Value 0
}

# 5. GPO_SCRIPT_MAPEAMENTO (simulação)
New-GPOWithSettings -Name "GPO_SCRIPT_MAPEAMENTO" -Description "Mapeamento de drives e mensagem" {
    param($GPO)
    
    # Criar script de logon
    $LogonScript = @"
@echo off
echo =========================================
echo Bem-vindo ao dominio ALMT
echo Computador: %COMPUTERNAME%
echo Usuario: %USERNAME%
echo =========================================

net use P: \\dc-windows.almt.local\netlogon
net use U: \\dc-windows.almt.local\users
"@
    
    $ScriptPath = "C:\Windows\SYSVOL\domain\scripts\logon.bat"
    $LogonScript | Out-File $ScriptPath -Encoding ASCII
    
    # Configurar GPO para executar script
    Set-GPLoginScript -Name $GPO.DisplayName -ScriptPath "logon.bat"
}

# 6. GPO_PERFIL_AVANCADO (simulação simplificada)
New-GPOWithSettings -Name "GPO_PERFIL_AVANCADO" -Description "Ambiente controlado" {
    param($GPO)
    
    # Desabilitar prompt de comandos
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
        -ValueName "DisableCMD" `
        -Type DWord `
        -Value 1
    
    # Desabilitar atualizações automáticas
    Set-GPRegistryValue -Name $GPO.DisplayName `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -ValueName "NoAutoUpdate" `
        -Type DWord `
        -Value 1
}

# Criar mais GPOs da sua lista...
Write-Host "`nCriando GPOs de restrição (Internet Explorer)..." -ForegroundColor Yellow

$RestrictionGPOs = @(
    "GPO_AMBUL_RESTRICAO",
    "GPO_COCERIM_RESTRICAO",
    "GPO_COEL_RESTRICAO",
    "GPO_COMIL_RESTRICAO",
    "GPO_CONT_RESTRICAO",
    "GPO_CPI_RESTRICAO",
    "GPO_CST_RESTRICAO",
    "GPO_FAP_RESTRICAO",
    "GPO_GAB_RESTRICAO",
    "GPO_Gel_RESTRICAO",
    "GPO_ISSPL_RESTRICAO",
    "GPO_NUADE_RESTRICAO",
    "GPO_NUCE_RESTRICAO",
    "GPO_NUS_RESTRICAO",
    "GPO_OUVIDORIA_RESTRICAO",
    "GPO_PG_RESTRICAO",
    "GPO_PRESID_RESTRICAO",
    "GPO_RECEP_RESTRICAO",
    "GPO_SCC_RESTRICAO",
    "GPO_SEAP_RESTRICAO",
    "GPO_SECOM_RESTRICAO",
    "GPO_SEGP_RESTRICAO",
    "GPO_SG_RESTRICAO",
    "GPO_SIMPL_RESTRICAO",
    "GPO_SUPE_RESTRICAO",
    "GPO_TVAL_RESTRICAO"
)

foreach ($GpoName in $RestrictionGPOs) {
    New-GPO -Name $GpoName -Comment "Restrições Internet Explorer (legado)"
    Write-Host "  Criada: $GpoName" -ForegroundColor Green
}

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "TODAS AS GPOS CRIADAS COM SUCESSO!" -ForegroundColor Green
Write-Host "Total: $(($RestrictionGPOs.Count + 6)) GPOs" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Green