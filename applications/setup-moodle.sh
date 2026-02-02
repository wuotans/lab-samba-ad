#!/bin/bash
# Moodle Installation with Samba AD LDAP Integration

set -e

echo "========================================="
echo "INSTALANDO MOODLE COM SAMBA AD LDAP"
echo "========================================="

# Configurações
DOMAIN="almt.local"
LDAP_HOST="dc-samba.almt.local"
LDAP_BASE="dc=almt,dc=local"
LDAP_USER="administrator"
LDAP_PASS="Passw0rd123!"
MOODLE_DB_NAME="moodle"
MOODLE_DB_USER="moodle"
MOODLE_DB_PASS="MoodleDB123!"
MOODLE_ADMIN="admin"
MOODLE_ADMIN_PASS="MoodleAdmin123!"
MOODLE_DATA_PATH="/var/moodledata"

echo "[1/10] Atualizando sistema..."
apt-get update
apt-get upgrade -y

echo "[2/10] Instalando dependências..."
apt-get install -y apache2 mariadb-server libapache2-mod-php8.1 \
    php8.1-{mysql,curl,gd,intl,ldap,mbstring,xml,zip,soap,opcache,json,pspell,bcmath,xmlrpc} \
    ghostscript graphviz aspell wget unzip git

echo "[3/10] Configurando MariaDB..."
mysql -e "CREATE DATABASE IF NOT EXISTS $MOODLE_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$MOODLE_DB_USER'@'localhost' IDENTIFIED BY '$MOODLE_DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $MOODLE_DB_NAME.* TO '$MOODLE_DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "[4/10] Baixando Moodle..."
cd /var/www/html
wget https://download.moodle.org/download.php/direct/stable401/moodle-latest-401.tgz
tar -xzf moodle-latest-401.tgz
chown -R www-data:www-data moodle
chmod -R 755 moodle

echo "[5/10] Criando diretório de dados..."
mkdir -p $MOODLE_DATA_PATH
chown -R www-data:www-data $MOODLE_DATA_PATH
chmod -R 777 $MOODLE_DATA_PATH

echo "[6/10] Configurando Apache..."
cat > /etc/apache2/sites-available/moodle.conf << APACHE_CONF
<VirtualHost *:80>
    ServerName moodle.$DOMAIN
    DocumentRoot /var/www/html/moodle
    
    <Directory /var/www/html/moodle>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/moodle_error.log
    CustomLog \${APACHE_LOG_DIR}/moodle_access.log combined
    
    # PHP settings
    php_value max_execution_time 300
    php_value max_input_time 300
    php_value memory_limit 256M
    php_value upload_max_filesize 50M
    php_value post_max_size 50M
</VirtualHost>
APACHE_CONF

a2ensite moodle.conf
a2enmod rewrite headers env dir mime
systemctl restart apache2

echo "[7/10] Criando arquivo de configuração Moodle..."
cat > /var/www/html/moodle/config.php << MOODLE_CONFIG
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'localhost';
\$CFG->dbname    = '$MOODLE_DB_NAME';
\$CFG->dbuser    = '$MOODLE_DB_USER';
\$CFG->dbpass    = '$MOODLE_DB_PASS';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => '',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

\$CFG->wwwroot   = 'http://moodle.$DOMAIN';
\$CFG->dataroot  = '$MOODLE_DATA_PATH';
\$CFG->admin     = '$MOODLE_ADMIN';

\$CFG->directorypermissions = 0777;

// Performance
\$CFG->cachejs = 1;
\$CFG->themedesignermode = 0;

// LDAP Configuration
\$CFG->auth = 'ldap';
\$CFG->auth_instructions = 'Faça login com suas credenciais do domínio ALMT';

require_once(__DIR__ . '/lib/setup.php');
MOODLE_CONFIG

echo "[8/10] Configurando autenticação LDAP..."
# Criar script para configurar LDAP via CLI
cat > /tmp/configure_moodle_ldap.php << 'PHP_SCRIPT'
<?php
define('CLI_SCRIPT', true);
require(__DIR__ . '/config.php');

// Configurar autenticação LDAP
set_config('auth', 'ldap');

// Configurar servidor LDAP
set_config('host_url', '$LDAP_HOST', 'auth_ldap');
set_config('ldap_version', 3, 'auth_ldap');
set_config('ldapencoding', 'utf-8', 'auth_ldap');
set_config('bind_dn', 'cn=$LDAP_USER,cn=Users,$LDAP_BASE', 'auth_ldap');
set_config('bind_pw', '$LDAP_PASS', 'auth_ldap');
set_config('user_type', 'ad', 'auth_ldap');
set_config('contexts', '$LDAP_BASE', 'auth_ldap');
set_config('opt_deref', 0, 'auth_ldap');
set_config('user_attribute', 'sAMAccountName', 'auth_ldap');
set_config('memberattribute', 'memberof', 'auth_ldap');
set_config('memberattribute_isdn', 1, 'auth_ldap');
set_config('objectclass', 'user', 'auth_ldap');
set_config('create_context', '$LDAP_BASE', 'auth_ldap');
set_config('field_map_email', 'mail', 'auth_ldap');
set_config('field_map_firstname', 'givenName', 'auth_ldap');
set_config('field_map_lastname', 'sn', 'auth_ldap');
set_config('field_map_idnumber', 'employeeID', 'auth_ldap');
set_config('field_map_phone1', 'telephoneNumber', 'auth_ldap');
set_config('field_map_department', 'department', 'auth_ldap');
set_config('removeuser', 2, 'auth_ldap'); // AUTH_REMOVEUSER_KEEP

echo "LDAP configuration completed\n";

// Criar usuário admin
require_once(\$CFG->libdir . '/authlib.php');
require_once(\$CFG->dirroot . '/user/lib.php');

\$user = new stdClass();
\$user->username = '$MOODLE_ADMIN';
\$user->password = hash_internal_user_password('$MOODLE_ADMIN_PASS');
\$user->firstname = 'Moodle';
\$user->lastname = 'Administrator';
\$user->email = 'admin@$DOMAIN';
\$user->mnethostid = 1;
\$user->confirmed = 1;
\$user->auth = 'manual';

\$admin_id = user_create_user(\$user);

// Atribuir papel de administrador
\$context = context_system::instance();
\$roleid = 1; // Manager role
role_assign(\$roleid, \$admin_id, \$context->id);

echo "Admin user created: $MOODLE_ADMIN\n";
?>
PHP_SCRIPT

# Substituir variáveis
sed -i "s/\$LDAP_HOST/$LDAP_HOST/g" /tmp/configure_moodle_ldap.php
sed -i "s/\$LDAP_BASE/$LDAP_BASE/g" /tmp/configure_moodle_ldap.php
sed -i "s/\$LDAP_USER/$LDAP_USER/g" /tmp/configure_moodle_ldap.php
sed -i "s/\$LDAP_PASS/$LDAP_PASS/g" /tmp/configure_moodle_ldap.php
sed -i "s/\$MOODLE_ADMIN/$MOODLE_ADMIN/g" /tmp/configure_moodle_ldap.php
sed -i "s/\$MOODLE_ADMIN_PASS/$MOODLE_ADMIN_PASS/g" /tmp/configure_moodle_ldap.php
sed -i "s/\$DOMAIN/$DOMAIN/g" /tmp/configure_moodle_ldap.php

cd /var/www/html/moodle
php /tmp/configure_moodle_ldap.php

echo "[9/10] Configurando sincronização de usuários..."
# Criar script de sincronização
cat > /usr/local/bin/moodle-ldap-sync.sh << SYNC_SCRIPT
#!/bin/bash
cd /var/www/html/moodle
php auth/ldap/cli/sync_users.php
echo "\$(date): LDAP sync completed" >> /var/log/moodle-ldap-sync.log
SYNC_SCRIPT

chmod +x /usr/local/bin/moodle-ldap-sync.sh

# Agendar sincronização
echo "*/15 * * * * www-data /usr/local/bin/moodle-ldap-sync.sh" >> /etc/crontab

echo "[10/10] Criando curso de exemplo..."
# Criar curso via CLI
cat > /tmp/create_moodle_course.php << 'COURSE_SCRIPT'
<?php
define('CLI_SCRIPT', true);
require(__DIR__ . '/config.php');

// Criar categoria
\$category = new stdClass();
\$category->name = 'Treinamentos ALMT';
\$category->idnumber = 'ALMT-TRAIN';
\$category->description = 'Cursos de treinamento para funcionários ALMT';
\$category->parent = 0;
\$category->visible = 1;

\$cat_id = \$DB->insert_record('course_categories', \$category);

// Criar curso
\$course = new stdClass();
\$course->fullname = 'Treinamento Inicial';
\$course->shortname = 'ALMT-INICIAL';
\$course->idnumber = 'TREIN001';
\$course->summary = 'Curso de treinamento inicial para novos funcionários da ALMT';
\$course->format = 'topics';
\$course->category = \$cat_id;
\$course->visible = 1;
\$course->startdate = time();
\$course->enddate = time() + (90 * 24 * 3600);

\$course_id = \$DB->insert_record('course', \$course);

echo "Course created with ID: \$course_id\n";

// Sincronizar usuários do AD
require_once(\$CFG->dirroot . '/auth/ldap/auth.php');
\$auth = get_auth_plugin('ldap');
\$auth->sync_users(true);

echo "LDAP users synchronized\n";
?>
COURSE_SCRIPT

php /tmp/create_moodle_course.php

echo "========================================="
echo "MOODLE INSTALADO COM SUCESSO!"
echo "========================================="
echo "URL: http://moodle.almt.local"
echo "Admin: $MOODLE_ADMIN / $MOODLE_ADMIN_PASS"
echo "LDAP: Samba AD integrado"
echo "Sincronização: a cada 15 minutos"
echo "Curso: Treinamento Inicial criado"
echo "========================================="

# Criar script de teste
cat > /usr/local/bin/test-moodle-ldap.sh << TEST_SCRIPT
#!/bin/bash
echo "Testando integração Moodle + Samba AD..."
echo "Usuários LDAP sincronizados:"
cd /var/www/html/moodle
php admin/cli/ldap_sync_users.php --help
echo ""
echo "Testando conexão LDAP:"
ldapsearch -x -H ldap://$LDAP_HOST -b "$LDAP_BASE" -D "cn=$LDAP_USER,cn=Users,$LDAP_BASE" -w "$LDAP_PASS" "(objectClass=user)" | head -5
TEST_SCRIPT

chmod +x /usr/local/bin/test-moodle-ldap.sh