# syntax=docker/dockerfile:1
FROM php:8.3-apache-bookworm

ARG PAHEKO_VERSION=1.3.23
ARG PAHEKO_SHA256=de094f790bb4448bed641d548e0a3ec85b5ffe5d4a26cb9ddd01b8cb5a400434

ENV TZ=Europe/Paris \
    PAHEKO_ROOT=/var/www/paheko \
    PAHEKO_DATA=/var/lib/paheko \
    BACKUP_DIR=/backups

# Dépendances système + extensions PHP utilisées par Paheko
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        sqlite3 tzdata curl ca-certificates \
        libicu-dev libzip-dev libpng-dev libjpeg62-turbo-dev libwebp-dev libfreetype6-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" intl zip gd opcache; \
    rm -rf /var/lib/apt/lists/*; \
    for ext in intl zip gd sqlite3 mbstring openssl; do php -m | grep -qix "$ext"; done

# Téléchargement et vérification de Paheko
RUN set -eux; \
    curl -fsSL -o /tmp/paheko.tar.gz "https://fossil.kd2.org/paheko/uv/paheko-${PAHEKO_VERSION}.tar.gz"; \
    echo "${PAHEKO_SHA256}  /tmp/paheko.tar.gz" | sha256sum -c -; \
    mkdir -p "$PAHEKO_ROOT"; \
    tar xzf /tmp/paheko.tar.gz -C "$PAHEKO_ROOT" --strip-components=1; \
    rm /tmp/paheko.tar.gz; \
    ln -s "$PAHEKO_DATA/cache/web" "$PAHEKO_ROOT/www/.cache"; \
    ln -s "$PAHEKO_ROOT/bin/paheko" /usr/local/bin/paheko; \
    chown -R root:root "$PAHEKO_ROOT"

COPY docker/config.local.php     $PAHEKO_ROOT/config.local.php
COPY docker/php.ini              /usr/local/etc/php/conf.d/zz-paheko.ini
COPY docker/apache-vhost.conf    /etc/apache2/sites-available/000-default.conf
COPY --chmod=0755 docker/entrypoint.sh  /usr/local/bin/paheko-entrypoint
COPY --chmod=0755 docker/scheduler.sh   /usr/local/bin/paheko-scheduler
COPY --chmod=0755 docker/backup.sh      /usr/local/bin/paheko-backup
COPY --chmod=0755 docker/restore.sh     /usr/local/bin/paheko-restore

RUN set -eux; \
    a2enmod rewrite headers remoteip setenvif; \
    printf 'ServerTokens Prod\nServerSignature Off\nTraceEnable Off\n' > /etc/apache2/conf-available/zz-security.conf; \
    a2enconf zz-security; \
    mkdir -p "$PAHEKO_DATA" "$BACKUP_DIR"; \
    chown www-data:www-data "$PAHEKO_DATA" "$BACKUP_DIR"

VOLUME ["/var/lib/paheko"]
WORKDIR /var/www/paheko
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1/ || exit 1

ENTRYPOINT ["paheko-entrypoint"]
CMD ["apache2-foreground"]
