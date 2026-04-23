#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# =========================================
# WordPress + Nginx (otimizado) + MariaDB + PHP (Ubuntu)
# v2 - segura, idempotente e automatizável
# =========================================

# -------- Config padrão (pode sobrescrever com flags) --------
DOMAIN_NAME=""
DB_NAME="wordpress"
DB_USER="wordpressuser"
DB_PASSWORD=""
SITE_ROOT_BASE="/var/www/html"
ENABLE_UFW="yes"
INSTALL_CERTBOT="no"   # mude para "yes" se quiser SSL automático
NON_INTERACTIVE="no"

# -------- Helpers --------
log()  { echo -e "\n[INFO] $*"; }
warn() { echo -e "\n[WARN] $*"; }
err()  { echo -e "\n[ERRO] $*" >&2; }
die()  { err "$*"; exit 1; }

trap 'err "Falha na linha $LINENO. Abortando."' ERR

usage() {
  cat <<EOF
Uso:
  sudo bash install.sh --domain exemplo.com.br [opções]

Opções:
  --domain <dominio>         Domínio do site (obrigatório)
  --db-name <nome>           Nome do banco (padrão: wordpress)
  --db-user <usuario>        Usuário do banco (padrão: wordpressuser)
  --db-pass <senha>          Senha do banco (se omitido, gera aleatória)
  --site-root-base <path>    Base dos sites (padrão: /var/www/html)
  --enable-ufw <yes|no>      Configura UFW (padrão: yes)
  --certbot <yes|no>         Instala/cfg SSL com certbot (padrão: no)
  --non-interactive <yes|no> Não pergunta nada (padrão: no)
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando ausente: $1"
}

configure_mariadb_tuning() {
  local mariadb_cnf="/etc/mysql/mariadb.conf.d/99-magalu-wordpress-optimized.cnf"
  local mem_kb mem_gb bp_size bp_instances log_size max_conn

  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  mem_gb=$(( mem_kb / 1024 / 1024 ))

  # Perfil "forte" solicitado (pensado para servidor grande ~64GB RAM)
  if (( mem_gb >= 56 )); then
    bp_size="44G"
    bp_instances="16"
    log_size="2G"
    max_conn="400"
    warn "Aplicando perfil MariaDB HIGH-RAM (>=56GB): buffer_pool=44G."
  else
    # Perfil automático para não estourar RAM em VPS menores
    local bp_mb log_mb
    bp_mb=$(( mem_gb * 65 / 100 * 1024 ))
    (( bp_mb < 256 )) && bp_mb=256
    bp_size="${bp_mb}M"

    bp_instances=$(( mem_gb / 4 ))
    (( bp_instances < 1 )) && bp_instances=1
    (( bp_instances > 8 )) && bp_instances=8

    log_mb=$(( bp_mb / 20 ))
    (( log_mb < 128 )) && log_mb=128
    (( log_mb > 2048 )) && log_mb=2048
    log_size="${log_mb}M"

    max_conn=200
    if (( mem_gb >= 16 )); then
      max_conn=300
    fi

    warn "RAM detectada: ${mem_gb}GB. Aplicando perfil MariaDB auto-ajustado para estabilidade."
  fi

  cat >"$mariadb_cnf" <<EOF
[mysqld]
skip-log-bin
innodb_file_per_table = 1
innodb_thread_concurrency = 0

# === MEMORIA PRINCIPAL ===
innodb_buffer_pool_size         = ${bp_size}
innodb_buffer_pool_instances    = ${bp_instances}
innodb_log_file_size            = ${log_size}
innodb_log_buffer_size          = 64M

# === SEGURANCA vs PERFORMANCE ===
innodb_flush_log_at_trx_commit  = 2
innodb_flush_method             = O_DIRECT

# === I/O para SSD moderno ===
innodb_io_capacity              = 4000
innodb_io_capacity_max          = 8000
innodb_read_io_threads          = 16
innodb_write_io_threads         = 16

innodb_checksum_algorithm       = crc32
innodb_log_compressed_pages     = OFF
innodb_change_buffering         = all

# === Cache e Tabelas ===
table_open_cache                = 4000
table_definition_cache          = 2000
thread_cache_size               = 64
max_connections                 = ${max_conn}
tmp_table_size                  = 128M
max_heap_table_size             = 128M

# === Seguranca e estabilidade ===
open_files_limit                = 65535
skip-host-cache
skip-name-resolve
default_authentication_plugin   = mysql_native_password
sql_mode                        = NO_ENGINE_SUBSTITUTION

# === Desabilitar itens obsoletos/inuteis ===
query_cache_size                = 0
query_cache_type                = 0
performance_schema              = 0
EOF

  log "Config MariaDB otimizada gravada em: $mariadb_cnf"
}

is_valid_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) DOMAIN_NAME="${2:-}"; shift 2 ;;
      --db-name) DB_NAME="${2:-}"; shift 2 ;;
      --db-user) DB_USER="${2:-}"; shift 2 ;;
      --db-pass) DB_PASSWORD="${2:-}"; shift 2 ;;
      --site-root-base) SITE_ROOT_BASE="${2:-}"; shift 2 ;;
      --enable-ufw) ENABLE_UFW="${2:-}"; shift 2 ;;
      --certbot) INSTALL_CERTBOT="${2:-}"; shift 2 ;;
      --non-interactive) NON_INTERACTIVE="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Parâmetro desconhecido: $1" ;;
    esac
  done
}

ask_missing_inputs() {
  if [[ -z "$DOMAIN_NAME" && "$NON_INTERACTIVE" != "yes" ]]; then
    read -rp "Digite o domínio (ex: exemplo.com.br): " DOMAIN_NAME
  fi
}

# -------- Main --------
parse_args "$@"
ask_missing_inputs

[[ -n "$DOMAIN_NAME" ]] || die "Domínio é obrigatório. Use --domain."
is_valid_domain "$DOMAIN_NAME" || die "Domínio inválido: $DOMAIN_NAME"

[[ "$ENABLE_UFW" == "yes" || "$ENABLE_UFW" == "no" ]] || die "--enable-ufw deve ser yes/no"
[[ "$INSTALL_CERTBOT" == "yes" || "$INSTALL_CERTBOT" == "no" ]] || die "--certbot deve ser yes/no"

require_cmd apt
require_cmd systemctl
require_cmd openssl
require_cmd curl
require_cmd awk
require_cmd sed

if [[ "$(id -u)" -ne 0 ]]; then
  die "Execute como root (sudo). Ex: sudo bash install.sh --domain exemplo.com.br"
fi

if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
fi

SITE_ROOT="${SITE_ROOT_BASE}/${DOMAIN_NAME}"
NGINX_AVAILABLE="/etc/nginx/sites-available/${DOMAIN_NAME}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN_NAME}"

log "Domínio: $DOMAIN_NAME"
log "Site root: $SITE_ROOT"
log "Banco: $DB_NAME / Usuário: $DB_USER"

# Log em arquivo
exec > >(tee -a /var/log/wp-bootstrap.log) 2>&1

log "Atualizando pacotes..."
apt update -y
apt upgrade -y

log "Instalando Nginx, MariaDB, PHP e utilitários..."
apt install -y nginx mariadb-server php-fpm php-mysql php-cli php-curl php-xml php-mbstring php-gd php-zip unzip tar

PHP_FPM_SOCK="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | head -n1 || true)"
[[ -n "$PHP_FPM_SOCK" ]] || die "Socket do PHP-FPM não encontrado em /run/php"

if [[ "$ENABLE_UFW" == "yes" ]]; then
  log "Configurando UFW com segurança..."
  ufw allow OpenSSH
  ufw allow 'Nginx Full'
  ufw --force enable
fi

log "Garantindo MariaDB ativo..."
systemctl enable --now mariadb

log "Aplicando tuning de performance no MariaDB..."
configure_mariadb_tuning
systemctl restart mariadb

log "Criando banco e usuário no MariaDB (idempotente)..."
mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

log "Preparando pasta do site..."
mkdir -p "$SITE_ROOT"
chown -R www-data:www-data "$SITE_ROOT"

if [[ ! -f "${SITE_ROOT}/wp-settings.php" ]]; then
  log "Baixando e instalando WordPress..."
  TMP_DIR="$(mktemp -d)"
  curl -fsSL https://wordpress.org/latest.tar.gz -o "${TMP_DIR}/latest.tar.gz"
  tar -xzf "${TMP_DIR}/latest.tar.gz" -C "${TMP_DIR}"
  cp -a "${TMP_DIR}/wordpress/." "$SITE_ROOT/"
  rm -rf "$TMP_DIR"
else
  warn "WordPress já parece instalado em $SITE_ROOT (pulando download)."
fi

log "Criando wp-config.php (se não existir)..."
if [[ ! -f "${SITE_ROOT}/wp-config.php" ]]; then
  cp "${SITE_ROOT}/wp-config-sample.php" "${SITE_ROOT}/wp-config.php"

  sed -i "s/database_name_here/${DB_NAME}/" "${SITE_ROOT}/wp-config.php"
  sed -i "s/username_here/${DB_USER}/" "${SITE_ROOT}/wp-config.php"
  sed -i "s/password_here/${DB_PASSWORD//\//\\/}/" "${SITE_ROOT}/wp-config.php"

  # Salts oficiais
  SALTS="$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/)"
  awk -v salts="$SALTS" '
    BEGIN { done=0 }
    /AUTH_KEY/ && done==0 { print salts; done=1; next }
    !/AUTH_KEY|SECURE_AUTH_KEY|LOGGED_IN_KEY|NONCE_KEY|AUTH_SALT|SECURE_AUTH_SALT|LOGGED_IN_SALT|NONCE_SALT/ { print }
  ' "${SITE_ROOT}/wp-config.php" > "${SITE_ROOT}/wp-config.php.tmp"
  mv "${SITE_ROOT}/wp-config.php.tmp" "${SITE_ROOT}/wp-config.php"
fi

log "Ajustando permissões..."
chown -R www-data:www-data "$SITE_ROOT"
find "$SITE_ROOT" -type d -exec chmod 755 {} \;
find "$SITE_ROOT" -type f -exec chmod 644 {} \;
chmod 600 "${SITE_ROOT}/wp-config.php" || true

log "Criando snippet do Let's Encrypt (idempotente)..."
mkdir -p /etc/nginx/snippets
cat >/etc/nginx/snippets/letsencrypt.conf <<'EOF'
location ^~ /.well-known/acme-challenge/ {
    allow all;
    root /var/www/html;
    default_type "text/plain";
    try_files $uri =404;
}
EOF

log "Criando configuração Nginx do domínio..."
cat >"$NGINX_AVAILABLE" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    root ${SITE_ROOT};
    index index.php index.html;
    client_max_body_size 64M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCK};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 120s;
        fastcgi_buffer_size 32k;
        fastcgi_buffers 8 16k;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp)$ {
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
        access_log off;
        log_not_found off;
    }

    location = /xmlrpc.php { deny all; }
    location ~* /(?:uploads|files)/.*\.php$ { deny all; }
    location ~ /\. { deny all; }
    location = /wp-config.php { deny all; }

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    include snippets/letsencrypt.conf;
}
EOF

if [[ ! -L "$NGINX_ENABLED" ]]; then
  ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
fi

if [[ -f /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
fi

log "Validando e reiniciando Nginx..."
nginx -t
systemctl restart nginx
systemctl enable nginx

if [[ "$INSTALL_CERTBOT" == "yes" ]]; then
  log "Instalando Certbot e emitindo SSL..."
  apt install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME" --non-interactive --agree-tos -m "admin@${DOMAIN_NAME}" --redirect
fi

log "Concluído com sucesso."
echo
echo "====================================================="
echo "Site:        http://${DOMAIN_NAME}"
echo "Pasta:       ${SITE_ROOT}"
echo "DB Name:     ${DB_NAME}"
echo "DB User:     ${DB_USER}"
echo "DB Password: ${DB_PASSWORD}"
echo "Log setup:   /var/log/wp-bootstrap.log"
echo "====================================================="
echo
warn "Guarde a senha do banco em local seguro."
