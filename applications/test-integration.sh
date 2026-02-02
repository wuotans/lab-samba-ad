#!/bin/bash
# Testar integração de todas as aplicações com Samba AD

set -e

echo "========================================="
echo "TESTANDO INTEGRAÇÃO APLICAÇÕES + SAMBA AD"
echo "========================================="

DOMAIN="almt.local"
LDAP_HOST="dc-samba.almt.local"
TEST_USER="joao.silva"
TEST_PASS="Senha123!"

echo "[1/5] Testando autenticação básica..."
echo "Testando Kerberos..."
kinit $TEST_USER@${DOMAIN^^} <<< "$TEST_PASS" && {
    echo "✓ Kerberos OK"
    klist
    kdestroy
} || {
    echo "✗ Falha Kerberos"
}

echo "Testando LDAP..."
ldapsearch -x -H ldap://$LDAP_HOST -b "dc=almt,dc=local" -D "$TEST_USER@$DOMAIN" -w "$TEST_PASS" "(objectClass=user)" | grep -q "dn:" && {
    echo "✓ LDAP OK"
} || {
    echo "✗ Falha LDAP"
}

echo "[2/5] Testando Nextcloud..."
if [ -d "/var/www/html/nextcloud" ]; then
    echo "Testando usuários LDAP no Nextcloud..."
    sudo -u www-data php /var/www/html/nextcloud/occ user:list | grep -i "$TEST_USER" && {
        echo "✓ Nextcloud LDAP OK"
    } || {
        echo "✗ Nextcloud LDAP falhou"
    }
else
    echo "Nextcloud não instalado"
fi

echo "[3/5] Testando GLPI..."
if [ -d "/var/www/html/glpi" ]; then
    echo "Testando sincronização GLPI..."
    php /var/www/html/glpi/bin/console glpi:ldap:synchronize-users --only-update --no-interaction && {
        echo "✓ GLPI LDAP OK"
    } || {
        echo "✗ GLPI LDAP falhou"
    }
else
    echo "GLPI não instalado"
fi

echo "[4/5] Testando Moodle..."
if [ -d "/var/www/html/moodle" ]; then
    echo "Testando sincronização Moodle..."
    cd /var/www/html/moodle
    php auth/ldap/cli/sync_users.php --help >/dev/null && {
        echo "✓ Moodle LDAP OK"
    } || {
        echo "✗ Moodle LDAP falhou"
    }
else
    echo "Moodle não instalado"
fi

echo "[5/5] Testando SMB/CIFS..."
echo "Testando acesso a compartilhamentos..."
smbclient -L $LDAP_HOST -U $TEST_USER%$TEST_PASS >/dev/null 2>&1 && {
    echo "✓ SMB OK"
} || {
    echo "✗ SMB falhou"
}

echo "========================================="
echo "TESTES CONCLUÍDOS!"
echo "========================================="

# Gerar relatório
cat > /var/log/app-integration-test.txt << TEST_REPORT
Data do teste: $(date)

Resultados:
1. Kerberos: $(kinit $TEST_USER@${DOMAIN^^} <<< "$TEST_PASS" 2>&1 | grep -q "Ticket" && echo "OK" || echo "FALHA")
2. LDAP: $(ldapsearch -x -H ldap://$LDAP_HOST -b "dc=almt,dc=local" -D "$TEST_USER@$DOMAIN" -w "$TEST_PASS" "(objectClass=user)" 2>&1 | grep -q "dn:" && echo "OK" || echo "FALHA")
3. Nextcloud: $([ -d "/var/www/html/nextcloud" ] && sudo -u www-data php /var/www/html/nextcloud/occ user:list 2>&1 | grep -qi "$TEST_USER" && echo "OK" || echo "NÃO INSTALADO/FALHA")
4. GLPI: $([ -d "/var/www/html/glpi" ] && php /var/www/html/glpi/bin/console glpi:user:list 2>&1 | grep -qi "$TEST_USER" && echo "OK" || echo "NÃO INSTALADO/FALHA")
5. Moodle: $([ -d "/var/www/html/moodle" ] && echo "INSTALADO" || echo "NÃO INSTALADO")
6. SMB: $(smbclient -L $LDAP_HOST -U $TEST_USER%$TEST_PASS 2>&1 | grep -q "Sharename" && echo "OK" || echo "FALHA")

Recomendações:
- Verificar logs em caso de falhas
- Validar sincronização periódica
- Testar login em todas as aplicações
TEST_REPORT

echo "Relatório completo em: /var/log/app-integration-test.txt"