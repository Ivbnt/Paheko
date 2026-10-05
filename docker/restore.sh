#!/bin/bash
# Restaure une sauvegarde. Paheko doit être ARRÊTÉ pendant l'opération :
#
#   docker compose stop paheko cron
#   docker compose run --rm cron paheko-restore /backups/daily/paheko-AAAA-MM-JJ_HHMMSS.sqlite.gz
#   docker compose up -d
#
# La base actuelle est conservée à côté (association.sqlite.avant-restauration-<date>).
# Toujours exécuté en www-data, même via "docker compose exec"
if [ "$(id -u)" = "0" ]; then exec setpriv --reuid=www-data --regid=www-data --init-groups -- "$0" "$@"; fi
set -euo pipefail

SRC="${1:-}"
DATA="${PAHEKO_DATA:-/var/lib/paheko}"
DB="$DATA/association.sqlite"

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
	echo "Usage : paheko-restore /backups/daily/paheko-….sqlite.gz (ou .sqlite)" >&2
	echo "Sauvegardes disponibles :" >&2
	find "${BACKUP_DIR:-/backups}" -name 'paheko-*.sqlite*' ! -name '*.sha256' 2>/dev/null | sort >&2
	exit 1
fi

if [ -f "$SRC.sha256" ]; then
	(cd "$(dirname "$SRC")" && sha256sum -c "$(basename "$SRC").sha256")
fi

tmp="$DATA/.restore.tmp"
trap 'rm -f "$tmp"' EXIT

case "$SRC" in
	*.gz) gunzip -c "$SRC" > "$tmp" ;;
	*)    cp "$SRC" "$tmp" ;;
esac

check=$(sqlite3 "$tmp" 'PRAGMA integrity_check;' | head -n1)
[ "$check" = "ok" ] || { echo "ERREUR : sauvegarde corrompue ($check)" >&2; exit 1; }

if [ -f "$DB" ]; then
	old="$DB.avant-restauration-$(date +%F_%H%M%S)"
	mv "$DB" "$old"
	echo "Base actuelle conservée : $old"
fi
rm -f "$DB-wal" "$DB-shm" "$DB-journal"
mv "$tmp" "$DB"
# Le cache web peut contenir des pages de l'ancienne base
rm -rf "$DATA/cache/web"

echo "Restauration terminée. Relancez : docker compose up -d"
