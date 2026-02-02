#!/bin/bash
# Importar/Converter GPOs do Windows para Samba AD

set -e

echo "========================================="
echo "IMPORTANDO/CONVERTENDO GPOS PARA SAMBA AD"
echo "========================================="

BACKUP_PATH="/vagrant/migration/reports"
DOMAIN="almt.local"
DOMAIN_DN="dc=almt,dc=local"

echo "[1/6] Analisando GPOs exportadas..."

if [ ! -d "$BACKUP_PATH" ]; then
    echo "ERRO: Pasta de backup não encontrada: $BACKUP_PATH"
    exit 1
fi

# Ler análise CSV
CSV_FILE="$BACKUP_PATH/gpo-analysis.csv"
if [ ! -f "$CSV_FILE" ]; then
    echo "Arquivo de análise não encontrado: $CSV_FILE"
    exit 1
fi

echo "[2/6] Processando GPOs por compatibilidade..."

# Criar diretórios para scripts convertidos
mkdir -p /opt/samba-migration/scripts
mkdir -p /opt/samba-migration/gpos

# Processar cada GPO
while IFS=, read -r Name GUID Created Modified Compatibility MigrationMethod
do
    # Remover cabeçalho e aspas
    if [[ "$Name" == "Name" ]]; then
        continue
    fi
    
    Name=$(echo $Name | tr -d '"')
    Compatibility=$(echo $Compatibility | tr -d '"')
    MigrationMethod=$(echo $MigrationMethod | tr -d '"')
    
    echo "Processando: $Name"
    echo "  Compatibilidade: $Compatibility"
    echo "  Método: $MigrationMethod"
    
    case $Compatibility in
        "High")
            # Políticas nativas do Samba
            ProcessNativePolicy "$Name"
            ;;
        "Partial"|"Script")
            # Converter para scripts
            ConvertToScript "$Name"
            ;;
        "None")
            # Registrar como não migrável
            echo "  [SKIP] Não migrável" >> /opt/samba-migration/non-migratable.txt
            ;;
    esac
done < <(tail -n +2 "$CSV_FILE")

ProcessNativePolicy() {
    local gpo_name=$1
    
    case $gpo_name in
        "HORA_ALMT"|"ntp_servers")
            echo "Configurando NTP no Samba..."
            cat >> /etc/samba/smb.conf << NTP_CONFIG

# $gpo_name - Time Synchronization
ntp signd socket directory = /var/lib/samba/ntp_signd
time server = yes
NTP_CONFIG
            ;;
        "DNS Query Timeout")
            echo "Configurando timeout DNS..."
            # Configurar via DNS do Samba
            ;;
        "Auditing Policy")
            echo "Configurando auditoria..."
            ConfigureSambaAudit
            ;;
    esac
}

ConvertToScript() {
    local gpo_name=$1
    local script_file="/opt/samba-migration/scripts/$(echo $gpo_name | tr ' ' '_' | tr 'A-Z' 'a-z').sh"
    
    # Gerar script baseado no tipo de GPO
    case $gpo_name in
        *"SCRIPT"*|*"Mapeamento"*)
            CreateLogonScript "$gpo_name" "$script_file"
            ;;
        *"Install"*)
            CreateInstallScript "$gpo_name" "$script_file"
            ;;
        *"Impressora"*)
            CreatePrinterScript "$gpo_name" "$script_file"
            ;;
        *)
            CreateGenericScript "$gpo_name" "$script_file"
            ;;
    esac
    
    chmod +x "$script_file"
}

ConfigureSambaAudit() {
    echo "[3/6] Configurando auditoria do Samba..."
    
    # Configurar logs detalhados
    cat >> /etc/samba/smb.conf << AUDIT_CONFIG

# Audit Configuration
log level = 3
debug level = 3
log file = /var/log/samba/audit.%m
max log size = 10000
AUDIT_CONFIG

    # Configurar auditd para Samba
    cat > /etc/audit/rules.d/samba.rules << AUDIT_RULES
-w /var/lib/samba/ -p wa -k samba_audit
-w /etc/samba/ -p wa -k samba_config
-w /var/log/samba/ -p wa -k samba_logs
AUDIT_RULES

    systemctl restart auditd
}

CreateLogonScript() {
    local gpo_name=$1
    local script_file=$2
    
    cat > "$script_file" << 'SCRIPT'
#!/bin/bash
# Script de logon para Samba AD
# Substitui GPO: $gpo_name

USERNAME=$1
DOMAIN="almt.local"

echo "========================================"
echo "Bem-vindo, $USERNAME!"
echo "Data: $(date)"
echo "Computador: $(hostname)"
echo "========================================"

# Mapear unidades (equivalente ao scriptunificado.vbs)
mount_samba_share() {
    share_name=$1
    mount_point=$2
    
    if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
    fi
    
    # Tentar montar com credenciais do usuário
    mount -t cifs //dc-samba.almt.local/$share_name "$mount_point" \
        -o username=$USERNAME,domain=$DOMAIN,uid=$(id -u),gid=$(id -g) 2>/dev/null || true
}

# Mapear unidades padrão
mount_samba_share "netlogon" "/mnt/netlogon"
mount_samba_share "users/$USERNAME" "/home/$USERNAME/shared"
mount_samba_share "public" "/mnt/public"

# Configurações do usuário
echo "Último login: $(date)" > "/home/$USERNAME/.last_login"
SCRIPT
}

echo "[4/6] Configurando políticas de senha equivalentes..."

# Configurar políticas equivalentes às do Windows
samba-tool domain passwordsettings set \
    --complexity=on \
    --min-pwd-length=8 \
    --min-pwd-age=1 \
    --max-pwd-age=90 \
    --history-length=24 \
    --account-lockout-duration=30 \
    --account-lockout-threshold=5 \
    --reset-account-lockout-after=30

echo "[5/6] Configurando scripts de logon no Samba..."

# Copiar scripts para sysvol
SAMBA_SYSVOL="/var/lib/samba/sysvol/$DOMAIN/scripts"
mkdir -p "$SAMBA_SYSVOL"
cp /opt/samba-migration/scripts/*.sh "$SAMBA_SYSVOL/"
chmod +x "$SAMBA_SYSVOL"/*.sh

# Configurar script de logon padrão
cat > "$SAMBA_SYSVOL/logon.sh" << DEFAULT_LOGON
#!/bin/bash
# Script de logon padrão Samba AD

# Executar scripts migrados
for script in $SAMBA_SYSVOL/*.sh; do
    if [ -x "$script" ] && [ "$script" != "$SAMBA_SYSVOL/logon.sh" ]; then
        "$script" "$1"
    fi
done
DEFAULT_LOGON

chmod +x "$SAMBA_SYSVOL/logon.sh"

echo "[6/6] Gerando relatório de migração..."

cat > /opt/samba-migration/migration-report.md << REPORT
# Relatório de Migração GPO → Samba AD

## Data: $(date)

## GPOs Migradas:
$(ls /opt/samba-migration/scripts/*.sh 2>/dev/null | wc -l) scripts gerados

## GPOs Não Migráveis:
$(cat /opt/samba-migration/non-migratable.txt 2>/dev/null | wc -l) políticas não compatíveis

## Configurações Aplicadas:
- Política de senha: Complexidade ativada, mínimo 8 caracteres
- Bloqueio de conta: 5 tentativas, 30 minutos
- Scripts de logon: $(ls /opt/samba-migration/scripts/*.sh 2>/dev/null | xargs basename -a | tr '\n' ', ')

## Próximos Passos:
1. Testar scripts de logon
2. Validar políticas de segurança
3. Testar integração com aplicações
REPORT

echo "========================================="
echo "IMPORTAÇÃO CONCLUÍDA!"
echo "Scripts em: /opt/samba-migration/scripts/"
echo "Relatório: /opt/samba-migration/migration-report.md"
echo "========================================="