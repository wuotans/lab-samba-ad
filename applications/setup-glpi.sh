#!/bin/bash
# GLPI Installation with Samba AD LDAP Integration

set -e

echo "========================================="
echo "INSTALANDO GLPI COM SAMBA AD LDAP"
echo "========================================="

# Configurações
DOMAIN="almt.local"
LDAP_HOST="dc-samba.almt.local"
LDAP_BASE="dc=almt,dc=local"
LDAP_USER="administrator"
LDAP_PASS="Passw0rd123!"
GLPI_DB_NAME="glpi"
GLPI_DB_USER="glpi"
GLPI_DB_PASS="GlpiDB123!"
GLPI_ADMIN="admin"
GLPI_ADMIN_PASS="GlpiAdmin123!"

echo "[1/10] Atualizando sistema..."
apt-get update
apt-get upgrade -y

echo "[2/10] Instalando dependências..."
apt-get install -y apache2 mariadb-server libapache2-mod-php8.1 \
    php8.1-{mysql,curl,gd,intl,ldap,mbstring,xml,zip,bz2,imap,apcu} \
    wget unzip

echo "[3/10] Configurando MariaDB..."
mysql -e "CREATE DATABASE IF NOT EXISTS $GLPI_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$GLPI_DB_USER'@'localhost' IDENTIFIED BY '$GLPI_DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $GLPI_DB_NAME.* TO '$GLPI_DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "[4/10] Baixando GLPI..."
cd /var/www/html
wget https://github.com/glpi-project/glpi/releases/download/10.0.0/glpi-10.0.0.tgz
tar -xzf glpi-10.0.0.tgz
chown -R www-data:www-data glpi
chmod -R 755 glpi

echo "[5/10] Configurando Apache..."
cat > /etc/apache2/sites-available/glpi.conf << APACHE_CONF
<VirtualHost *:80>
    ServerName glpi.$DOMAIN
    DocumentRoot /var/www/html/glpi
    
    <Directory /var/www/html/glpi>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
    
    # PHP settings
    php_value upload_max_filesize 20M
    php_value post_max_size 20M
    php_value max_execution_time 300
    php_value memory_limit 256M
</VirtualHost>
APACHE_CONF

a2ensite glpi.conf
a2enmod rewrite headers env dir mime
systemctl restart apache2

echo "[6/10] Criando configuração do banco de dados..."
cat > /var/www/html/glpi/config/config_db.php << DB_CONFIG
<?php
class DB extends DBmysql {
   public \$dbhost     = 'localhost';
   public \$dbuser     = '$GLPI_DB_USER';
   public \$dbpassword = '$GLPI_DB_PASS';
   public \$dbdefault  = '$GLPI_DB_NAME';
}
DB_CONFIG

echo "[7/10] Instalando GLPI via linha de comando..."
cd /var/www/html/glpi
php bin/console glpi:database:install \
    --db-host=localhost \
    --db-name=$GLPI_DB_NAME \
    --db-user=$GLPI_DB_USER \
    --db-password=$GLPI_DB_PASS \
    --no-interaction

echo "[8/10] Configurando autenticação LDAP..."
# Criar script PHP para configurar LDAP
cat > /tmp/configure_glpi_ldap.php << 'PHP_SCRIPT'
<?php
define('GLPI_ROOT', '/var/www/html/glpi');
include (GLPI_ROOT . "/inc/includes.php");

// Configurar servidor LDAP
$ldap = new AuthLDAP();
$inputs = [
    'name' => 'Samba AD',
    'host' => '$LDAP_HOST',
    'basedn' => '$LDAP_BASE',
    'rootdn' => 'cn=$LDAP_USER,cn=Users,$LDAP_BASE',
    'rootdn_passwd' => '$LDAP_PASS',
    'port' => 389,
    'login_field' => 'sAMAccountName',
    'sync_field' => 'objectGUID',
    'is_active' => 1,
    'is_default' => 1,
    'inventory_domain' => '$DOMAIN'
];

$ldap_id = $ldap->add($inputs);

if ($ldap_id) {
    echo "LDAP server configured with ID: $ldap_id\n";
    
    // Configurar mapeamento de campos
    $fieldmap = [
        'name' => 'cn',
        'realname' => 'sn',
        'firstname' => 'givenName',
        'phone' => 'telephoneNumber',
        'phone2' => 'mobile',
        'mobile' => 'mobile',
        'email' => 'mail',
        'registration_number' => 'employeeID'
    ];
    
    foreach ($fieldmap as $glpi_field => $ldap_field) {
        $field = new AuthLdapFieldMapping();
        $field->add([
            'authldaps_id' => $ldap_id,
            'field' => $glpi_field,
            'attribute' => $ldap_field,
            'is_active' => 1
        ]);
    }
    
    echo "Field mapping configured\n";
    
    // Sincronizar usuários
    $ldap->forceOneSync($ldap_id);
    echo "Users synchronized\n";
} else {
    echo "Failed to configure LDAP\n";
}
?>
PHP_SCRIPT

# Substituir variáveis
sed -i "s/\$LDAP_HOST/$LDAP_HOST/g" /tmp/configure_glpi_ldap.php
sed -i "s/\$LDAP_BASE/$LDAP_BASE/g" /tmp/configure_glpi_ldap.php
sed -i "s/\$LDAP_USER/$LDAP_USER/g" /tmp/configure_glpi_ldap.php
sed -i "s/\$LDAP_PASS/$LDAP_PASS/g" /tmp/configure_glpi_ldap.php
sed -i "s/\$DOMAIN/$DOMAIN/g" /tmp/configure_glpi_ldap.php

php /tmp/configure_glpi_ldap.php

echo "[9/10] Configurando agente GLPI..."
wget https://github.com/glpi-project/glpi-agent/releases/download/1.5/glpi-agent-1.5-linux-installer.pl
perl glpi-agent-1.5-linux-installer.pl --install --no-httpd --server http://glpi.$DOMAIN --run-now

echo "[10/10] Criando usuário administrador..."
# Criar usuário admin via console
php bin/console glpi:user:add \
    --name="$GLPI_ADMIN" \
    --password="$GLPI_ADMIN_PASS" \
    --password-confirm="$GLPI_ADMIN_PASS" \
    --email="admin@$DOMAIN" \
    --firstname="GLPI" \
    --realname="Administrator" \
    --profile="Super-Admin" \
    --no-interaction

echo "========================================="
echo "GLPI INSTALADO COM SUCESSO!"
echo "========================================="
echo "URL: http://glpi.almt.local"
echo "Admin: $GLPI_ADMIN / $GLPI_ADMIN_PASS"
echo "LDAP: Samba AD integrado"
echo "Agente GLPI: Instalado e configurado"
echo "========================================="

# Criar script de teste
cat > /usr/local/bin/test-glpi-ldap.sh << TEST_SCRIPT
#!/bin/bash
echo "Testando integração GLPI + Samba AD..."
echo "Usuários LDAP sincronizados:"
php /var/www/html/glpi/bin/console glpi:user:list | grep -i almt
echo ""
echo "Testando login LDAP:"
php /var/www/html/glpi/bin/console glpi:ldap:synchronize-users --only-update
TEST_SCRIPT

chmod +x /usr/local/bin/test-glpi-ldap.sh