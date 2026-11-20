<?php
declare(strict_types=1);

const CRED_CACHE = '/var/cache/webapp/db-credentials.json';
const RDS_CA     = '/etc/pki/rds/global-bundle.pem';

function app_config(): array
{
    static $cfg = null;
    return $cfg ??= require __DIR__ . '/config.php';
}

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Each AZ gets its own colour so a reload that lands on another AZ is obvious. */
function zone_color(string $az): string
{
    return match (substr($az, -1)) {
        'a'     => '#0E7A73',
        'b'     => '#B0650A',
        'c'     => '#4B4FB0',
        default => '#45606B',
    };
}

/**
 * DB credentials come from the RDS-managed secret in Secrets Manager, using
 * the instance role. They are cached in a file only the web server can read.
 * RDS rotates this password automatically, so on "access denied" the caller
 * asks for a forced refresh.
 */
function db_credentials(array $cfg, bool $refresh = false): array
{
    if (!$refresh && is_readable(CRED_CACHE)) {
        $cached = json_decode((string) file_get_contents(CRED_CACHE), true);
        if (is_array($cached) && isset($cached['username'], $cached['password'])) {
            return $cached;
        }
    }

    $cmd = sprintf(
        'HOME=/tmp /usr/bin/aws secretsmanager get-secret-value --region %s --secret-id %s --query SecretString --output text 2>/dev/null',
        escapeshellarg($cfg['region']),
        escapeshellarg($cfg['secret_arn'])
    );
    $secret = json_decode(trim((string) shell_exec($cmd)), true);

    if (!is_array($secret) || !isset($secret['username'], $secret['password'])) {
        throw new RuntimeException('Could not read the database secret from Secrets Manager.');
    }

    $creds = ['username' => $secret['username'], 'password' => $secret['password']];
    $tmp = CRED_CACHE . '.' . getmypid();
    file_put_contents($tmp, json_encode($creds), LOCK_EX);
    chmod($tmp, 0600);
    rename($tmp, CRED_CACHE);

    return $creds;
}

function db_open(array $cfg, array $creds): mysqli
{
    $db = mysqli_init();
    $db->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);
    $db->options(MYSQLI_OPT_SSL_VERIFY_SERVER_CERT, true);
    $db->ssl_set(null, null, RDS_CA, null, null); // encryption in transit
    $db->real_connect(
        $cfg['db_host'],
        $creds['username'],
        $creds['password'],
        $cfg['db_name'],
        (int) $cfg['db_port'],
        null,
        MYSQLI_CLIENT_SSL
    );
    $db->set_charset('utf8mb4');
    return $db;
}

function db_connect(array $cfg): mysqli
{
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    try {
        return db_open($cfg, db_credentials($cfg));
    } catch (mysqli_sql_exception $e) {
        if ($e->getCode() !== 1045) { // 1045 = access denied -> password was rotated
            throw $e;
        }
        return db_open($cfg, db_credentials($cfg, true));
    }
}

function ensure_schema(mysqli $db): void
{
    $db->query(
        'CREATE TABLE IF NOT EXISTS visits (
            id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            instance_id VARCHAR(32) NOT NULL,
            az          VARCHAR(32) NOT NULL,
            created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_instance (instance_id)
        ) ENGINE=InnoDB'
    );
}
