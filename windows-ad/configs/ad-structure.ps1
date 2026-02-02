# Configurar estrutura detalhada do AD

# Criar OUs específicas da ALMT
$OUs = @(
    @{Name="ALMT"; Path="DC=almt,DC=local"; Description="Raiz ALMT"},
    @{Name="Diretoria"; Path="OU=ALMT,DC=almt,DC=local"; Description="Diretoria Geral"},
    @{Name="Procuradoria"; Path="OU=ALMT,DC=almt,DC=local"; Description="Procuradoria Geral"},
    @{Name="Orcamento"; Path="OU=ALMT,DC=almt,DC=local"; Description="Orçamento e Finanças"},
    @{Name="TI"; Path="OU=ALMT,DC=almt,DC=local"; Description="Tecnologia da Informação"},
    @{Name="Suporte"; Path="OU=TI,OU=ALMT,DC=almt,DC=local"; Description="Suporte Técnico"},
    @{Name="Infraestrutura"; Path="OU=TI,OU=ALMT,DC=almt,DC=local"; Description="Infraestrutura"}
)

foreach ($ou in $OUs) {
    New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -Description $ou.Description -ProtectedFromAccidentalDeletion $true
}

# Criar grupos específicos
$Groups = @(
    @{Name="ALMT_Domain_Admins"; Scope="Universal"; Category="Security"; Description="Administradores do Domínio ALMT"},
    @{Name="ALMT_Usuarios"; Scope="Global"; Category="Security"; Description="Usuários do Domínio ALMT"},
    @{Name="TI_Administradores"; Scope="Global"; Category="Security"; Description="Administradores de TI"},
    @{Name="TI_Suporte"; Scope="Global"; Category="Security"; Description="Equipe de Suporte Técnico"},
    @{Name="PG_Admin_Local"; Scope="Global"; Category="Security"; Description="Administradores Locais Procuradoria"}
)

foreach ($group in $Groups) {
    New-ADGroup -Name $group.Name -GroupScope $group.Scope -GroupCategory $group.Category `
        -Path "OU=Grupos,DC=almt,DC=local" -Description $group.Description
}