#!/bin/bash
# Nextcloud Installation with Samba AD LDAP Integration

set -e

echo "========================================="
echo "INSTALANDO NEXTCLOUD COM SAMBA AD LDAP"
echo "========================================="

# Configurações
DOMAIN="almt.local"
LDAP_HOST="dc-samba.almt.local"
LDAP_BASE="dc=almt,dc=local"
LDAP_USER="administrator"
LDAP_PASS="Passw0rd123!"
NEXTCLOUD_ADMIN="admin"
NEXTCLOUD_PASS="Nextcloud123!"
DB_PASS="NextcloudDB123!"

echo "[1/10] Atualizando sistema..."
apt-get update
apt-get upgrade -y

echo "[2/10] Instalando dependências..."
apt-get install -y apache2 mariadb-server libapache2-mod-php8.1 \
    php8.1-{gd,mysql,curl,mbstring,intl,imagick,xml,zip,bz2,ldap} \
    wget unzip

echo "[3/10] Configurando MariaDB..."
mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "[4/10] Baixando Nextcloud..."
cd /var/www/html
wget https://download.nextcloud.com/server/releases/nextcloud-27.0.0.zip
unzip nextcloud-27.0.0.zip
chown -R www-data:www-data nextcloud
chmod -R 755 nextcloud

echo "[5/10] Configurando Apache..."
cat > /etc/apache2/sites-available/nextcloud.conf << APACHE_CONF
<VirtualHost *:80>
    ServerName nextcloud.$DOMAIN
    DocumentRoot /var/www/html/nextcloud
    
    <Directory /var/www/html/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
    
    # PHP settings
    php_value upload_max_filesize 20M
    php_value post_max_size 20M
    php_value memory_limit 256M
</VirtualHost>
APACHE_CONF

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime
systemctl restart apache2

echo "[6/10] Instalando Nextcloud via linha de comando..."
cd /var/www/html/nextcloud
sudo -u www-data php occ maintenance:install \
    --database "mysql" \
    --database-name "nextcloud" \
    --database-user "nextcloud" \
    --database-pass "$DB_PASS" \
    --admin-user "$NEXTCLOUD_ADMIN" \
    --admin-pass "$NEXTCLOUD_PASS"

echo "[7/10] Habilitando aplicativo LDAP..."
sudo -u www-data php occ app:enable user_ldap

echo "[8/10] Configurando conexão LDAP com Samba AD..."
# Configurar LDAP via occ
CONFIG_ID=$(sudo -u www-data php occ ldap:show-config | grep "| Configuration" | head -1 | awk '{print $1}')

if [ -n "$CONFIG_ID" ]; then
    sudo -u www-data php occ ldap:delete-config "$CONFIG_ID"
fi

sudo -u www-data php occ ldap:create-empty-config
CONFIG_ID="s01"

# Configurar servidor LDAP
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapHost "$LDAP_HOST"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapPort 389
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapBase "$LDAP_BASE"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapAgentName "cn=$LDAP_USER,cn=Users,$LDAP_BASE"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapAgentPassword "$LDAP_PASS"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapUserFilter "(objectClass=user)"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapLoginFilter "(&(objectClass=user)(|(sAMAccountName=%uid)(userPrincipalName=%uid)))"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapUserDisplayName displayName
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapUserEmail mail
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapConfigurationActive 1
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapExpertUsernameAttr sAMAccountName
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapExpertUUIDUserAttr objectGUID
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapGroupFilter "(objectClass=group)"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapGroupMemberAssocAttr member
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapBaseGroups "$LDAP_BASE"
sudo -u www-data php occ ldap:set-config "$CONFIG_ID" ldapBaseUsers "$LDAP_BASE"

echo "[9/10] Testando conexão LDAP..."
sudo -u www-data php occ ldap:test-config "$CONFIG_ID"

echo "[10/10] Sincronizando usuários..."
sudo -u www-data php occ ldap:update-user

cat > /etc/cron.d/nextcloud-ldap-sync << CRON_SYNC
*/15 * * * * www-data php -f /var/www/html/nextcloud/occ ldap:update-user
CRON_SYNC

echo "========================================="
echo "NEXTCLOUD INSTALADO COM SUCESSO!"
echo "========================================="
echo "URL: http://nextcloud.almt.local"
echo "Admin: $NEXTCLOUD_ADMIN / $NEXTCLOUD_PASS"
echo "LDAP Users: administrator, joao.silva, maria.souza"
echo "Sincronização automática: a cada 15 minutos"
echo "========================================="

# Criar script de teste
cat > /usr/local/bin/test-nextcloud-ldap.sh << TEST_SCRIPT
#!/bin/bash
echo "Testando integração Nextcloud + Samba AD..."
echo "Usuários LDAP sincronizados:"
sudo -u www-data php /var/www/html/nextcloud/occ user:list | grep -i almt
echo ""
echo "Status LDAP:"
sudo -u www-data php /var/www/html/nextcloud/occ ldap:show-config
TEST_SCRIPT

chmod +x /usr/local/bin/test-nextcloud-ldap.sh