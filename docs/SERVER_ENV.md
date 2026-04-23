# 安全大师 · 生产环境快照（给 Cursor / 自己看）

> **用途**：AI 无法登录你的宝塔。把「真实环境」写进仓库后，对话里就不用反复口述同一套路径。  
> **注意**：不要在此文件写入 **数据库密码、API Key、域名证书私钥**。密码类只写「已配置在 config.json / 环境变量」即可。

---

## 1. 服务器概览

| 项 | 填写 |
|----|------|
| 云厂商 / 系统 | 例：OpenCloudOS，宝塔 BT-Panel |
| 公网 IP / 域名 | 例：`http://x.x.x.x:3000` 或 `https://api.example.com` |
| SSH | 是否仅用宝塔终端（是/否） |

---

## 2. 软件版本（在宝塔终端 `node -v`、`mysql --version` 可查）

| 软件 | 版本 |
|------|------|
| Node.js |  |
| PM2 |  |
| MySQL |  |
| Nginx（若已反代） |  |

---

## 3. 自建 API（safemaster-api）— 最关键

| 项 | 填写 |
|----|------|
| **项目根目录（服务器绝对路径）** | 例：`/www/wwwroot/safemaster-api` |
| **入口文件** | `index.js`（与 `hazardPrompts.js`、`package.json` 同级） |
| **PM2 进程名** | 例：`safemaster-api` |
| **监听端口** | 默认 `3000`；若改过写实际端口 |
| **对外访问方式** | 直连端口 / Nginx 反代 HTTPS |
| **config.json 位置** | 与 `index.js` 同目录；`dbHost` 当前用 `localhost` 还是 `127.0.0.1` |

---

## 4. MySQL

| 项 | 填写 |
|----|------|
| 业务库名 | 例：`safemaster` |
| 业务用户 | 例：`safemaster` |
| 权限说明 | 例：已对 `safemaster.*` 授权 ALL（勿写密码） |

---

## 5. iOS App 指向的 API 根地址

| 项 | 填写 |
|----|------|
| `SafeMasterAPIConfiguration.baseURL`（Xcode 里） | 例：`http://IP:3000` 或 `https://域名` |

---

## 6. 排错时一键自检（在服务器执行）

在 **`/www/wwwroot/safemaster-api`**（改成你的路径）下：

```bash
chmod +x verify-remote-env.sh
./verify-remote-env.sh
```

把**完整终端输出**贴给 Cursor，比只说「报错了」有效得多。

---

## 7. 常见坑（我们踩过的）

1. **`index.js` 已更新但宝塔上仍是旧文件** → App 出现 `Cannot POST /v1/hazard/analyze`（404）。  
2. **`config.json` 非法 JSON** → 服务进 demo、或读不到 DB；用 `node -e "JSON.parse(fs.readFileSync('config.json'))"` 校验。  
3. **`loadDb()` 只建连接池、启动时不验密码** → 日志显示 mysql，真机首请求才 `Access denied`。  
4. **`'user'@'localhost'` 与 `'user'@'127.0.0.1'`** 在 MySQL 里是不同账号；`dbHost` 与授权要一致或两条都授权。  
5. **PM2 的 error.log 会保留历史** → 旧报错不代表当前失败；可 `pm2 flush` 后重启再看。

---

## 8. 变更记录

| 日期 | 变更 |
|------|------|
|  | 例：dbHost 改为 localhost |

---

填写说明：随部署变更**及时改两行**，比每次聊天重讲一遍省精力。
