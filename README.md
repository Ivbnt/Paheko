# Paheko sous Docker

Déploiement Docker de [Paheko](https://paheko.cloud) (gestion d'association) avec :

- **PHP 8.3 + Apache**, avec les règles de réécriture officielles de Paheko
- **Archive vérifiée** : téléchargée depuis fossil.kd2.org et contrôlée par SHA-256
- **Données persistantes** dans un volume Docker (`paheko-data`)
- **Conteneur `cron`** : envoi des e-mails en file d'attente (chaque minute), tâches quotidiennes (rappels de cotisation, corbeille…) et **sauvegardes automatiques**
- **Sauvegardes à chaud** : vérifiées (`integrity_check`), compressées, avec somme SHA-256 et rotation quotidienne / hebdomadaire / mensuelle
- **Mise à jour du schéma** de la base automatique au démarrage après un changement de version
- **HTTPS optionnel** avec Caddy (certificat Let's Encrypt automatique)

## Démarrage rapide

```bash
cp .env.example .env
docker compose up -d --build
```

Ouvrir http://localhost:8080 et suivre l'assistant d'installation de Paheko.

## Mise en production avec HTTPS

Dans `.env` :

```ini
PAHEKO_DOMAIN=paheko.mon-asso.fr
PAHEKO_URL=https://paheko.mon-asso.fr/
```

Le DNS du domaine doit pointer vers le serveur, et les ports 80/443 doivent être libres. Ensuite :

```bash
docker compose --profile https up -d --build
```

Si vous avez déjà un reverse proxy (Traefik, nginx…), ne lancez pas Caddy : pointez votre proxy vers `127.0.0.1:8080`, renseignez `PAHEKO_URL` et transmettez les en-têtes `X-Forwarded-For` / `X-Forwarded-Proto`.

## Sauvegardes

Elles sont écrites sur l'hôte dans `./backups` (modifiable avec `BACKUP_HOST_DIR`) :

```
backups/
├── daily/    14 dernières (BACKUP_KEEP_DAILY)
├── weekly/   copie du dimanche, 8 dernières (BACKUP_KEEP_WEEKLY)
└── monthly/  copie du 1er du mois, 12 dernières (BACKUP_KEEP_MONTHLY)
```

La sauvegarde automatique tourne chaque jour à `BACKUP_TIME` (03:00 par défaut). Elle utilise l'API de sauvegarde de SQLite, donc pas besoin d'arrêter Paheko.

Lancer une sauvegarde à la main :

```bash
docker compose exec cron paheko-backup
```

> Par défaut Paheko stocke aussi les fichiers (documents, pièces jointes) **dans** la base SQLite : la sauvegarde contient donc tout.
>
> Pensez à copier `./backups` ailleurs (autre serveur, cloud, disque externe) : une sauvegarde sur la même machine ne protège pas d'une panne de disque.

### Restaurer

```bash
docker compose stop paheko cron
docker compose run --rm cron paheko-restore /backups/daily/paheko-2026-10-05_030000.sqlite.gz
docker compose up -d
```

Sans argument, `paheko-restore` liste les sauvegardes disponibles. La base remplacée est conservée dans le volume (`association.sqlite.avant-restauration-…`).

## Mettre à jour Paheko

1. Récupérer le SHA-256 de la nouvelle archive :
   ```bash
   curl -sL https://fossil.kd2.org/paheko/uv/paheko-X.Y.Z.tar.gz | sha256sum
   ```
2. Modifier `PAHEKO_VERSION` et `PAHEKO_SHA256` dans `.env`
3. Faire une sauvegarde, puis reconstruire :
   ```bash
   docker compose exec cron paheko-backup
   docker compose up -d --build
   ```

Au démarrage, le conteneur met la base à jour (`paheko upgrade`). Paheko fait aussi sa propre sauvegarde avant migration. Les mises à jour depuis l'interface web sont désactivées : la version est celle de l'image.

## Commandes utiles

```bash
docker compose logs -f                       # journaux
docker compose exec -u www-data paheko paheko db check   # vérifier l'intégrité de la base
docker compose exec -u www-data paheko paheko env        # configuration effective
docker compose exec -u www-data paheko paheko help       # toutes les commandes Paheko
```

## Configuration

Tous les réglages sont dans `.env` (voir [.env.example](.env.example)) et sont convertis en constantes Paheko par [docker/config.local.php](docker/config.local.php).

| Variable | Défaut | Rôle |
|---|---|---|
| `PAHEKO_BIND` / `PAHEKO_PORT` | `127.0.0.1` / `8080` | Adresse et port exposés sur l'hôte |
| `PAHEKO_URL` | auto | URL publique (obligatoire derrière HTTPS) |
| `PAHEKO_DOMAIN` | — | Domaine pour Caddy (profil `https`) |
| `PAHEKO_SECRET_KEY` | générée | Clé secrète (sinon stockée dans le volume) |
| `SMTP_*`, `MAIL_*` | — | Envoi d'e-mails via un serveur SMTP |
| `PAHEKO_CRON_TIME` | `04:00` | Heure des tâches quotidiennes |
| `BACKUP_ENABLED` | `true` | Active la sauvegarde automatique |
| `BACKUP_TIME` | `03:00` | Heure de la sauvegarde |
| `BACKUP_KEEP_DAILY/WEEKLY/MONTHLY` | `14/8/12` | Rotation |
| `TZ` | `Europe/Paris` | Fuseau horaire |

## Structure

```
Dockerfile               image PHP/Apache + Paheko
docker-compose.yml       services paheko, cron, caddy (optionnel)
docker/
  config.local.php       configuration Paheko depuis l'environnement
  apache-vhost.conf      virtual host Apache
  php.ini                réglages PHP
  entrypoint.sh          init du volume, clé secrète, migration de la base
  scheduler.sh           boucle du conteneur cron
  backup.sh              sauvegarde + rotation
  restore.sh             restauration
caddy/Caddyfile          reverse proxy HTTPS
```
