<?php
// Shallow health check used by the ALB and Route 53.
// Deliberately does NOT query the database (see alb.tf for why).
header('Content-Type: text/plain');
header('Cache-Control: no-store');
http_response_code(200);
echo "OK\n";
