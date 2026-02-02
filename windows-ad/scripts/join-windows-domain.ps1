# PowerShell Script - Ingressar estação Windows no domínio

Write-Host "Ingressando no domínio ALMT..." -ForegroundColor Yellow

# Configurar DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
    -ServerAddresses "192.168.100.10"

# Credenciais
$Domain = "almt.local"
$User = "Administrator"
$Password = "Passw0rd123!"
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential("$Domain\$User", $SecurePassword)

# Ingressar no domínio
Add-Computer -DomainName $Domain `
    -Credential $Credential `
    -NewName "WIN10-CLIENT01" `
    -OUPath "OU=Computadores,DC=almt,DC=local" `
    -Force

Write-Host "Computador ingressado no domínio. Reinicie para aplicar." -ForegroundColor Green