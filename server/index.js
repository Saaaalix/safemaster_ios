/**
 * 安全大师 · 服务端
 * - 无 config.json：演示模式（/v1/me 返回固定次数）
 * - 有 config.json 且数据库可用：真实读写 users 表
 * - DeepSeek：环境变量 DEEPSEEK_API_KEY 或 config.json 的 deepseekApiKey（仅服务器持有）
 */
const express = require("express");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { buildSystemPrompt, buildUserPrompt } = require("./hazardPrompts");

const app = express();
const port = Number(process.env.PORT) || 3000;

app.use(express.json({ limit: "3mb" }));

let pool = null;
let dbMode = "demo";
/** 无数据库时，按 accessToken 记在内存里演示扣次（进程重启会清空） */
const demoCreditsByToken = new Map();

/** 启动时读取 config.json（数据库 + 可选 deepseekApiKey） */
let fileConfig = {};
try {
  const cfgPath = path.join(__dirname, "config.json");
  if (fs.existsSync(cfgPath)) {
    fileConfig = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
  }
} catch (e) {
  console.warn("[config] 读取 config.json 失败：", e.message);
}

function getDeepseekKey() {
  const env = process.env.DEEPSEEK_API_KEY;
  if (env && String(env).trim()) return String(env).trim();
  const k = fileConfig.deepseekApiKey;
  if (k && String(k).trim()) return String(k).trim();
  return "";
}

function loadDb() {
  if (!fileConfig.dbUser || !fileConfig.dbName) {
    console.warn("[DB] 未找到数据库配置（dbUser/dbName），使用演示模式");
    return;
  }
  try {
    const mysql = require("mysql2/promise");
    const dbPort = Number(fileConfig.dbPort);
    /** Linux 上 host=localhost 会走 Unix 套接字，对应 @localhost，易与 @127.0.0.1 密码不一致；统一走 TCP。 */
    let dbHost = (fileConfig.dbHost && String(fileConfig.dbHost).trim()) || "127.0.0.1";
    if (dbHost === "localhost") dbHost = "127.0.0.1";
    console.log("[DB] MySQL 连接使用 host=", dbHost);
    pool = mysql.createPool({
      host: dbHost,
      port: Number.isFinite(dbPort) && dbPort > 0 ? dbPort : 3306,
      user: fileConfig.dbUser,
      password: fileConfig.dbPassword,
      database: fileConfig.dbName,
      waitForConnections: true,
      connectionLimit: 5,
    });
    dbMode = "mysql";
    console.log("[DB] 已连接配置：", fileConfig.dbName);
  } catch (e) {
    console.warn("[DB] 加载失败，演示模式：", e.message);
  }
}

/**
 * 扣次：供 /v1/credits/consume 与 /v1/hazard/analyze 共用
 * @returns {Promise<{ok:boolean,credits?:number,statusCode?:number,errorMessage?:string}>}
 */
async function consumeCreditsInternal(sub, amount) {
  if (!sub) {
    return { ok: false, statusCode: 401, errorMessage: "需要 Bearer accessToken" };
  }
  let amt = Number(amount);
  if (!Number.isFinite(amt) || amt < 1) amt = 1;
  amt = Math.min(10, Math.floor(amt));

  if (!pool) {
    if (!demoCreditsByToken.has(sub)) demoCreditsByToken.set(sub, 5);
    const cur = demoCreditsByToken.get(sub);
    if (cur < amt) {
      return { ok: false, statusCode: 402, credits: cur, errorMessage: "次数不足" };
    }
    const next = cur - amt;
    demoCreditsByToken.set(sub, next);
    return { ok: true, credits: next };
  }

  try {
    let row = await loadUserRow(sub);
    if (!row) {
      return { ok: false, statusCode: 404, credits: 0, errorMessage: "用户不存在，请先登录" };
    }
    row = await resetDailyQuotaIfNeeded(sub, row);

    if (!isPlanActive(row)) {
      return {
        ok: false,
        statusCode: 402,
        credits: remainingDailyQuota(row),
        errorMessage: "会员已过期或未开通，请先订阅（月费48元）",
      };
    }
    const left = remainingDailyQuota(row);
    if (left < amt) {
      return {
        ok: false,
        statusCode: 402,
        credits: left,
        errorMessage: "今日分析次数已用完（每日20次）",
      };
    }
    const [result] = await pool.execute(
      "UPDATE users SET daily_used = daily_used + ? WHERE apple_sub = ? AND daily_used + ? <= daily_limit",
      [amt, sub, amt]
    );
    if (result.affectedRows === 0) {
      row = await loadUserRow(sub);
      return {
        ok: false,
        statusCode: 402,
        credits: remainingDailyQuota(row),
        errorMessage: "今日分析次数已用完（每日20次）",
      };
    }
    row = await loadUserRow(sub);
    row = await resetDailyQuotaIfNeeded(sub, row);
    return { ok: true, credits: remainingDailyQuota(row) };
  } catch (e) {
    console.error(e);
    return { ok: false, statusCode: 500, errorMessage: "扣次失败：" + e.message };
  }
}

function stripMarkdownJSONFence(s) {
  let t = String(s).trim();
  if (t.startsWith("```json")) t = t.slice(7);
  else if (t.startsWith("```")) t = t.slice(3);
  t = t.trim();
  if (t.endsWith("```")) t = t.slice(0, -3).trim();
  return t;
}

function pickField(a, b) {
  const t = a != null && String(a).trim() ? String(a).trim() : "";
  if (t) return t;
  return b != null && String(b).trim() ? String(b).trim() : "";
}

function normalizeAnalysis(obj) {
  const hazard = pickField(obj.hazard_description, obj.hazardDescription);
  let measures = pickField(obj.rectification_measures, obj.rectificationMeasures);
  if (!measures && hazard) {
    measures =
      "（本次模型未返回整改措施正文。请结合上方隐患描述与整改依据现场落实，或点击「重新分析（需联网）」重试。）\n" +
      "1. 对照隐患描述逐项消除：如移除影响散热/检修的遮盖物，规范电缆与箱体布置。\n" +
      "2. 对间距、防护等级等需实测项，现场测定后采取隔离、警戒或移位等措施直至符合规范。\n" +
      "3. 完成整改后复查并留存记录。";
  }
  const risk = pickField(obj.risk_level, obj.riskLevel) || "一般风险";
  return {
    hazard_description: hazard,
    rectification_measures: measures,
    risk_level: risk,
    accident_category_major: pickField(obj.accident_category_major, obj.accidentCategoryMajor),
    accident_category_minor: pickField(obj.accident_category_minor, obj.accidentCategoryMinor),
    legal_basis: pickField(obj.legal_basis, obj.legalBasis),
  };
}

const MAX_ANALYZE = {
  location: 500,
  supplementary: 4000,
  vision: 12000,
  playbook: 20000,
  law: 25000,
};

const PLAN = {
  monthlyPriceCNY: Number(fileConfig.planMonthlyPriceCNY) > 0 ? Number(fileConfig.planMonthlyPriceCNY) : 48,
  dailyLimit: Number(fileConfig.planDailyLimit) > 0 ? Number(fileConfig.planDailyLimit) : 20,
  trialDays: 30,
};

function isMockRenewEnabled() {
  const raw = process.env.ALLOW_MOCK_RENEW ?? fileConfig.allowMockRenew;
  if (raw !== undefined && raw !== null && String(raw).trim() !== "") {
    const v = String(raw).trim().toLowerCase();
    return v === "1" || v === "true" || v === "yes" || v === "on";
  }
  return process.env.NODE_ENV !== "production";
}

function cnDateKey(d = new Date()) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return fmt.format(d);
}

function isPlanActive(row) {
  if (!row) return false;
  if (row.plan_status !== "active") return false;
  if (!row.plan_expires_at) return false;
  const expires = new Date(row.plan_expires_at);
  return Number.isFinite(expires.getTime()) && expires.getTime() > Date.now();
}

function remainingDailyQuota(row) {
  const limit = Number(row?.daily_limit ?? PLAN.dailyLimit);
  const used = Number(row?.daily_used ?? 0);
  return Math.max(0, limit - used);
}

async function loadUserRow(sub) {
  const [rows] = await pool.execute(
    "SELECT apple_sub, credits, plan_status, plan_expires_at, daily_limit, daily_used, daily_quota_date, report_unlimited FROM users WHERE apple_sub = ? LIMIT 1",
    [sub]
  );
  return rows[0] || null;
}

async function resetDailyQuotaIfNeeded(sub, row) {
  const today = cnDateKey();
  if ((row.daily_quota_date || "") === today) {
    return row;
  }
  await pool.execute(
    "UPDATE users SET daily_used = 0, daily_quota_date = ? WHERE apple_sub = ?",
    [today, sub]
  );
  row.daily_used = 0;
  row.daily_quota_date = today;
  return row;
}

function buildSubscriptionPayload(row) {
  return {
    active: isPlanActive(row),
    status: row.plan_status || "inactive",
    expiresAt: row.plan_expires_at
      ? new Date(row.plan_expires_at).toISOString()
      : null,
    dailyLimit: Number(row.daily_limit ?? PLAN.dailyLimit),
    dailyUsed: Number(row.daily_used ?? 0),
    dailyRemaining: remainingDailyQuota(row),
    dailyQuotaDate: row.daily_quota_date || "",
    reportUnlimited: Boolean(row.report_unlimited),
    monthlyPriceCNY: PLAN.monthlyPriceCNY,
  };
}

function clampStr(s, max) {
  const t = typeof s === "string" ? s : "";
  if (t.length <= max) return t;
  return t.slice(0, max) + "\n…（已截断）";
}

function appleSubFromToken(identityToken) {
  return crypto.createHash("sha256").update(String(identityToken)).digest("hex");
}

function bearerToken(req) {
  const auth = req.headers.authorization || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}

function decodeBase64UrlJSON(s) {
  const t = String(s || "").trim();
  if (!t) return null;
  const b64 = t.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
  const raw = Buffer.from(b64 + pad, "base64").toString("utf8");
  return JSON.parse(raw);
}

function decodeJWTPayloadWithoutVerify(jwt) {
  const parts = String(jwt || "").split(".");
  if (parts.length < 2) return null;
  return decodeBase64UrlJSON(parts[1]);
}

async function ensureIapTransactionsTable() {
  if (!pool) return;
  await pool.execute(`
    CREATE TABLE IF NOT EXISTS iap_transactions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      apple_sub VARCHAR(64) NOT NULL,
      product_id VARCHAR(128) NOT NULL,
      transaction_id VARCHAR(64) NOT NULL,
      original_transaction_id VARCHAR(64) NOT NULL,
      expires_at DATETIME NOT NULL,
      environment VARCHAR(32) NOT NULL DEFAULT '',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uk_tx_transaction_id (transaction_id),
      KEY idx_tx_original_transaction_id (original_transaction_id),
      KEY idx_tx_apple_sub (apple_sub)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

loadDb();

app.get("/health", async (req, res) => {
  let dbOk = false;
  if (pool) {
    try {
      await pool.query("SELECT 1");
      dbOk = true;
    } catch (e) {
      dbOk = false;
      console.error("[health] DB ping 失败：", e.message);
    }
  }
  res.json({
    ok: true,
    message: "SafeMaster API 运行中",
    time: new Date().toISOString(),
    dbMode,
    dbConnected: dbOk,
  });
});

app.get("/v1/me", async (req, res) => {
  if (!pool) {
    const sub = bearerToken(req);
    if (sub && demoCreditsByToken.has(sub)) {
      const left = demoCreditsByToken.get(sub);
      return res.json({
        ok: true,
        credits: left,
        subscription: {
          active: true,
          status: "demo",
          expiresAt: null,
          dailyLimit: PLAN.dailyLimit,
          dailyUsed: PLAN.dailyLimit - left,
          dailyRemaining: left,
          dailyQuotaDate: cnDateKey(),
          reportUnlimited: true,
          monthlyPriceCNY: PLAN.monthlyPriceCNY,
        },
        note: "演示：内存中的次数（重启服务会重置）",
        version: "0.4-demo",
      });
    }
    return res.json({
      ok: true,
      credits: PLAN.dailyLimit,
      subscription: {
        active: true,
        status: "demo",
        expiresAt: null,
        dailyLimit: PLAN.dailyLimit,
        dailyUsed: 0,
        dailyRemaining: PLAN.dailyLimit,
        dailyQuotaDate: cnDateKey(),
        reportUnlimited: true,
        monthlyPriceCNY: PLAN.monthlyPriceCNY,
      },
      note: "演示数据：未配置 config.json 或未连上数据库",
      version: "0.3-demo",
    });
  }

  const sub = bearerToken(req);
  if (!sub) {
    return res.status(401).json({
      ok: false,
      error: "需要 Header：Authorization: Bearer <accessToken>（请先调用 POST /v1/auth/apple）",
    });
  }
  try {
    let row = await loadUserRow(sub);
    if (!row) {
      return res.status(404).json({ ok: false, error: "用户不存在，请先登录" });
    }
    row = await resetDailyQuotaIfNeeded(sub, row);
    const subscription = buildSubscriptionPayload(row);
    return res.json({
      ok: true,
      credits: subscription.dailyRemaining,
      subscription,
      version: "0.6",
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ ok: false, error: "数据库查询失败" });
  }
});

app.post("/v1/auth/apple", async (req, res) => {
  const token = req.body?.identityToken;
  if (!token || typeof token !== "string") {
    return res.status(400).json({
      ok: false,
      error: "缺少 identityToken（JSON：{\"identityToken\":\"...\"}）",
    });
  }

  const sub = appleSubFromToken(token);

  if (!pool) {
    demoCreditsByToken.set(sub, PLAN.dailyLimit);
    return res.json({
      ok: true,
      accessToken: sub,
      credits: PLAN.dailyLimit,
      subscription: {
        active: true,
        status: "demo",
        expiresAt: null,
        dailyLimit: PLAN.dailyLimit,
        dailyUsed: 0,
        dailyRemaining: PLAN.dailyLimit,
        dailyQuotaDate: cnDateKey(),
        reportUnlimited: true,
        monthlyPriceCNY: PLAN.monthlyPriceCNY,
      },
      note: "演示：未连数据库，扣次在内存中模拟（重启服务会重置）",
      version: "0.4-demo",
    });
  }

  try {
    await pool.execute(
      "INSERT INTO users (apple_sub, credits, plan_status, plan_expires_at, daily_limit, daily_used, daily_quota_date, report_unlimited) VALUES (?, ?, 'active', DATE_ADD(NOW(), INTERVAL ? DAY), ?, 0, ?, 1) ON DUPLICATE KEY UPDATE apple_sub = apple_sub",
      [sub, PLAN.dailyLimit, PLAN.trialDays, PLAN.dailyLimit, cnDateKey()]
    );
    let row = await loadUserRow(sub);
    if (row && !row.plan_expires_at) {
      await pool.execute(
        "UPDATE users SET plan_status = 'active', plan_expires_at = DATE_ADD(NOW(), INTERVAL ? DAY), daily_limit = ?, daily_used = 0, daily_quota_date = ? WHERE apple_sub = ?",
        [PLAN.trialDays, PLAN.dailyLimit, cnDateKey(), sub]
      );
      row = await loadUserRow(sub);
    }
    row = await resetDailyQuotaIfNeeded(sub, row);
    const subscription = buildSubscriptionPayload(row);
    const credits = subscription.dailyRemaining;
    return res.json({
      ok: true,
      accessToken: sub,
      credits,
      subscription,
      note: "已写入数据库（首次登录赠送30天会员，每日20次）",
      version: "0.6",
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ ok: false, error: "数据库写入失败：" + e.message });
  }
});

/**
 * POST /v1/credits/consume
 * Header: Authorization: Bearer <accessToken>
 * Body: { "amount": 1 } 可选，默认 1，上限 10
 */
app.post("/v1/credits/consume", async (req, res) => {
  const sub = bearerToken(req);
  let amount = Number(req.body?.amount);
  if (!Number.isFinite(amount) || amount < 1) amount = 1;
  amount = Math.min(10, Math.floor(amount));

  const con = await consumeCreditsInternal(sub, amount);
  if (!con.ok) {
    return res.status(con.statusCode).json({
      ok: false,
      error: con.errorMessage,
      credits: con.credits,
    });
  }
  return res.json({
    ok: true,
    credits: con.credits,
    version: pool ? "0.4" : "0.4-demo",
  });
});

/**
 * POST /v1/subscription/mock/renew
 * Bearer accessToken；开发联调用：手动续期 N 天并重置当日配额（后续可改为 IAP 验票入账）。
 * Body: { days?: number } 默认 30 天。
 */
app.post("/v1/subscription/mock/renew", async (req, res) => {
  if (!isMockRenewEnabled()) {
    return res.status(403).json({
      ok: false,
      error: "mock/renew 已关闭（生产环境）。如需启用请设置 ALLOW_MOCK_RENEW=true",
    });
  }
  const sub = bearerToken(req);
  if (!sub) {
    return res.status(401).json({ ok: false, error: "需要 Bearer accessToken" });
  }
  if (!pool) {
    demoCreditsByToken.set(sub, PLAN.dailyLimit);
    return res.json({
      ok: true,
      credits: PLAN.dailyLimit,
      subscription: {
        active: true,
        status: "demo",
        expiresAt: null,
        dailyLimit: PLAN.dailyLimit,
        dailyUsed: 0,
        dailyRemaining: PLAN.dailyLimit,
        dailyQuotaDate: cnDateKey(),
        reportUnlimited: true,
        monthlyPriceCNY: PLAN.monthlyPriceCNY,
      },
      note: "演示模式：已重置每日配额",
    });
  }
  let days = Number(req.body?.days);
  if (!Number.isFinite(days) || days < 1) days = 30;
  days = Math.min(365, Math.floor(days));
  try {
    const [result] = await pool.execute(
      "UPDATE users SET plan_status = 'active', plan_expires_at = DATE_ADD(GREATEST(COALESCE(plan_expires_at, NOW()), NOW()), INTERVAL ? DAY), daily_limit = ?, daily_used = 0, daily_quota_date = ?, report_unlimited = 1 WHERE apple_sub = ?",
      [days, PLAN.dailyLimit, cnDateKey(), sub]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ ok: false, error: "用户不存在，请先登录" });
    }
    let row = await loadUserRow(sub);
    row = await resetDailyQuotaIfNeeded(sub, row);
    const subscription = buildSubscriptionPayload(row);
    return res.json({
      ok: true,
      credits: subscription.dailyRemaining,
      subscription,
      note: "已续期 " + days + " 天（开发联调接口）",
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ ok: false, error: "续期失败：" + e.message });
  }
});

/**
 * POST /v1/subscription/apple/verify
 * Header: Authorization: Bearer <accessToken>
 * Body: { productId: string, signedTransactionInfo: string }
 *
 * 说明：当前实现先做“JWS 结构解析 + 字段校验 + 到期入库”，用于联调闭环。
 * 生产建议升级为：Apple 官方签名链校验（x5c）或 App Store Server API 二次验票。
 */
app.post("/v1/subscription/apple/verify", async (req, res) => {
  const sub = bearerToken(req);
  if (!sub) {
    return res.status(401).json({ ok: false, error: "需要 Bearer accessToken" });
  }
  if (!pool) {
    return res.status(503).json({ ok: false, error: "数据库未连接，无法验票入账" });
  }

  const productId = String(req.body?.productId || "").trim();
  const signedTransactionInfo = String(req.body?.signedTransactionInfo || "").trim();
  if (!productId || !signedTransactionInfo) {
    return res.status(400).json({
      ok: false,
      error: "缺少参数：productId 与 signedTransactionInfo 均必填",
    });
  }

  const expectedBundleId = String(fileConfig.appleBundleId || "com.safeMaster.aqds").trim();
  const expectedProductId = String(fileConfig.appleMonthlyProductId || "com.safeMaster.aqds.monthly").trim();
  if (productId !== expectedProductId) {
    return res.status(400).json({
      ok: false,
      error: "productId 不匹配，期望 " + expectedProductId,
    });
  }

  try {
    await ensureIapTransactionsTable();
    const payload = decodeJWTPayloadWithoutVerify(signedTransactionInfo);
    if (!payload || typeof payload !== "object") {
      return res.status(400).json({ ok: false, error: "signedTransactionInfo 不是有效 JWS" });
    }

    const txProductId = String(payload.productId || "").trim();
    const txBundleId = String(payload.bundleId || "").trim();
    const txId = String(payload.transactionId || "").trim();
    const originalTxId = String(payload.originalTransactionId || txId).trim();
    const txEnv = String(payload.environment || "").trim();
    const expiresDateMs = Number(payload.expiresDate);

    if (!txProductId || !txBundleId || !txId || !originalTxId || !Number.isFinite(expiresDateMs)) {
      return res.status(400).json({
        ok: false,
        error: "交易字段不完整：需要 productId / bundleId / transactionId / originalTransactionId / expiresDate",
      });
    }
    if (txProductId !== expectedProductId || txProductId !== productId) {
      return res.status(400).json({ ok: false, error: "交易中的 productId 不匹配" });
    }
    if (txBundleId !== expectedBundleId) {
      return res.status(400).json({ ok: false, error: "交易中的 bundleId 不匹配" });
    }

    const expiresAt = new Date(expiresDateMs);
    if (!Number.isFinite(expiresAt.getTime())) {
      return res.status(400).json({ ok: false, error: "expiresDate 非法" });
    }

    const now = Date.now();
    const gracePastMs = 10 * 60 * 1000;
    if (expiresAt.getTime() < now - gracePastMs) {
      return res.status(402).json({ ok: false, error: "订阅已过期，未续费成功" });
    }

    const expiresAtSql = expiresAt.toISOString().slice(0, 19).replace("T", " ");
    let isDuplicateTx = false;
    try {
      const [ins] = await pool.execute(
        "INSERT INTO iap_transactions (apple_sub, product_id, transaction_id, original_transaction_id, expires_at, environment) VALUES (?, ?, ?, ?, ?, ?)",
        [sub, txProductId, txId, originalTxId, expiresAtSql, txEnv]
      );
      isDuplicateTx = Number(ins?.affectedRows || 0) === 0;
    } catch (e) {
      if (e && e.code === "ER_DUP_ENTRY") {
        isDuplicateTx = true;
      } else {
        throw e;
      }
    }

    const [result] = await pool.execute(
      "UPDATE users SET plan_status = 'active', plan_expires_at = GREATEST(COALESCE(plan_expires_at, '1970-01-01 00:00:00'), ?), daily_limit = ?, report_unlimited = 1 WHERE apple_sub = ?",
      [expiresAtSql, PLAN.dailyLimit, sub]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ ok: false, error: "用户不存在，请先登录" });
    }

    let row = await loadUserRow(sub);
    row = await resetDailyQuotaIfNeeded(sub, row);
    const subscription = buildSubscriptionPayload(row);
    return res.json({
      ok: true,
      credits: subscription.dailyRemaining,
      subscription,
      note: isDuplicateTx ? "Apple 订阅重复凭证，已幂等处理" : "Apple 订阅已入账（联调模式）",
    });
  } catch (e) {
    console.error("[subscription.verify]", e);
    return res.status(500).json({ ok: false, error: "验票入账失败：" + e.message });
  }
});

/**
 * POST /v1/hazard/analyze
 * Bearer accessToken；本接口内先扣 1 次再代调 DeepSeek（密钥仅在服务器）。
 * Body: { hasPhoto, location, supplementaryText, visionBlock, playbookBlock, lawEvidenceBlock }
 */
app.post("/v1/hazard/analyze", async (req, res) => {
  const sub = bearerToken(req);
  if (!sub) {
    return res.status(401).json({ ok: false, error: "需要 Bearer accessToken" });
  }

  const apiKey = getDeepseekKey();
  if (!apiKey) {
    return res.status(503).json({
      ok: false,
      error:
        "服务器未配置 DeepSeek：请在环境变量 DEEPSEEK_API_KEY 或 config.json 的 deepseekApiKey 中填写密钥",
    });
  }

  const con = await consumeCreditsInternal(sub, 1);
  if (!con.ok) {
    return res.status(con.statusCode).json({
      ok: false,
      error: con.errorMessage,
      credits: con.credits,
    });
  }
  const creditsAfter = con.credits;

  const hasPhoto = Boolean(req.body?.hasPhoto);
  const visionBlock = clampStr(req.body?.visionBlock ?? "", MAX_ANALYZE.vision);
  const playbookBlock = clampStr(req.body?.playbookBlock ?? "", MAX_ANALYZE.playbook);
  const lawEvidenceBlock = clampStr(req.body?.lawEvidenceBlock ?? "", MAX_ANALYZE.law);
  const locationRaw = clampStr(req.body?.location ?? "", MAX_ANALYZE.location);
  const supplementaryRaw = clampStr(req.body?.supplementaryText ?? "", MAX_ANALYZE.supplementary);

  const place = locationRaw.trim() || "未填写";
  const text = supplementaryRaw.trim();
  const userExtra = text ? text : "（用户未填写补充文字）";

  const systemPrompt = buildSystemPrompt();
  const userPrompt = buildUserPrompt(
    place,
    userExtra,
    visionBlock,
    playbookBlock,
    lawEvidenceBlock,
    hasPhoto
  );

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 120000);

  try {
    const dr = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer " + apiKey,
      },
      body: JSON.stringify({
        model: "deepseek-chat",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.35,
      }),
      signal: controller.signal,
    });

    const rawText = await dr.text();
    if (!dr.ok) {
      console.error("[DeepSeek] HTTP", dr.status, rawText.slice(0, 600));
      return res.status(502).json({
        ok: false,
        error: "模型服务错误（HTTP " + dr.status + "）",
        credits: creditsAfter,
      });
    }

    let dj;
    try {
      dj = JSON.parse(rawText);
    } catch (e) {
      return res.status(502).json({
        ok: false,
        error: "模型响应不是 JSON",
        credits: creditsAfter,
      });
    }

    const content = dj.choices?.[0]?.message?.content;
    if (!content || typeof content !== "string") {
      return res.status(502).json({
        ok: false,
        error: "模型未返回内容",
        credits: creditsAfter,
      });
    }

    const cleaned = stripMarkdownJSONFence(content);
    let obj;
    try {
      obj = JSON.parse(cleaned);
    } catch (e) {
      console.error("[DeepSeek] 内容 JSON 解析失败", e.message, cleaned.slice(0, 400));
      return res.status(502).json({
        ok: false,
        error: "模型返回不是有效 JSON",
        credits: creditsAfter,
      });
    }

    const analysis = normalizeAnalysis(obj);
    return res.json({
      ok: true,
      credits: creditsAfter,
      version: pool ? "0.5" : "0.5-demo",
      analysis,
    });
  } catch (e) {
    const msg = e.name === "AbortError" ? "模型请求超时" : e.message;
    console.error("[v1/hazard/analyze]", e);
    return res.status(502).json({
      ok: false,
      error: "分析失败：" + msg,
      credits: creditsAfter,
    });
  } finally {
    clearTimeout(timer);
  }
});

app.get("/", (req, res) => {
  res.type("html").send(
    `<h1>SafeMaster 服务端</h1>
    <p>模式：<b>${dbMode}</b></p>
    <ul>
      <li><a href="/health">GET /health</a></li>
      <li>GET /v1/me（Bearer；返回会员状态与每日剩余次数）</li>
      <li>POST /v1/auth/apple</li>
      <li>POST /v1/credits/consume（Bearer，开发接口：扣分析次数）</li>
      <li>POST /v1/subscription/mock/renew（Bearer，开发联调用：续期与重置配额）</li>
      <li>POST /v1/hazard/analyze（Bearer，扣 1 次 + 服务端代调 DeepSeek）</li>
    </ul>`
  );
});

app.listen(port, "0.0.0.0", () => {
  console.log(`SafeMaster API 监听 http://0.0.0.0:${port} （dbMode=${dbMode}）`);
});
