# 本机用 Docker 跑 MySQL（推荐给「先本地跑通」）

## 为什么用 Docker？

| 点 | 说明 |
|----|------|
| 版本可对齐线上 | 本仓库使用 **MySQL 5.7** 镜像，接近宝塔上常见的 5.7.x。 |
| 可重复 | `docker compose up -d` 随时拉起同一环境；换电脑也能照做。 |
| 好维护 | 数据在 Docker 卷里；要「清空重来」可删卷再起（开发阶段）。 |
| 和后期部署的关系 | 线上仍是「真实 MySQL + Node」；本地只是用容器代替本机安装 MySQL，**表结构仍用仓库里的 `server/schema.sql`**，上线导出/导入即可。 |

不怕麻烦、希望数据库规范，**Docker 是加分项**；若你坚持不装 Docker，也可以用 Homebrew 装 MySQL，但版本、行为要和线上自己对照。

---

## 前置条件

- 已安装 **Docker Desktop**（Mac）：<https://www.docker.com/products/docker-desktop/>  
- 安装后菜单栏有鲸鱼图标，终端执行 `docker version` 有输出即可。

---

## 步骤（均在 Mac 终端操作）

### 1）进入 server 目录

```bash
cd /你的路径/安全大师/server
```

### 2）准备环境变量文件

```bash
cp .env.example .env
```

（可按需改 `.env` 里的密码；**不要**把 `.env` 发给他人或提交 Git。）

### 3）启动数据库

```bash
docker compose up -d
```

### 4）导入表结构

```bash
docker exec -i safemaster-mysql-local mysql -usafemaster -p"safemaster_dev" safemaster < schema.sql
```

若你改了 `.env` 里的 `MYSQL_PASSWORD`，把上面命令里的密码改成一致。

### 5）配置 Node 使用的 `config.json`

在 **`server` 目录**放一份 `config.json`（若没有），内容与线上一致字段，本机示例：

```json
{
  "dbHost": "127.0.0.1",
  "dbPort": 3306,
  "dbUser": "safemaster",
  "dbPassword": "safemaster_dev",
  "dbName": "safemaster",
  "deepseekApiKey": "你的DeepSeek密钥或先留空仅测数据库"
}
```

`dbPassword` 必须与 `.env` 里 `MYSQL_PASSWORD` 一致。  
若本机 **3306 已被别的 MySQL 占用**，可改 Docker 映射与本配置中的 **`dbPort`**（需与 `docker-compose.yml` 里端口映射一致）。

### `/health` 里 `dbConnected` 仍是 false？

1. 先 **保存 `config.json` 后重启** `node index.js`。  
2. 终端里会打印 **`[health] DB ping 失败：...`**，把这句完整错误发出来即可定位。  
3. 确认容器在跑：`docker ps | grep safemaster-mysql-local`，且端口为 **`0.0.0.0:3306->3306`**（或你改过的端口）。

### 6）安装依赖并启动 API

```bash
npm install
node index.js
```

另开终端测：`curl -s http://127.0.0.1:3000/health`

---

## 常用命令

```bash
docker compose logs -f mysql    # 看数据库日志
docker compose stop               # 停止
docker compose down             # 停止并删容器（卷里数据默认保留）
```

---

## Apple Silicon 说明

`mysql:5.7` 在 M 系列 Mac 上通过 **amd64 模拟**运行，第一次拉镜像会慢一点，属正常现象。
