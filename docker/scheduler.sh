#!/bin/bash
# Planificateur du conteneur "cron" :
#  - toutes les minutes : envoi des e-mails en attente (paheko queue run)
#  - chaque jour à PAHEKO_CRON_TIME : tâches quotidiennes (rappels, corbeille…)
#  - chaque jour à BACKUP_TIME : sauvegarde de la base (paheko-backup)
set -uo pipefail

DB="${PAHEKO_DATA:-/var/lib/paheko}/association.sqlite"
CRON_TIME="${PAHEKO_CRON_TIME:-04:00}"
BACKUP_TIME="${BACKUP_TIME:-03:00}"
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"

log() { echo "[$(date '+%F %T')] $*"; }
hhmm() { echo $((10#${1/:/})); }   # "03:00" -> 300

last_cron=""
last_backup=""

trap 'log "Arrêt du planificateur"; exit 0' TERM INT

log "Planificateur démarré (tâches quotidiennes à $CRON_TIME, sauvegarde à $BACKUP_TIME, TZ=${TZ:-UTC})"

while true; do
	if [ -f "$DB" ]; then
		paheko queue run || log "ATTENTION : 'paheko queue run' a échoué"

		today=$(date +%F)
		now=$((10#$(date +%H%M)))

		if [ "$today" != "$last_cron" ] && [ "$now" -ge "$(hhmm "$CRON_TIME")" ]; then
			log "Tâches quotidiennes Paheko…"
			if paheko cron; then last_cron="$today"; else log "ERREUR : 'paheko cron' a échoué"; fi
		fi

		if [ "${BACKUP_ENABLED,,}" = "true" ] && [ "$today" != "$last_backup" ] && [ "$now" -ge "$(hhmm "$BACKUP_TIME")" ]; then
			# Pas de doublon si le conteneur redémarre dans la journée
			if compgen -G "${BACKUP_DIR:-/backups}/daily/paheko-${today}_*.sqlite.gz" >/dev/null; then
				last_backup="$today"
			elif paheko-backup; then
				last_backup="$today"
			else
				log "ERREUR : la sauvegarde a échoué"
			fi
		fi
	fi

	sleep 60 &
	wait $!
done
