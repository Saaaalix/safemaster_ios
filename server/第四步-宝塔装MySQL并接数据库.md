# 第四步：宝塔装 MySQL，把「次数」存进数据库

做完第三步后，你的接口已经能跑。这一步让 **`/v1/auth/apple` 真正往数据库里写用户**，**`/v1/me` 按账号返回剩余次数**（不再全是演示固定值）。

---

## 一、在宝塔里安装并启动 MySQL

1. 打开宝塔面板 → **软件商店**。
2. 搜索 **MySQL**（建议 **8.0** 或 **5.7**，任选其一）。
3. 点 **安装**，等安装完成。
4. 左侧 **数据库**，确认能打开 **phpMyAdmin**（或「数据库」列表里有 MySQL 服务在运行）。

**成功标志：** 软件商店里 MySQL 显示「运行中」，且「数据库」页面能打开。

---

## 二、新建数据库和用户（记下账号密码）

1. 宝塔 → **数据库** → **添加数据库**。
2. **数据库名**填：`safemaster`（可自定，但要和后面 `config.json` 里一致）。
3. **用户名**：可用宝塔自动生成，或自己起一个（例如 `safemaster`）。
4. **密码**：**自己设一个并复制保存**（后面要写进 `config.json`）。
5. **访问权限**选 **本地服务器**（默认即可）。
6. 点 **提交**。

**成功标志：** 数据库列表里出现 `safemaster`，你能看到用户名。

---

## 三、导入表结构（建 `users` 表）

下面两种方法任选其一。**若 phpMyAdmin 一打开就报错、重装也没用，请直接用「方法 B：终端」，最稳。**

---

### 方法 A：phpMyAdmin（注意：不要用「数据库 → 管理」）

宝塔里点 **`safemaster` 那一行的「管理」`**，常常会**自动用 `safemaster` 账号登录** phpMyAdmin，页面一加载就报错（`SELECT command denied ... user 'safemaster'`），**这和 phpMyAdmin 是否重装无关**。

请按下面做：

1. **不要用** 数据库列表里 **`safemaster` → 管理** 这个入口（或用过以后先清掉本站 Cookie / 换 **无痕窗口** 再试）。
2. 改用其一进入 phpMyAdmin：
   - 宝塔 → **软件商店** → 已安装里找到 **phpMyAdmin** → 点 **设置** 或 **打开**（若有）；或  
   - 浏览器 **无痕模式** 新开标签，地址栏手动输入：`http://你的服务器IP:8888/phpmyadmin/`（端口以你宝塔为准，常见 8888）。
3. 出现登录框时：**用户名填 `root`**，密码填宝塔 **数据库** 页里的 **root 密码**（不是 `safemaster` 的密码）。
4. 登录成功后，左侧选中数据库 **`safemaster`** → 顶部 **SQL** → 粘贴 **`schema.sql`** 全文 → **执行**。

**成功标志：** 左侧出现表 **`users`**。

---

### 方法 B：宝塔终端用 root 执行 SQL（推荐，不依赖 phpMyAdmin）

1. 先把 **`schema.sql`** 上传到服务器，例如放到：`/www/wwwroot/safemaster-api/schema.sql`（与 `index.js` 同目录即可）。
2. 宝塔 → **终端**，执行（会提示输入密码，**输入 root 密码时屏幕不显示字符，属正常**）：

```bash
mysql -u root -p safemaster < /www/wwwroot/safemaster-api/schema.sql
```

3. 若没有报错，即表示已导入。可再执行下面命令确认有 `users` 表：

```bash
mysql -u root -p -e "USE safemaster; SHOW TABLES;"
```

**成功标志：** 输出里能看到 **`users`**。

---

> **程序连库仍然用 `safemaster`：** `config.json` 里继续填业务库账号；**只有** 在「建表 / 管理整库」时用 **root**（phpMyAdmin 或 `mysql -u root`）。

---

## 四、在服务器上放 `config.json`（不要泄露）

1. 在宝塔 **文件**，进入目录：`/www/wwwroot/safemaster-api`。
2. 参考本目录下的 **`config.example.json`**，新建一个文件 **`config.json`**（和 `index.js` 同级）。
3. 把内容改成你的真实信息，例如：

```json
{
  "dbHost": "127.0.0.1",
  "dbUser": "你在宝塔创建的数据库用户名",
  "dbPassword": "你的数据库密码",
  "dbName": "safemaster"
}
```

4. **保存**。

**注意：** `config.json` 里是密码，不要发到网上、不要提交到公开的 Git 仓库。

---

## 五、上传新代码并安装依赖

1. 用宝塔 **文件** 或 **FTP**，把本机 **`server/index.js`**、**`server/package.json`** 覆盖上传到 `safemaster-api` 目录（覆盖原来的同名文件）。
2. 打开宝塔 **终端**（或 SSH），执行：

```bash
cd /www/wwwroot/safemaster-api
npm install
pm2 restart safemaster-api
```

**成功标志：** `pm2` 里 `safemaster-api` 状态为 **online**，且无红色报错。

---

## 六、验证是否接上数据库

### 1）健康检查（看数据库是否连通）

浏览器打开（把 IP 换成你的）：

`http://111.229.218.215:3000/health`

应看到 JSON 里类似：

- `"dbMode": "mysql"`
- `"dbConnected": true`

若 `dbConnected` 为 `false`：检查 `config.json` 账号密码、数据库名、MySQL 是否运行、`schema.sql` 是否已执行。

### 2）登录拿 token（一行 curl，避免 `>` 续行问题）

在服务器终端执行（整行复制）：

```bash
curl -s -X POST http://127.0.0.1:3000/v1/auth/apple -H "Content-Type: application/json" -d '{"identityToken":"test-from-server-001"}'
```

应返回 **`accessToken`** 和 **`credits`**（新用户一般为 **5**）。

### 3）用 token 查 `/v1/me`

把上一步返回里的 **`accessToken`** 复制出来，执行（把 `你的TOKEN` 换成真实值，仍是一行）：

```bash
curl -s http://127.0.0.1:3000/v1/me -H "Authorization: Bearer 你的TOKEN"
```

应返回 **`credits`**，且与上一步一致。

### 4）在 phpMyAdmin 里看数据

打开 **`users` 表**，应能看到新一行，`apple_sub` 是一串很长的十六进制，`credits` 为 **5**。

---

## 七、常见问题

**Q：打开 phpMyAdmin 就报错 `SELECT command denied ... user 'safemaster'`，重装 phpMyAdmin 也一样？**  
A：**不是坏了，是登录身份错了。** 点 **数据库 → `safemaster` → 管理** 时，宝塔经常用 **`safemaster` 自动登录**，一打开就炸。请换 **无痕窗口** 手动打开 phpMyAdmin 地址，用 **`root` + root 密码** 登录；或直接按上面 **「三、方法 B」** 用终端 `mysql -u root -p` 导入，不经过 phpMyAdmin。

**Q：打开 phpMyAdmin 登录后，出现 `SELECT command denied ... for table 'user'` 之类 Fatal error？**  
A：你是用 **`safemaster` 等业务账号** 登录的。请 **退出**，改用 **用户名 `root`** + 宝塔 **数据库** 页里的 **root 密码** 再登录。业务程序仍用 `safemaster` 账号（写在 `config.json`），两者不冲突。

**Q：终端里输入 curl 后出现很多 `>`，像卡住一样？**  
A：多半是命令没写完（少了引号、反斜杠续行没结束）。请用上面 **一整行** 的 curl，或先在记事本里写好再粘贴。

**Q：`/health` 里 `dbMode` 还是 demo？**  
A：说明 **`config.json` 没放到 `index.js` 旁边**，或文件名不对。确认路径是 `/www/wwwroot/safemaster-api/config.json`。

**Q：提示数据库写入失败？**  
A：检查 **`users` 表是否建好**、`dbUser` 对该库是否有权限、密码是否复制错（多空格等）。

---

## 八、这一步完成后你可以期待什么

- 每个不同的 `identityToken` 会对应 **`users` 表里一行**，首次登录 **`credits` 为 5**。
- App 里以后可以：**Sign in with Apple → 把 `identityToken` 发给 `/v1/auth/apple` → 存 `accessToken` → 调 `/v1/me` 看剩余次数**。

下一步（第五步预告）：在接口里增加 **「分析一次扣 1 次」**、或接 **苹果收据 / 服务端校验**，再与 iOS 联调。需要时继续做傻瓜文档即可。
