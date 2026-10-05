<?php
/**
 * Configuration Paheko pour Docker.
 * Toutes les valeurs viennent des variables d'environnement (voir .env.example).
 * Ne pas modifier ici : changez le fichier .env puis `docker compose up -d`.
 */

namespace Paheko;

$env = static function (string $name, $default = null) {
	$v = getenv($name);
	return ($v === false || $v === '') ? $default : $v;
};

$bool = static function (string $name, bool $default) use ($env): bool {
	return filter_var($env($name, $default ? 'true' : 'false'), FILTER_VALIDATE_BOOLEAN);
};

// Données persistantes (volume Docker)
define('Paheko\DATA_ROOT', '/var/lib/paheko');
// Les extensions livrées avec Paheko restent dans l'image
define('Paheko\PLUGINS_ROOT', __DIR__ . '/data/plugins');

// Clé secrète : variable d'env, sinon fichier généré au 1er démarrage
$secret = $env('PAHEKO_SECRET_KEY');
if (!$secret && is_readable(DATA_ROOT . '/.secret_key')) {
	$secret = trim(file_get_contents(DATA_ROOT . '/.secret_key'));
}
if ($secret) {
	define('Paheko\SECRET_KEY', $secret);
}

// URL publique (obligatoire derrière un reverse proxy HTTPS)
if ($url = $env('PAHEKO_URL')) {
	define('Paheko\WWW_URL', rtrim($url, '/') . '/');
}

// Volume local (pas NFS) => WAL est sûr et bien plus rapide
define('Paheko\SQLITE_JOURNAL_MODE', $env('PAHEKO_SQLITE_JOURNAL_MODE', 'WAL'));

// Les tâches planifiées et l'envoi d'e-mails sont assurés par le conteneur "cron"
define('Paheko\USE_CRON', $bool('PAHEKO_USE_CRON', true));

// Les mises à jour se font en changeant d'image, pas depuis l'interface
define('Paheko\ENABLE_UPGRADES', false);

define('Paheko\SHOW_ERRORS', $bool('PAHEKO_SHOW_ERRORS', false));
define('Paheko\ENABLE_TECH_DETAILS', $bool('PAHEKO_TECH_DETAILS', true));
define('Paheko\DISABLE_INSTALL_PING', $bool('PAHEKO_DISABLE_INSTALL_PING', false));

if ($v = $env('PAHEKO_FILE_VERSIONING_POLICY')) {
	define('Paheko\FILE_VERSIONING_POLICY', $v);
}

// E-mails
if ($bool('PAHEKO_DISABLE_EMAIL', false)) {
	define('Paheko\DISABLE_EMAIL', true);
}

if ($host = $env('SMTP_HOST')) {
	define('Paheko\SMTP_HOST', $host);
	define('Paheko\SMTP_PORT', (int) $env('SMTP_PORT', 587));
	define('Paheko\SMTP_USER', $env('SMTP_USER'));
	define('Paheko\SMTP_PASSWORD', $env('SMTP_PASSWORD'));
	define('Paheko\SMTP_SECURITY', $env('SMTP_SECURITY', 'STARTTLS'));
}

if ($v = $env('MAIL_SENDER')) {
	define('Paheko\MAIL_SENDER', $v);
}

if ($v = $env('MAIL_RETURN_PATH')) {
	define('Paheko\MAIL_RETURN_PATH', $v);
}

if ($v = $env('MAIL_ERRORS')) {
	define('Paheko\MAIL_ERRORS', $v);
}

unset($env, $bool, $secret, $url, $host, $v);
