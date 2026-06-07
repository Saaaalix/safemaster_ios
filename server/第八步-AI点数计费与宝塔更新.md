# 第八步：AI 点数计费与宝塔更新

本次把“每日 20 次分析”升级为“每日 AI 点数额度”：

- App 端仍读取 `credits` / `dailyRemaining`，但含义改为“剩余 AI 点数”。
- 服务端统一代理 AI 调用，成功后读取模型返回的 `usage.total_tokens`。
- 默认 `1000 tokens = 1 点`，可在 `config.json` 里用 `aiUnitTokens` 调整。
- 默认月会员每日 `200 点`，可在 `config.json` 里用 `planDailyAIUnitLimit` 调整。
- 模型失败、文档解析失败、回退原文时不扣 AI 点数。

---

## 一、宝塔上需要改什么

需要改三类内容：

1. 上传新版服务端文件：
   - `server/index.js`
   - `server/rateLimiters.js`（如本地有更新）
   - `server/schema.sql`
   - 其它本次新增或修改的服务端文件

2. 更新数据库字段：
   - `users.daily_ai_unit_limit`
   - `users.daily_ai_unit_used`
   - 新表 `ai_usage_logs`

3. 更新 `config.json`：
   - 增加 `planDailyAIUnitLimit`
   - 增加 `aiUnitTokens`

服务端启动后会自动补字段和新表；但生产环境建议你也在宝塔 phpMyAdmin 手动执行下面 SQL，方便确认。

---

## 二、phpMyAdmin 执行 SQL

宝塔 → 数据库 → phpMyAdmin → 选择 `safemaster` 数据库 → SQL，执行：

```sql
ALTER TABLE users ADD COLUMN daily_ai_unit_limit INT NOT NULL DEFAULT 200 COMMENT '每日 AI 点数额度';
ALTER TABLE users ADD COLUMN daily_ai_unit_used INT NOT NULL DEFAULT 0 COMMENT '当日已用 AI 点数';

CREATE TABLE IF NOT EXISTS ai_usage_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  apple_sub VARCHAR(64) NOT NULL COMMENT '关联 users.apple_sub',
  feature VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'AI 功能点',
  model VARCHAR(64) NOT NULL DEFAULT '' COMMENT '模型名称',
  prompt_tokens INT NOT NULL DEFAULT 0 COMMENT '输入 token',
  completion_tokens INT NOT NULL DEFAULT 0 COMMENT '输出 token',
  total_tokens INT NOT NULL DEFAULT 0 COMMENT '总 token',
  units_charged INT NOT NULL DEFAULT 0 COMMENT '本次折算扣减 AI 点数',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ai_usage_apple_sub_created (apple_sub, created_at),
  KEY idx_ai_usage_feature_created (feature, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

如果提示字段已存在，忽略即可，继续执行后面的 SQL。

---

## 三、修改宝塔上的 config.json

文件一般在：

```bash
/www/wwwroot/safemaster-api/server/config.json
```

增加或确认这两项：

```json
{
  "planDailyAIUnitLimit": 200,
  "aiUnitTokens": 1000
}
```

含义：

- `planDailyAIUnitLimit: 200`：月会员每天 200 点 AI 额度。
- `aiUnitTokens: 1000`：模型总 token 每满 1000 折算 1 点，不足 1000 也按 1 点。

如果你发现用户消耗太快，可以把 `planDailyAIUnitLimit` 调大，比如 300 或 500。  
如果你想让扣费更细，可以把 `aiUnitTokens` 调小；想让用户更宽松，就调大。

---

## 四、重启 PM2

宝塔 → 终端：

```bash
cd /www/wwwroot/safemaster-api/server
pm2 restart safemaster-api
pm2 logs safemaster-api --lines 50
```

如果你的 PM2 进程是在 `/www/wwwroot/safemaster-api` 启动的，就进入对应目录重启。重点是重启同一个 `safemaster-api` 进程。

---

## 五、验证是否成功

### 1. 登录拿 token

```bash
curl -sS -X POST http://127.0.0.1:3000/v1/auth/apple \
  -H "Content-Type: application/json" \
  -d '{"identityToken":"curl-ai-unit-test"}'
```

返回里应看到：

- `credits`
- `subscription.dailyLimit`
- `subscription.dailyRemaining`

这几个数字现在表示 AI 点数。

### 2. 调一次隐患分析

把上一步返回的 `accessToken` 填进去：

```bash
curl -sS -X POST http://127.0.0.1:3000/v1/hazard/analyze \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer 这里填accessToken" \
  -d '{"hasPhoto":false,"location":"3号楼外架","supplementaryText":"作业人员未佩戴安全帽","visionBlock":"","industryDomain":"construction"}'
```

成功返回里应看到：

- `credits`：扣减后的剩余 AI 点数
- `usage.totalTokens`
- `usage.unitsCharged`
- `analysis`

### 3. 查看用量日志

phpMyAdmin 执行：

```sql
SELECT feature, model, total_tokens, units_charged, created_at
FROM ai_usage_logs
ORDER BY id DESC
LIMIT 20;
```

能看到 `hazard_analyze` 或 `import_extract_text_clean` 记录，就说明模型用量计费已经生效。

---

## 六、是否需要更改宝塔上的模型

不一定。

如果你还是用 DeepSeek，模型名目前仍是服务端代码里的 `deepseek-chat`，只要宝塔环境变量 `DEEPSEEK_API_KEY` 或 `config.json.deepseekApiKey` 正常，就不用换模型。

如果你以后想换模型，需要改两处：

1. `server/index.js` 里请求 DeepSeek 的 `model: "deepseek-chat"`。
2. 结合新模型的返回结构确认是否仍有 `usage.prompt_tokens / completion_tokens / total_tokens`。

只要返回里有 usage，这套 AI 点数计费就能继续工作。

---

## 七、上线后建议观察

上线前 1-2 天建议每天看一次：

```sql
SELECT
  feature,
  COUNT(*) AS calls,
  SUM(total_tokens) AS total_tokens,
  SUM(units_charged) AS units
FROM ai_usage_logs
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
GROUP BY feature
ORDER BY units DESC;
```

这样你能知道是隐患分析、导入清洗，还是后续新增 AI 功能消耗最多，再决定套餐额度是否要调。
