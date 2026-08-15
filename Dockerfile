# Self-contained Pterodactyl Panel on Alpine Linux with Auto SSL & Sleep Infinity
FROM alpine:3.19

LABEL maintainer="Pterodactyl Alpine All-in-One SSL"
LABEL description="Single Dockerfile installation for Pterodactyl Panel on Alpine Linux"

ENV DEBIAN_FRONTEND=noninteractive \
    APP_ENV=production \
    APP_ENVIRONMENT_ONLY=true

# 1. Install System Dependencies, Database, Redis, Web Server, PHP 8.3 & OpenSSL
RUN apk update && apk add --no-cache \
    bash \
    curl \
    tar \
    unzip \
    git \
    ca-certificates \
    openssl \
    supervisor \
    nginx \
    mariadb \
    mariadb-client \
    redis \
    cronie \
    composer \
    php83 \
    php83-fpm \
    php83-cli \
    php83-common \
    php83-mbstring \
    php83-bcmath \
    php83-xml \
    php83-curl \
    php83-zip \
    php83-pdo \
    php83-pdo_mysql \
    php83-gd \
    php83-iconv \
    php83-fileinfo \
    php83-openssl \
    php83-tokenizer \
    php83-json \
    php83-dom \
    php83-simplexml \
    php83-session \
    php83-ctype \
    php83-phar \
    php83-redis \
    php83-opcache \
    php83-posix && \
    ln -sf /usr/bin/php83 /usr/bin/php && \
    ln -sf /usr/sbin/php-fpm83 /usr/bin/php-fpm

# 2. Create Required System & Certs Directories
RUN mkdir -p /var/www/pterodactyl \
    /certs \
    /run/mysqld \
    /var/lib/mysql \
    /run/nginx \
    /var/log/supervisor \
    /var/log/nginx \
    /var/log/pterodactyl && \
    chown -R mysql:mysql /run/mysqld /var/lib/mysql && \
    chown -R nginx:nginx /run/nginx /var/www/pterodactyl

# 3. Create Nginx Configuration with SSL & HTTP Redirect Inline
RUN cat << 'EOF' > /etc/nginx/http.d/default.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name cp.kexcloud.sryze.cc;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name cp.kexcloud.sryze.cc;

    ssl_certificate /certs/fullchain.pem;
    ssl_certificate_key /certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/pterodactyl/public;
    index index.php;
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log error;

    client_max_body_size 100M;
    client_body_buffer_size 128k;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# 4. Create Supervisor Configuration (Available if started manually)
RUN cat << 'EOF' > /etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/run/supervisord.pid

[program:mariadb]
command=/usr/bin/mariadbd-safe --user=mysql
autorestart=true
priority=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:redis]
command=redis-server
autorestart=true
priority=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:php-fpm]
command=php-fpm83 -F
autorestart=true
priority=20
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g "daemon off;"
autorestart=true
priority=20
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:ptero-queue]
command=php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --tries=3
user=nginx
directory=/var/www/pterodactyl
autorestart=true
priority=30
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:cron]
command=crond -f -l 2
autorestart=true
priority=30
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# 5. Create Startup & SSL Generation Script Inline
RUN cat << 'EOF' > /entrypoint.sh
#!/bin/bash
set -e

echo "=== Pterodactyl Panel Auto SSL Startup ==="

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE:-panel}"
DB_USERNAME="${DB_USERNAME:-pterodactyl}"
DB_PASSWORD="${DB_PASSWORD:-pterodactyl_pass_123}"
APP_URL="${APP_URL:-https://cp.kexcloud.sryze.cc}"
APP_TIMEZONE="${APP_TIMEZONE:-UTC}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@kexcloud.sryze.cc}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-Admin}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-User}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-password}"

# 5.1 Generate OpenSSL Certificate in /certs/ if missing
mkdir -p /certs
if [ ! -f "/certs/fullchain.pem" ] || [ ! -f "/certs/privkey.pem" ]; then
    echo "[+] Generating SSL certificate for cp.kexcloud.sryze.cc in /certs/..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /certs/privkey.pem \
        -out /certs/fullchain.pem \
        -subj "/C=US/ST=State/L=City/O=KexCloud/CN=cp.kexcloud.sryze.cc"
    chmod 600 /certs/privkey.pem
    chmod 644 /certs/fullchain.pem
fi

# 5.2 Initialize MariaDB on first run
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[+] Initializing MariaDB storage..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null
    
    mariadbd-safe --user=mysql &
    PID_MYSQL=$!
    
    until mariadb-admin ping --silent; do
        sleep 2
    done
    
    mariadb -u root <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_DATABASE}\`;
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'%';
GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOSQL

    kill -s TERM $PID_MYSQL
    wait $PID_MYSQL 2>/dev/null || true
fi

# 5.3 Download Pterodactyl Panel
cd /var/www/pterodactyl
if [ ! -f "artisan" ]; then
    echo "[+] Downloading Pterodactyl Panel release..."
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    rm panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env

    echo "[+] Installing PHP dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
fi

# 5.4 Configure .env File
if [ ! -f ".env" ]; then
    cp .env.example .env
fi

if ! grep -q "APP_KEY=base64:" .env; then
    echo "[+] Generating APP_KEY..."
    php artisan key:generate --force
fi

sed -i "s|^APP_URL=.*|APP_URL=${APP_URL}|g" .env
sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=${APP_TIMEZONE}|g" .env
sed -i "s|^DB_HOST=.*|DB_HOST=${DB_HOST}|g" .env
sed -i "s|^DB_PORT=.*|DB_PORT=${DB_PORT}|g" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_DATABASE}|g" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USERNAME}|g" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=redis|g" .env
sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|g" .env
sed -i "s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|g" .env
sed -i "s|^REDIS_HOST=.*|REDIS_HOST=127.0.0.1|g" .env

# 5.5 Database Migrations & Initial Admin User Creation
mariadbd-safe --user=mysql &
PID_MYSQL=$!
redis-server --daemonize yes

until mariadb-admin ping --silent; do
    sleep 1
done

echo "[+] Migrating database..."
php artisan migrate --seed --force

USER_COUNT=$(php artisan db:table users --count 2>/dev/null || echo "0")
if [ "$USER_COUNT" = "0" ] || [ -z "$USER_COUNT" ]; then
    echo "[+] Creating admin user: ${ADMIN_EMAIL}"
    php artisan p:user:make \
        --email="${ADMIN_EMAIL}" \
        --username="${ADMIN_USERNAME}" \
        --firstname="${ADMIN_FIRSTNAME}" \
        --lastname="${ADMIN_LASTNAME}" \
        --password="${ADMIN_PASSWORD}" \
        --admin=1
fi

kill -s TERM $PID_MYSQL 2>/dev/null || true
redis-cli shutdown 2>/dev/null || true
wait $PID_MYSQL 2>/dev/null || true

# 5.6 Permissions & Cron Setup
chown -R nginx:nginx /var/www/pterodactyl
chmod -R 775 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache
echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -u nginx -

echo "=== Setup complete! Handoff to CMD command ==="
exec "$@"
EOF

RUN chmod +x /entrypoint.sh

WORKDIR /var/www/pterodactyl

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]
