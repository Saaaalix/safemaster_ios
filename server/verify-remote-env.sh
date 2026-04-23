#!/usr/bin/env bash
# 在宝塔 / SSH 中，于与 index.js 相同的目录执行（通常 /www/wwwroot/safemaster-api）
# 用法：chmod +x verify-remote-env.sh && ./verify-remote-env.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "======== 路径 ========="
echo "PWD=$PWD"
echo "index.js: $([ -f index.js ] && echo OK || echo MISSING)"
echo "hazardPrompts.js: $([ -f hazardPrompts.js ] && echo OK || echo MISSING)"
echo "config.json: $([ -f config.json ] && echo OK || echo MISSING)"

echo ""
echo "======== Node ========="
command -v node >/dev/null && node -v || echo "node: NOT FOUND"

echo ""
echo "======== config.json JSON ========="
if [[ -f config.json ]]; then
  node -e "JSON.parse(require('fs').readFileSync('config.json','utf8')); console.log('JSON OK')" 2>&1 || echo "JSON PARSE FAIL"
else
  echo "no config.json"
fi

echo ""
echo "======== mysql2 模块 ========="
node -e "require('mysql2/promise'); console.log('mysql2 OK')" 2>&1 || echo "mysql2 require FAIL"

echo ""
echo "======== 用 config 试连 MySQL（仅 SELECT 1）========"
node -e "
const fs=require('fs'); const mysql=require('mysql2/promise');
(async()=>{
  if(!fs.existsSync('config.json')){ console.log('skip: no config'); return; }
  const c=JSON.parse(fs.readFileSync('config.json','utf8'));
  if(!c.dbUser||!c.dbName){ console.log('skip: no dbUser/dbName'); return; }
  const pool=mysql.createPool({
    host:c.dbHost||'127.0.0.1',
    user:c.dbUser,
    password:c.dbPassword,
    database:c.dbName,
    waitForConnections:true,
    connectionLimit:1
  });
  await pool.query('SELECT 1 AS ok');
  console.log('MySQL ping: OK');
  await pool.end();
})().catch(e=>console.error('MySQL ping:', e.message));
" 2>&1

echo ""
echo "======== PM2 ========="
command -v pm2 >/dev/null && pm2 list 2>&1 | head -20 || echo "pm2: NOT FOUND"

echo ""
echo "======== 本机 HTTP ========="
PORT="${PORT:-3000}"
if curl -sS -m 3 "http://127.0.0.1:${PORT}/health" 2>/dev/null; then
  echo ""
  echo "health: OK (port ${PORT})"
else
  echo "health: FAIL or not listening on ${PORT} (可 export PORT=实际端口 再运行)"
fi

echo ""
echo "======== POST /v1/hazard/analyze（无 Token，期望 401 JSON）========"
curl -sS -m 15 -w "\nHTTP:%{http_code}\n" -X POST "http://127.0.0.1:${PORT}/v1/hazard/analyze" \
  -H "Content-Type: application/json" \
  -d '{}' || true

echo ""
echo "======== 完成 ========="
