#!/bin/bash
# Prépare le volume de données puis lance la commande (Apache par défaut).
set -euo pipefail

DATA="${PAHEKO_DATA:-/var/lib/paheko}"
DB="$DATA/association.sqlite"

as_www() {
	if [ "$(id -u)" = "0" ]; then
		setpriv --reuid=www-data --regid=www-data --init-groups -- "$@"
	else
		"$@"
	fi
}

if [ "$(id -u)" = "0" ]; then
	mkdir -p "$DATA" "${BACKUP_DIR:-/backups}"
	chown www-data:www-data "$DATA"
	chown www-data:www-data "${BACKUP_DIR:-/backups}" 2>/dev/null || true

	# Clé secrète persistante (sinon les sessions sautent à chaque recréation du conteneur)
	if [ -z "${PAHEKO_SECRET_KEY:-}" ] && [ ! -s "$DATA/.secret_key" ]; then
		(umask 077; head -c 48 /dev/urandom | base64 | tr -d '\n/+=' > "$DATA/.secret_key")
		chown www-data:www-data "$DATA/.secret_key"
		echo "[paheko] Clé secrète générée dans $DATA/.secret_key"
	fi
fi

# Mise à jour du schéma après un changement de version de l'image (uniquement par le conteneur web)
if [ "${1:-}" = "apache2-foreground" ] && [ -f "$DB" ]; then
	echo "[paheko] Vérification du schéma de la base…"
	set +e
	as_www paheko upgrade
	rc=$?
	set -e
	case $rc in
		0) echo "[paheko] Base à jour." ;;
		2) echo "[paheko] Base mise à jour (sauvegarde automatique faite par Paheko dans $DATA/backups)." ;;
		*) echo "[paheko] ERREUR pendant la mise à jour de la base (code $rc)." >&2; exit $rc ;;
	esac
fi

case "${1:-}" in
	# Apache démarre en root puis bascule seul en www-data
	apache2-foreground) exec "$@" ;;
	# Les commandes Paheko tournent toujours en www-data
	paheko-scheduler|paheko-backup|paheko-restore|paheko) as_www "$@"; exit $? ;;
	*) exec "$@" ;;
esac
