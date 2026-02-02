#!/bin/bash
# SAMBA AD DOMAIN CONTROLLER SETUP
# Deve ser executado APÓS o AD Windows estar configurado

set -e

echo "========================================="
echo "CONFIGURANDO SAMBA ACTIVE DIRECTORY"
echo "========================================="

# Configurações
DOMAIN="almt.local"
DOMAIN_UPPER="ALMT.LOCAL"
DOMAIN_NETBIOS="ALMT"
ADMIN_PASSWORD="Passw0rd123!"
DNS_FORWARDER="192.168.100.10"  # Usa DC Windows como forwarder inicial
HOSTNAME="dc-samba"
IP_ADDRESS="192.168.100.100"

echo "[1/12] Atualizando sistema..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q

echo "[2/12] Configurando hostname..."
hostnamectl set-hostname $HOSTNAME.$DOMAIN
echo "$IP_ADDRESS $HOSTNAME.$DOMAIN $HOSTNAME" >> /etc/hosts

echo "[3/12] Instalando pacotes necessários..."
apt-get install -y samba smbclient winbind krb5-user krb5-config \
    bind9 bind9utils bind9-doc dnsutils ntp ntpdate \
    acl attr python3-dnspython ldb-tools samba-vfs-modules \
    samba-dsdb-modules samba-dc

echo "[4/12] Configurando NTP..."
cat > /etc/ntp.conf << NTP_CONF
server 0.br.pool.ntp.org
server 1.br.pool.ntp.org
server 2.br.pool.ntp.org
server 3.br.pool.ntp.org

# Sincronizar com DC Windows
server dc-windows.almt.local iburst

restrict 127.0.0.1
restrict ::1
restrict $IP_ADDRESS mask 255.255.255.0 nomodify notrap
NTP_CONF

systemctl restart ntp
systemctl enable ntp

echo "[5/12] Configurando Kerberos..."
cat > /etc/krb5.conf << KRB5_CONF
[libdefaults]
    default_realm = $DOMAIN_UPPER
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    $DOMAIN_UPPER = {
        kdc = $HOSTNAME.$DOMAIN
        admin_server = $HOSTNAME.$DOMAIN
        default_domain = $DOMAIN
    }

[domain_realm]
    .$DOMAIN = $DOMAIN_UPPER
    $DOMAIN = $DOMAIN_UPPER
KRB5_CONF

echo "[6/12] Parando serviços existentes..."
systemctl stop samba-ad-dc 2>/dev/null || true
systemctl disable samba-ad-dc 2>/dev/null || true

echo "[7/12] Removendo configurações antigas..."
rm -rf /var/lib/samba/private/*
rm -rf /var/lib/samba/sysvol/*

echo "[8/12] Provisionando novo domínio Samba AD..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm=$DOMAIN_UPPER \
    --domain=$DOMAIN_NETBIOS \
    --server-role=dc \
    --dns-backend=BIND9_DLZ \
    --adminpass="$ADMIN_PASSWORD" \
    --host-name=$HOSTNAME \
    --host-ip=$IP_ADDRESS \
    --option="bind interfaces only = yes" \
    --option="interfaces = lo $IP_ADDRESS" \
    --option="dns forwarder = $DNS_FORWARDER" \
    --option="allow dns updates = secure" \
    --option="winbind enum users = yes" \
    --option="winbind enum groups = yes" \
    --option="winbind use default domain = yes" \
    --option="template homedir = /home/%U" \
    --option="template shell = /bin/bash" \
    --option="idmap_ldb:use rfc2307 = yes"

echo "[9/12] Configurando Samba..."
cat > /etc/samba/smb.conf << SAMBA_CONF
[global]
    workgroup = $DOMAIN_NETBIOS
    realm = $DOMAIN_UPPER
    netbios name = $HOSTNAME
    server role = active directory domain controller
    dns forwarder = $DNS_FORWARDER
    
    # Security
    server signing = auto
    client signing = auto
    server schannel = auto
    client schannel = auto
    
    # Logging
    log level = 2
    log file = /var/log/samba/log.%m
    max log size = 5000
    
    # ID Mapping
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config $DOMAIN_NETBIOS : backend = ad
    idmap config $DOMAIN_NETBIOS : schema_mode = rfc2307
    idmap config $DOMAIN_NETBIOS : range = 10000-999999
    idmap config $DOMAIN_NETBIOS : unix_nss_info = yes
    
    # Winbind
    winbind enum users = yes
    winbind enum groups = yes
    winbind use default domain = yes
    winbind refresh tickets = yes
    winbind offline logon = false
    
    # Templates
    template homedir = /home/%U
    template shell = /bin/bash
    
    # Kerberos
    kerberos method = secrets and keytab
    
    # LDAP
    ldap server require strong auth = no
    
    # TLS (será configurado posteriormente)
    tls enabled = yes
    tls keyfile = /etc/ssl/private/samba.key
    tls certfile = /etc/ssl/certs/samba.crt
    tls cafile = /etc/ssl/certs/ca-certificates.crt

[sysvol]
    path = /var/lib/samba/sysvol
    read only = No
    vfs objects = dfs_samba4 acl_xattr

[netlogon]
    path = /var/lib/samba/sysvol/$DOMAIN/scripts
    read only = No
    browsable = No

[homes]
    comment = Home Directories
    browseable = No
    read only = No
    create mask = 0700
    directory mask = 0700
    valid users = %S

[profiles]
    path = /var/lib/samba/profiles
    read only = No
    profile acls = Yes
    browsable = No
SAMBA_CONF

echo "[10/12] Configurando BIND9 DNS..."
cat > /etc/bind/named.conf.options << BIND_OPTIONS
options {
    directory "/var/cache/bind";
    forwarders {
        $DNS_FORWARDER;
        8.8.8.8;
        8.8.4.4;
    };
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
    allow-query { any; };
    allow-transfer { none; };
    allow-recursion { any; };
};
BIND_OPTIONS

# Incluir configuração do Samba
echo 'include "/var/lib/samba/private/named.conf";' >> /etc/bind/named.conf.local

systemctl restart bind9
systemctl enable bind9

echo "[11/12] Iniciando serviços Samba..."
systemctl start samba-ad-dc
systemctl enable samba-ad-dc

echo "[12/12] Criando estrutura básica e testando..."

# Aguardar serviços iniciarem
sleep 10

# Criar OUs equivalentes ao Windows AD
samba-tool ou create "OU=Usuarios,DC=almt,DC=local"
samba-tool ou create "OU=Computadores,DC=almt,DC=local"
samba-tool ou create "OU=Servidores,DC=almt,DC=local"
samba-tool ou create "OU=Grupos,DC=almt,DC=local"

# Testar configuração
echo "Testando configuração..."
net ads testjoin
net ads info

# Configurar políticas de senha (equivalentes às do Windows)
samba-tool domain passwordsettings set \
    --complexity=on \
    --min-pwd-length=8 \
    --min-pwd-age=1 \
    --max-pwd-age=90 \
    --history-length=24 \
    --account-lockout-duration=30 \
    --account-lockout-threshold=5 \
    --reset-account-lockout-after=30

echo "========================================="
echo "SAMBA AD CONFIGURADO COM SUCESSO!"
echo "========================================="
echo "Domínio: $DOMAIN"
echo "Hostname: $HOSTNAME.$DOMAIN"
echo "IP: $IP_ADDRESS"
echo "Administrador: Administrator"
echo "Senha: $ADMIN_PASSWORD"
echo ""
echo "COMANDOS DE TESTE:"
echo "  kinit Administrator@$DOMAIN_UPPER"
echo "  smbclient -L localhost -U Administrator%$ADMIN_PASSWORD"
echo "  samba-tool user list"
echo "========================================="