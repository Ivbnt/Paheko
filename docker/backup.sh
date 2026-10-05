#!/bin/bash
# Sauvegarde à chaud de la base Paheko, vérifiée, compressée et avec rotation.
#
#   daily/   : les BACKUP_KEEP_DAILY dernières sauvegardes
#   weekly/  : copie du dimanche, BACKUP_KEEP_WEEKLY dernières
#   monthly/ : copie du 1er du mois, BACKUP_KEEP_MONTHLY dernières
#
# Usage manuel : docker compose exec cron paheko-backup
# Toujours exécuté en www-data, même via "docker compose exec"
if [ "$(id -u)" = "0" ]; then exec setpriv --reuid=www-data --regid=www-data --init-groups -- "$0" "$@"; fi
set -euo pipefail

DIR="${BACKUP_DIR:-/backups}"
KEEP_DAILY="${BACKUP_KEEP_DAILY:-14}"
KEEP_WEEKLY="${BACKUP_KEEP_WEEKLY:-8}"
KEEP_MONTHLY="${BACKUP_KEEP_MONTHLY:-12}"
DB="${PAHEKO_DATA:-/var/lib/paheko}/association.sqlite"

log() { echo "[$(date '+%F %T')] [backup] $*"; }

[ -f "$DB" ] || { log "Aucune base trouvée ($DB) : Paheko n'est pas encore installé."; exit 0; }

mkdir -p "$DIR/daily" "$DIR/weekly" "$DIR/monthly"

name="paheko-$(date +%F_%H%M%S).sqlite"
tmp="$DIR/.${name}.tmp"
trap 'rm -f "$tmp" "$tmp.gz"' EXIT

# Copie cohérente via l'API de sauvegarde SQLite de Paheko (fonctionne pendant l'utilisation)
paheko db backup "$tmp"

check=$(sqlite3 "$tmp" 'PRAGMA integrity_check;' | head -n1)
if [ "$check" != "ok" ]; then
	log "ERREUR : la copie est corrompue ($check)"
	exit 1
fi

gzip -9 "$tmp"
mv "$tmp.gz" "$DIR/daily/$name.gz"
(cd "$DIR/daily" && sha256sum "$name.gz" > "$name.gz.sha256")
log "OK : daily/$name.gz ($(du -h "$DIR/daily/$name.gz" | cut -f1))"

copy() { ln -f "$1" "$2" 2>/dev/null || cp -f "$1" "$2"; }

if [ "$(date +%u)" = "7" ]; then
	copy "$DIR/daily/$name.gz" "$DIR/weekly/$name.gz"
	copy "$DIR/daily/$name.gz.sha256" "$DIR/weekly/$name.gz.sha256"
fi
if [ "$(date +%d)" = "01" ]; then
	copy "$DIR/daily/$name.gz" "$DIR/monthly/$name.gz"
	copy "$DIR/daily/$name.gz.sha256" "$DIR/monthly/$name.gz.sha256"
fi

prune() {
	local d="$1" keep="$2" f
	# Le nom contient la date : tri inverse = du plus récent au plus ancien
	find "$d" -maxdepth 1 -name 'paheko-*.sqlite.gz' | sort -r | tail -n +"$((keep + 1))" | while read -r f; do
		rm -f "$f" "$f.sha256"
		log "Supprimée : ${f#"$DIR"/}"
	done
}

prune "$DIR/daily" "$KEEP_DAILY"
prune "$DIR/weekly" "$KEEP_WEEKLY"
prune "$DIR/monthly" "$KEEP_MONTHLY"
