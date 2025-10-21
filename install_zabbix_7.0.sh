#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# Script de instalação do Zabbix 7.0 LTS no Debian 13 (Trixie)
# =============================================================
# Objetivo:
#   Automatizar a instalação e configuração do Zabbix Server, Frontend,
#   Agent, PostgreSQL (banco) e Nginx (web) na MESMA máquina.
#   O script cria o usuário e o banco do Zabbix no PostgreSQL,
#   importa o schema inicial e aplica as configurações mínimas
#   necessárias no zabbix_server.conf, no agent e no Nginx.
# Referência oficial:
#   https://www.zabbix.com/br/download?zabbix=7.0&os_distribution=debian&os_version=13&components=server_frontend_agent&db=pgsql&ws=nginx
# Uso sugerido:
#   - Execute como root.
#   - Opcionalmente exporte a variável ZBX_DB_PASS para evitar prompt interativo da senha
#       export ZBX_DB_PASS='sua-senha-segura'
#       ./install_zabbix_7.0.sh
# Notas:
#   - Configura Nginx para escutar na porta 8080 (padrão deste script).
#   - Frontend ficará acessível em: http://localhost:8080/
#   - Login padrão do frontend: Admin / zabbix (altere após o primeiro acesso).
#   - Mantém otimizações adicionais caso um zabbix_server.conf local com parâmetros
#     específicos seja encontrado no diretório atual (comportamento herdado do script base).

# =============================
# Corpo do instalador (script)
# =============================

# Zabbix 7.0 LTS + PostgreSQL + Nginx (Debian 13)
# Este bloco abaixo é baseado no script previamente validado no ambiente atual
# (install_zabbix_debian13.sh), preservando a lógica e correções aplicadas.

# Requisitos:
# - Rodar como root
# - Debian 13 (Trixie)
# - Rede com acesso a repo.zabbix.com e mirrors Debian
# - Opcional: exporte ZBX_DB_PASS para automatizar a criação do usuário de banco

########################################
# Funções utilitárias
########################################
log() { echo -e "[ZBX] $*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Este script precisa ser executado como root." >&2
    exit 1
  fi
}

########################################
# Variáveis
########################################
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PASS="${ZBX_DB_PASS:-}"
NGINX_LISTEN_PORT="8080"
SERVER_NAME="localhost"

########################################
# Início
########################################
require_root

log "Instalando repositório oficial do Zabbix"
wget -q https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian13_all.deb -O /tmp/zabbix-release_latest_7.0+debian13_all.deb
dpkg -i /tmp/zabbix-release_latest_7.0+debian13_all.deb
apt update -y

log "Instalando Zabbix Server, Frontend, Agent, PostgreSQL, Nginx e dependências"
apt install -y \
  zabbix-server-pgsql \
  zabbix-frontend-php \
  php8.4-pgsql \
  zabbix-nginx-conf \
  zabbix-sql-scripts \
  zabbix-agent \
  postgresql \
  nginx \
  php8.4-fpm

log "Habilitando e iniciando PostgreSQL"
systemctl enable --now postgresql

########################################
# Banco de Dados: criação de role, DB e import de schema
########################################
if [ -z "${DB_PASS}" ]; then
  # Solicita senha de banco interativa para automatizar DBPassword posteriormente
  read -r -s -p "Defina a senha do banco para o usuário '${DB_USER}': " DB_PASS
  echo
fi

log "Criando usuário e banco de dados no PostgreSQL"
# Cria/atualiza role do Zabbix
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN CREATE ROLE ${DB_USER} WITH LOGIN ENCRYPTED PASSWORD '${DB_PASS}'; ELSE ALTER ROLE ${DB_USER} WITH LOGIN ENCRYPTED PASSWORD '${DB_PASS}'; END IF; END $$;"
# Cria DB se não existir (CREATE DATABASE não pode rodar dentro de DO/transaction)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O ${DB_USER} ${DB_NAME}
fi

log "Importando schema inicial do Zabbix (pode demorar)"
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u ${DB_USER} psql ${DB_NAME}

########################################
# Configuração do Zabbix Server
########################################
ZBX_SERVER_CONF="/etc/zabbix/zabbix_server.conf"

log "Aplicando configurações de banco no zabbix_server.conf"
sed -i -E "s|^#?\s*DBHost=.*$|DBHost=localhost|" "${ZBX_SERVER_CONF}"
sed -i -E "s|^#?\s*DBName=.*$|DBName=${DB_NAME}|" "${ZBX_SERVER_CONF}"
sed -i -E "s|^#?\s*DBUser=.*$|DBUser=${DB_USER}|" "${ZBX_SERVER_CONF}"
sed -i -E "s|^#?\s*DBPassword=.*$|DBPassword=${DB_PASS}|" "${ZBX_SERVER_CONF}"

# Aplicar otimizações detectadas no diretório atual (se houver zabbix_server.conf)
log "Verificando otimizações de zabbix_server.conf existentes no diretório atual"
LOCAL_SERVER_CONFS=$(find "$(pwd)" -type f -name "*zabbix_server*.conf" 2>/dev/null || true)
if [ -n "${LOCAL_SERVER_CONFS}" ]; then
  log "Encontrado(s):\n${LOCAL_SERVER_CONFS}"
  # Lista de parâmetros de otimização a preservar (ajuste conforme necessário)
  OPT_KEYS="CacheSize|ValueCacheSize|HistoryCacheSize|HistoryTextCacheSize|TrendCacheSize|Timeout|ConfigCacheReload|StartPollers|StartPollersUnreachable|StartTrappers|StartDBSyncers|StartDiscoverers|StartHTTPPollers|StartIPMIPollers|StartPingers|StartSNMPPollers|StartVMwareCollectors|StartPreprocessors"
  while IFS= read -r conf; do
    while IFS= read -r line; do
      key=$(echo "$line" | awk -F'=' '{print $1}' | xargs)
      val=$(echo "$line" | awk -F'=' '{print $2}' | xargs)
      if [[ -n "$key" && -n "$val" ]]; then
        # Atualiza somente se chave existir no conjunto de otimizações
        if echo "$key" | grep -Eq "^(${OPT_KEYS})$"; then
          log "Aplicando otimização: $key=$val"
          if grep -Eq "^#?\s*${key}=" "${ZBX_SERVER_CONF}"; then
            sed -i -E "s|^#?\s*${key}=.*$|${key}=${val}|" "${ZBX_SERVER_CONF}"
          else
            echo "${key}=${val}" >> "${ZBX_SERVER_CONF}"
          fi
        fi
      fi
    done < <(grep -E "^(${OPT_KEYS})=" "$conf" | sed 's/\r$//')
  done <<< "${LOCAL_SERVER_CONFS}"
else
  log "Nenhum zabbix_server.conf local encontrado; mantendo valores padrão além do DB"
fi

########################################
# Configuração do Zabbix Agent (aplicar otimizações detectadas)
########################################
ZBX_AGENT_CONF="/etc/zabbix/zabbix_agentd.conf"

log "Aplicando apontamentos do agent para localhost"
sed -i -E "s|^#?\s*Server=.*$|Server=127.0.0.1|" "${ZBX_AGENT_CONF}"
sed -i -E "s|^#?\s*ServerActive=.*$|ServerActive=127.0.0.1|" "${ZBX_AGENT_CONF}"
# Se houver arquivo local com otimização do agent, preserva algumas conhecidas
LOCAL_AGENT_CONFS=$(find "$(pwd)" -type f -name "*zabbix_agentd*.conf" 2>/dev/null || true)
if [ -n "${LOCAL_AGENT_CONFS}" ]; then
  log "Encontrado(s) conf de agent; aplicando otimizações úteis"
  # Ex.: LogFileSize
  AGENT_OPT_KEYS="LogFileSize|Timeout|BufferSend|BufferSize|MaxLinesPerSecond|ListenBacklog"
  while IFS= read -r conf; do
    while IFS= read -r line; do
      key=$(echo "$line" | awk -F'=' '{print $1}' | xargs)
      val=$(echo "$line" | awk -F'=' '{print $2}' | xargs)
      if [[ -n "$key" && -n "$val" ]]; then
        if echo "$key" | grep -Eq "^(${AGENT_OPT_KEYS})$"; then
          log "Agent otimização: $key=$val"
          if grep -Eq "^#?\s*${key}=" "${ZBX_AGENT_CONF}"; then
            sed -i -E "s|^#?\s*${key}=.*$|${key}=${val}|" "${ZBX_AGENT_CONF}"
          else
            echo "${key}=${val}" >> "${ZBX_AGENT_CONF}"
          fi
        fi
      fi
    done < <(grep -E "^(${AGENT_OPT_KEYS})=" "$conf" | sed 's/\r$//')
  done <<< "${LOCAL_AGENT_CONFS}"
fi

########################################
# Configuração do Nginx para o frontend Zabbix
########################################
ZBX_NGINX_CONF="/etc/zabbix/nginx.conf"

log "Configurando Nginx conforme documentação (listen e server_name)"
sed -i -E "s|^#\s*listen\s+.*;|listen          ${NGINX_LISTEN_PORT};|" "${ZBX_NGINX_CONF}"
sed -i -E "s|^#\s*server_name\s+.*;|server_name     ${SERVER_NAME};|" "${ZBX_NGINX_CONF}"

########################################
# Reiniciar e habilitar serviços
########################################
log "Reiniciando serviços Zabbix Server, Agent, Nginx e PHP-FPM"
systemctl restart zabbix-server zabbix-agent nginx php8.4-fpm
log "Habilitando na inicialização"
systemctl enable zabbix-server zabbix-agent nginx php8.4-fpm

log "Concluído. Acesse o frontend via: http://${SERVER_NAME}:${NGINX_LISTEN_PORT}/"