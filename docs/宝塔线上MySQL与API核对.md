# 宝塔线上：MySQL + API 核对清单（傻瓜步骤）

目标：消除 App 里 **`数据库写入失败: Access denied for user 'safemaster'@'localhost'`**，让 **`POST /v1/auth/apple`** 能写入 `users` 表。

以下在 **宝塔 → 终端**（或 SSH）里操作，全程 **root** 或能执行 `mysql` 的账号。

---

## 第一步：确认 `config.json` 在哪、Node 读的是不是它

```bash
cd /www/wwwroot/safemaster-api
cat config.json
```

核对：

- **`dbHost`**：建议先用 **`127.0.0.1`**（与 Node 走 TCP，少踩 `localhost` 套接字问题）。
- **`dbPassword`**：必须和下面 MySQL 里 **`safemaster` 用户**的密码**完全一致**（复制粘贴，无多余空格）。

改完后：

```bash
pm2 restart safemaster-api
```

---

## 第二步：用 root 进 MySQL，看账号是否齐全

```bash
mysql -u root -p
```

执行（把结果记下来或截图）：

```sql
SELECT user, host FROM mysql.user WHERE user = 'safemaster';
```

至少应存在 **`safemaster`@`localhost`** 或 **`safemaster`@`127.0.0.1`**（或两者都有）。  
若只有其中一个，而 `config.json` 里是另一个 host，就会 **Access denied**。

---

## 第三步：看权限是否包含「写库」

仍在 MySQL 里，对每个存在的 host 执行（把 `'localhost'` 换成你上一步看到的 host）：

```sql
SHOW GRANTS FOR 'safemaster'@'localhost';
```

应看到对 **`safemaster`.* 的权限，且含 INSERT、UPDATE**（或 `ALL PRIVILEGES`）。

若没有，用 **root** 执行（**密码换成与 `config.json` 里一致**）：

```sql
GRANT ALL PRIVILEGES ON safemaster.* TO 'safemaster'@'localhost' IDENTIFIED BY '与config.json一致';
-- 若存在 127.0.0.1 用户，再执行一条（MySQL 5.7 语法）：
GRANT ALL PRIVILEGES ON safemaster.* TO 'safemaster'@'127.0.0.1' IDENTIFIED BY '与config.json一致';
FLUSH PRIVILEGES;
```

> MySQL 8 的 `CREATE USER` / `ALTER USER` 语法不同；你线上是 **5.7** 时上面这种一般可用。若报错，把**完整英文错误**贴出来。

---

## 第四步：用「业务账号」本机测登录 + 写表

**退出 MySQL**，在 shell 里（密码用 `config.json` 里的 `dbPassword`）：

```bash
mysql -u safemaster -p -h 127.0.0.1 safemaster
```

进去后执行：

```sql
INSERT INTO users (apple_sub, credits) VALUES ('_write_test_', 5)
  ON DUPLICATE KEY UPDATE credits = credits;
SELECT apple_sub FROM users WHERE apple_sub = '_write_test_';
```

- **若这里就报错**：问题在 **MySQL 用户/权限/密码**，先别怪 Node。  
- **若成功**：再执行第五步。

测试行可删（可选）：

```sql
DELETE FROM users WHERE apple_sub = '_write_test_';
```

---

## 第五步：在同一目录用 Node 测（与 PM2 同一套 `config.json`）

```bash
cd /www/wwwroot/safemaster-api
node -e "
const fs=require('fs');const m=require('mysql2/promise');
(async()=>{
  const c=JSON.parse(fs.readFileSync('config.json','utf8'));
  const port=Number(c.dbPort); const pool=m.createPool({
    host:c.dbHost||'127.0.0.1',
    port:(Number.isFinite(port)&&port>0)?port:3306,
    user:c.dbUser,password:c.dbPassword,database:c.dbName
  });
  await pool.execute(\"INSERT INTO users (apple_sub,credits) VALUES ('_node_test_',5) ON DUPLICATE KEY UPDATE apple_sub=apple_sub\");
  console.log('NODE_WRITE_OK');
  await pool.end();
})().catch(e=>console.error('NODE_FAIL',e.message));
"
```

看到 **`NODE_WRITE_OK`** 即与 App 同路径的写入已通。

---

## 第六步：测 HTTP 接口

```bash
curl -sS -X POST http://127.0.0.1:3000/v1/auth/apple \
  -H "Content-Type: application/json" \
  -d '{"identityToken":"curl-smoke-test"}'
```

应返回 **`ok":true`** 和 **`accessToken`**（或至少不是 **500 + 数据库写入失败**）。

---

## 第七步：再打开 App

「我的」里 **重新同步 / 重新登录** 一次。若仍报错，把 **`pm2 logs safemaster-api --err --lines 30`** 整段贴给开发者（可打码）。

---

## 常见对应关系

| 现象 | 优先查 |
|------|--------|
| `Access denied` | 密码不一致、`localhost` vs `127.0.0.1` 账号不匹配 |
| `数据库查询失败`（仅读） | 同上 + SELECT 权限 |
| `数据库写入失败` | INSERT/UPDATE 权限、`users` 表是否存在 |

---

把 **`docs/SERVER_ENV.md`** 里线上路径、PM2 名也顺手填好，以后少口述一遍。
