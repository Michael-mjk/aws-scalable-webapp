<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

header('Cache-Control: no-store');

$cfg     = app_config();
$error   = null;
$total   = 0;
$recent  = [];
$servers = [];

try {
    $db = db_connect($cfg);
    ensure_schema($db);

    $stmt = $db->prepare('INSERT INTO visits (instance_id, az) VALUES (?, ?)');
    $stmt->bind_param('ss', $cfg['instance_id'], $cfg['az']);
    $stmt->execute();

    $total   = (int) $db->query('SELECT COUNT(*) FROM visits')->fetch_row()[0];
    $recent  = $db->query('SELECT instance_id, az, created_at FROM visits ORDER BY id DESC LIMIT 8')->fetch_all(MYSQLI_ASSOC);
    $servers = $db->query('SELECT instance_id, az, COUNT(*) AS hits FROM visits GROUP BY instance_id, az ORDER BY hits DESC LIMIT 6')->fetch_all(MYSQLI_ASSOC);
    $db->close();
} catch (Throwable $e) {
    error_log('[webapp] ' . get_class($e) . ': ' . $e->getMessage());
    $error = 'The database did not respond. If an RDS failover is in progress this clears within about a minute. Reload to try again.';
}

$maxHits = max(1, ...array_map(fn ($r) => (int) $r['hits'], $servers ?: [['hits' => 1]]));
$cdn     = rtrim($cfg['cdn_url'], '/');
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Visit Ledger</title>
  <link rel="icon" href="<?= h($cdn) ?>/static/img/logo.svg" type="image/svg+xml">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@500&family=IBM+Plex+Sans:wght@400;600&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="<?= h($cdn) ?>/static/css/style.css">
</head>
<body style="--zone: <?= h(zone_color($cfg['az'])) ?>">
  <div class="zone-band" aria-hidden="true"></div>

  <header class="top">
    <img src="<?= h($cdn) ?>/static/img/logo.svg" alt="" width="28" height="28">
    <span class="brand">Visit Ledger</span>
  </header>

  <main>
    <section class="hero">
      <p class="lead">This page was served by</p>
      <h1 class="instance"><?= h($cfg['instance_id']) ?></h1>
      <p class="zone">in <strong><?= h($cfg['az']) ?></strong></p>
      <p class="hint">Reload to send a new request. The load balancer may hand it to a different server, and the colour bar will change when it lands in another Availability Zone.</p>
    </section>

    <?php if ($error !== null): ?>
      <p class="notice" role="alert"><?= h($error) ?></p>
    <?php else: ?>
      <section class="ledger">
        <div class="servers">
          <h2>Requests per server</h2>
          <p class="total"><?= number_format($total) ?> visits stored in RDS</p>
          <ul>
            <?php foreach ($servers as $s): ?>
              <li style="--zone-row: <?= h(zone_color($s['az'])) ?>">
                <span class="id"><?= h($s['instance_id']) ?></span>
                <span class="az"><?= h($s['az']) ?></span>
                <span class="bar"><span style="width: <?= round(((int) $s['hits'] / $maxHits) * 100) ?>%"></span></span>
                <span class="hits"><?= number_format((int) $s['hits']) ?></span>
              </li>
            <?php endforeach; ?>
          </ul>
        </div>

        <div class="recent">
          <h2>Latest visits</h2>
          <table>
            <thead>
              <tr><th scope="col">Time (UTC)</th><th scope="col">Server</th><th scope="col">Zone</th></tr>
            </thead>
            <tbody>
              <?php foreach ($recent as $r): ?>
                <tr>
                  <td><?= h(substr($r['created_at'], 11)) ?></td>
                  <td class="id"><?= h($r['instance_id']) ?></td>
                  <td><span class="dot" style="background: <?= h(zone_color($r['az'])) ?>"></span><?= h($r['az']) ?></td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      </section>
    <?php endif; ?>
  </main>

  <footer>
    EC2 Auto Scaling behind an Application Load Balancer, MySQL on RDS Multi-AZ, static files from CloudFront.
  </footer>
</body>
</html>
