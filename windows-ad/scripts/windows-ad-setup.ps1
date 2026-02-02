# PowerShell Script - Instalar e Configurar AD DS Windows Server

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "INSTALANDO ACTIVE DIRECTORY DOMAIN SERVICES" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Configurações
$DomainName = "almt.local"
$DomainNetBIOS = "ALMT"
$SafeModePassword = ConvertTo-SecureString "Passw0rd123!" -AsPlainText -Force
$AdminPassword = ConvertTo-SecureString "Passw0rd123!" -AsPlainText -Force

Write-Host "[1/8] Configurando adaptador de rede..." -ForegroundColor Yellow

# Configurar IP estático
New-NetIPAddress -InterfaceAlias "Ethernet" `
    -IPAddress "192.168.100.10" `
    -PrefixLength 24 `
    -DefaultGateway "192.168.100.1"

# Configurar DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
    -ServerAddresses ("127.0.0.1", "8.8.8.8")

Write-Host "[2/8] Alterando nome do computador..." -ForegroundColor Yellow
Rename-Computer -NewName "DC-WINDOWS" -Force

Write-Host "[3/8] Instalando funções do Windows Server..." -ForegroundColor Yellow

# Instalar AD DS e DNS
Install-WindowsFeature -Name "AD-Domain-Services" `
    -IncludeManagementTools `
    -IncludeAllSubFeature

Install-WindowsFeature -Name "DNS" `
    -IncludeManagementTools

Write-Host "[4/8] Promovendo a Controlador de Domínio..." -ForegroundColor Yellow

# Promover a DC
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetBIOS `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDns:$true `
    -NoRebootOnCompletion:$true `
    -Force:$true

Write-Host "[5/8] Configurando administrador..." -ForegroundColor Yellow

# Configurar conta administrador
Set-ADAccountPassword -Identity "Administrator" `
    -NewPassword $AdminPassword `
    -Reset

Enable-ADAccount -Identity "Administrator"

Write-Host "[6/8] Criando estrutura do domínio..." -ForegroundColor Yellow

# Criar OUs (Organizational Units)
New-ADOrganizationalUnit -Name "Usuarios" -Path "DC=almt,DC=local"
New-ADOrganizationalUnit -Name "Computadores" -Path "DC=almt,DC=local"
New-ADOrganizationalUnit -Name "Servidores" -Path "DC=almt,DC=local"
New-ADOrganizationalUnit -Name "Grupos" -Path "DC=almt,DC=local"

# Criar grupos
New-ADGroup -Name "Domain Admins" -GroupScope Universal -GroupCategory Security -Path "OU=Grupos,DC=almt,DC=local"
New-ADGroup -Name "Domain Users" -GroupScope Global -GroupCategory Security -Path "OU=Grupos,DC=almt,DC=local"
New-ADGroup -Name "Administradores" -GroupScope Global -GroupCategory Security -Path "OU=Grupos,DC=almt,DC=local"
New-ADGroup -Name "Usuarios Comuns" -GroupScope Global -GroupCategory Security -Path "OU=Grupos,DC=almt,DC=local"
New-ADGroup -Name "Suporte Tecnico" -GroupScope Global -GroupCategory Security -Path "OU=Grupos,DC=almt,DC=local"

Write-Host "[7/8] Criando usuários de teste..." -ForegroundColor Yellow

# Criar usuários
$Users = @(
    @{GivenName="Administrador"; Surname="Sistema"; SamAccountName="admin"; Password="Passw0rd123!"},
    @{GivenName="Joao"; Surname="Silva"; SamAccountName="joao.silva"; Password="Senha123!"},
    @{GivenName="Maria"; Surname="Souza"; SamAccountName="maria.souza"; Password="Senha123!"},
    @{GivenName="Carlos"; Surname="Santos"; SamAccountName="carlos.santos"; Password="Senha123!"}
)

foreach ($User in $Users) {
    New-ADUser `
        -GivenName $User.GivenName `
        -Surname $User.Surname `
        -SamAccountName $User.SamAccountName `
        -UserPrincipalName "$($User.SamAccountName)@$DomainName" `
        -Name "$($User.GivenName) $($User.Surname)" `
        -DisplayName "$($User.GivenName) $($User.Surname)" `
        -Path "OU=Usuarios,DC=almt,DC=local" `
        -AccountPassword (ConvertTo-SecureString $User.Password -AsPlainText -Force) `
        -Enabled $true `
        -PasswordNeverExpires $false `
        -ChangePasswordAtLogon $false
}

# Adicionar usuários aos grupos
Add-ADGroupMember -Identity "Domain Admins" -Members "admin"
Add-ADGroupMember -Identity "Domain Users" -Members "admin", "joao.silva", "maria.souza", "carlos.santos"
Add-ADGroupMember -Identity "Administradores" -Members "admin"
Add-ADGroupMember -Identity "Usuarios Comuns" -Members "joao.silva", "maria.souza", "carlos.santos"

Write-Host "[8/8] Configurando políticas de domínio..." -ForegroundColor Yellow

# Configurar política de senha via PowerShell
$PasswordPolicy = @{
    "ComplexityEnabled" = $true
    "LockoutDuration" = "00:30:00"
    "LockoutObservationWindow" = "00:30:00"
    "LockoutThreshold" = 5
    "MaxPasswordAge" = "90.00:00:00"
    "MinPasswordAge" = "1.00:00:00"
    "MinPasswordLength" = 8
    "PasswordHistoryCount" = 24
    "ReversibleEncryptionEnabled" = $false
}

foreach ($Policy in $PasswordPolicy.GetEnumerator()) {
    Set-ADDefaultDomainPasswordPolicy -Identity $DomainName `
        -Replace @{$Policy.Key = $Policy.Value}
}

Write-Host "=========================================" -ForegroundColor Green
Write-Host "AD DS CONFIGURADO COM SUCESSO!" -ForegroundColor Green
Write-Host "Domínio: $DomainName" -ForegroundColor Yellow
Write-Host "Usuário administrador: admin" -ForegroundColor Yellow
Write-Host "Senha: Passw0rd123!" -ForegroundColor Yellow
Write-Host "Reinicie o servidor para concluir" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Green