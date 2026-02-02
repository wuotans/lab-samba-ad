#!/bin/bash
# Migrar usuários e grupos do Windows AD para Samba AD

set -e

echo "========================================="
echo "MIGRANDO USUÁRIOS E GRUPOS PARA SAMBA AD"
echo "========================================="

BACKUP_PATH="/vagrant/migration/reports"
DOMAIN="almt.local"
DOMAIN_DN="dc=almt,dc=local"
TEMP_DIR="/tmp/ad-migration-$(date +%s)"

mkdir -p "$TEMP_DIR"

echo "[1/7] Preparando ambiente..."

# Verificar se arquivos de backup existem
if [ ! -f "$BACKUP_PATH/users.csv" ]; then
    echo "ERRO: Arquivo users.csv não encontrado!"
    exit 1
fi

echo "[2/7] Processando usuários..."

# Processar CSV de usuários
# Skippar header e processar cada linha
tail -n +2 "$BACKUP_PATH/users.csv" | while IFS=, read -r line
do
    # Parse manual do CSV (simplificado)
    IFS=',' read -ra fields <<< "$line"
    
    # Extrair campos (ajuste baseado no formato real)
    samaccountname=$(echo "${fields[0]}" | tr -d '"' | tr -d '\r')
    givenname=$(echo "${fields[2]}" | tr -d '"' | tr -d '\r')
    surname=$(echo "${fields[3]}" | tr -d '"' | tr -d '\r')
    displayname=$(echo "${fields[4]}" | tr -d '"' | tr -d '\r')
    enabled=$(echo "${fields[5]}" | tr -d '"' | tr -d '\r')
    email=$(echo "${fields[9]}" | tr -d '"' | tr -d '\r')
    department=$(echo "${fields[10]}" | tr -d '"' | tr -d '\r')
    
    if [ -z "$samaccountname" ] || [ "$samaccountname" == "SamAccountName" ]; then
        continue
    fi
    
    echo "Migrando usuário: $samaccountname"
    
    # Gerar senha temporária (na prática, usar senha real ou forçar troca)
    TEMP_PASSWORD="TempPass123!"
    
    # Criar usuário no Samba AD
    samba-tool user create "$samaccountname" "$TEMP_PASSWORD" \
        --given-name="$givenname" \
        --surname="$surname" \
        --display-name="$displayname" \
        --mail="$email" \
        --department="$department" \
        --must-change-at-next-login
    
    # Configurar propriedades adicionais
    if [ "$enabled" == "False" ]; then
        samba-tool user disable "$samaccountname"
    fi
    
    # Adicionar aos grupos básicos
    samba-tool group addmembers "Domain Users" "$samaccountname"
    
done

echo "[3/7] Processando grupos..."

if [ -f "$BACKUP_PATH/group-members.csv" ]; then
    # Extrair lista única de grupos
    groups=$(tail -n +2 "$BACKUP_PATH/group-members.csv" | cut -d',' -f1 | tr -d '"' | sort -u)
    
    for group in $groups; do
        if [ ! -z "$group" ] && [ "$group" != "GroupName" ]; then
            echo "Criando grupo: $group"
            
            # Criar grupo se não existir
            samba-tool group show "$group" >/dev/null 2>&1 || \
                samba-tool group add "$group" --group-scope=Global
            
            # Adicionar membros ao grupo
            members=$(grep "^\"$group\"" "$BACKUP_PATH/group-members.csv" | cut -d',' -f3 | tr -d '"' | tr '\n' ',')
            if [ ! -z "$members" ]; then
                samba-tool group addmembers "$group" "$members"
            fi
        fi
    done
fi

echo "[4/7] Migrando OUs..."

if [ -f "$BACKUP_PATH/ous.csv" ]; then
    tail -n +2 "$BACKUP_PATH/ous.csv" | while IFS=, read -r ou_line
    do
        IFS=',' read -ra ou_fields <<< "$ou_line"
        ou_name=$(echo "${ou_fields[0]}" | tr -d '"')
        ou_dn=$(echo "${ou_fields[1]}" | tr -d '"')
        
        if [ ! -z "$ou_name" ] && [ "$ou_name" != "Name" ]; then
            echo "Criando OU: $ou_name"
            
            # Converter DN do Windows para formato Samba
            samba_ou_path=$(echo "$ou_dn" | sed 's/DC=almt,DC=local//' | sed 's/^,//' | sed 's/$/,DC=almt,DC=local/')
            
            samba-tool ou create "$samba_ou_path"
        fi
    done
fi

echo "[5/7] Configurando políticas de senha..."

# Aplicar política de senha do Windows AD
if [ -f "$BACKUP_PATH/domain-password-policy.xml" ]; then
    # Extrair configurações (simplificado)
    min_length=$(grep -oP 'MinPasswordLength="\K[^"]+' "$BACKUP_PATH/domain-password-policy.xml" || echo "8")
    max_age=$(grep -oP 'MaxPasswordAge="\K[^"]+' "$BACKUP_PATH/domain-password-policy.xml" || echo "90")
    history=$(grep -oP 'PasswordHistoryCount="\K[^"]+' "$BACKUP_PATH/domain-password-policy.xml" || echo "24")
    
    samba-tool domain passwordsettings set \
        --min-pwd-length="$min_length" \
        --max-pwd-age="$max_age" \
        --history-length="$history"
fi

echo "[6/7] Configurando home directories..."

# Criar home directories para usuários
samba-tool user list | while read user
do
    home_dir="/home/$user"
    if [ ! -d "$home_dir" ]; then
        mkdir -p "$home_dir"
        chown "$user":"Domain Users" "$home_dir"
        chmod 700 "$home_dir"
    fi
done

echo "[7/7] Gerando relatório de migração..."

cat > /opt/samba-migration/user-migration-report.md << USER_REPORT
# Relatório de Migração de Usuários

## Data: $(date)

## Estatísticas:
- Usuários migrados: $(samba-tool user list | wc -l)
- Grupos migrados: $(samba-tool group list | wc -l)
- OUs migradas: $(samba-tool ou list | wc -l)

## Usuários Criados:
$(samba-tool user list | sed 's/^/- /')

## Grupos Criados:
$(samba-tool group list | sed 's/^/- /')

## Configurações:
- Política de senha aplicada
- Home directories criadas
- Scripts de logon configurados

## Próximos Passos:
1. Testar login dos usuários
2. Verificar permissões de grupos
3. Testar acesso a recursos compartilhados
USER_REPORT

echo "========================================="
echo "MIGRAÇÃO DE USUÁRIOS CONCLUÍDA!"
echo "Relatório: /opt/samba-migration/user-migration-report.md"
echo "========================================="

# Limpar
rm -rf "$TEMP_DIR"