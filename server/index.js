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
const multer = require("multer");
const mammoth = require("mammoth");
const { buildSystemPrompt, buildUserPrompt } = require("./hazardPrompts");
const { LawEvidenceRetriever } = require("./lawEvidenceRetriever");
const { buildRateLimiters } = require("./rateLimiters");

const app = express();
const port = Number(process.env.PORT) || 3000;
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 },
});

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

const lawRetriever = new LawEvidenceRetriever({
  lawsDir: fileConfig.lawsDir || process.env.LAWS_DIR || "",
});
const defaultLawDomain = String(fileConfig.activeLawDomain || process.env.SAFEMASTER_ACTIVE_LAW_DOMAIN || "construction").trim();
const trustProxyRaw = process.env.TRUST_PROXY ?? fileConfig.trustProxy;
if (trustProxyRaw !== undefined && trustProxyRaw !== null && String(trustProxyRaw).trim() !== "") {
  const trustProxy = ["1", "true", "yes", "on"].includes(String(trustProxyRaw).trim().toLowerCase());
  if (trustProxy) {
    app.set("trust proxy", 1);
  }
}

const { authLimiter, analyzeLimiter, creditsLimiter } = buildRateLimiters(fileConfig);

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

function normalizeAIUnits(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.min(10000, Math.ceil(n));
}

function normalizePlanDays(raw, fallback = PLAN.trialDays) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(365, Math.floor(n));
}

function usageUnitsFromTokens(totalTokens) {
  const total = Number(totalTokens);
  if (!Number.isFinite(total) || total <= 0) return 1;
  return normalizeAIUnits(total / PLAN.aiUnitTokens);
}

function normalizeModelUsage(raw) {
  const promptTokens = Number(raw?.prompt_tokens ?? raw?.promptTokens ?? 0);
  const completionTokens = Number(raw?.completion_tokens ?? raw?.completionTokens ?? 0);
  const totalTokensRaw = Number(raw?.total_tokens ?? raw?.totalTokens ?? 0);
  const safePrompt = Number.isFinite(promptTokens) && promptTokens > 0 ? Math.floor(promptTokens) : 0;
  const safeCompletion = Number.isFinite(completionTokens) && completionTokens > 0 ? Math.floor(completionTokens) : 0;
  const totalTokens = Number.isFinite(totalTokensRaw) && totalTokensRaw > 0
    ? Math.floor(totalTokensRaw)
    : safePrompt + safeCompletion;
  return {
    promptTokens: safePrompt,
    completionTokens: safeCompletion,
    totalTokens: Math.max(0, totalTokens),
  };
}

function remainingAIUnits(row) {
  const limit = Number(row?.daily_ai_unit_limit ?? row?.daily_limit ?? PLAN.dailyAIUnitLimit);
  const used = Number(row?.daily_ai_unit_used ?? row?.daily_used ?? 0);
  return Math.max(0, limit - used);
}

/**
 * AI 额度扣减：保留旧的 credits 返回字段，但含义改为“剩余 AI 点数”。
 * @returns {Promise<{ok:boolean,credits?:number,statusCode?:number,errorMessage?:string}>}
 */
async function consumeCreditsInternal(sub, amount, options = {}) {
  if (!sub) {
    return { ok: false, statusCode: 401, errorMessage: "需要 Bearer accessToken" };
  }
  const amt = normalizeAIUnits(amount);
  const allowOverage = Boolean(options.allowOverage);

  if (!pool) {
    if (!demoCreditsByToken.has(sub)) demoCreditsByToken.set(sub, PLAN.dailyAIUnitLimit);
    const cur = demoCreditsByToken.get(sub);
    if (!allowOverage && cur < amt) {
      return { ok: false, statusCode: 402, credits: cur, errorMessage: "次数不足" };
    }
    const next = Math.max(0, cur - amt);
    demoCreditsByToken.set(sub, next);
    return { ok: true, credits: next };
  }

  try {
    await ensureUsageSchema();
    let row = await loadUserRow(sub);
    if (!row) {
      return { ok: false, statusCode: 404, credits: 0, errorMessage: "用户不存在，请先登录" };
    }
    row = await resetDailyQuotaIfNeeded(sub, row);

    if (!isPlanActive(row)) {
      return {
        ok: false,
        statusCode: 402,
        credits: remainingAIUnits(row),
        errorMessage: "会员已过期或未开通，请先订阅（月费48元）",
      };
    }
    const left = remainingAIUnits(row);
    if (!allowOverage && left < amt) {
      return {
        ok: false,
        statusCode: 402,
        credits: left,
        errorMessage: "今日 AI 额度不足",
      };
    }
    await pool.execute(
      "UPDATE users SET daily_ai_unit_used = daily_ai_unit_used + ? WHERE apple_sub = ?",
      [amt, sub]
    );
    if (options.usageLog) {
      await insertAIUsageLog({
        appleSub: sub,
        feature: options.usageLog.feature || "unknown",
        model: options.usageLog.model || "",
        usage: options.usageLog.usage,
        unitsCharged: amt,
      });
    }
    row = await loadUserRow(sub);
    row = await resetDailyQuotaIfNeeded(sub, row);
    return { ok: true, credits: remainingAIUnits(row) };
  } catch (e) {
    console.error(e);
    return { ok: false, statusCode: 500, errorMessage: "扣减 AI 额度失败：" + e.message };
  }
}

async function preflightAIQuota(sub) {
  if (!sub) {
    return { ok: false, statusCode: 401, errorMessage: "需要 Bearer accessToken" };
  }
  if (!pool) {
    if (!demoCreditsByToken.has(sub)) demoCreditsByToken.set(sub, PLAN.dailyAIUnitLimit);
    const left = demoCreditsByToken.get(sub);
    return left > 0
      ? { ok: true, credits: left }
      : { ok: false, statusCode: 402, credits: 0, errorMessage: "今日 AI 额度不足" };
  }
  await ensureUsageSchema();
  let row = await loadUserRow(sub);
  if (!row) {
    return { ok: false, statusCode: 404, credits: 0, errorMessage: "用户不存在，请先登录" };
  }
  row = await resetDailyQuotaIfNeeded(sub, row);
  if (!isPlanActive(row)) {
    return {
      ok: false,
      statusCode: 402,
      credits: remainingAIUnits(row),
      errorMessage: "会员已过期或未开通，请先订阅（月费48元）",
    };
  }
  const left = remainingAIUnits(row);
  return left > 0
    ? { ok: true, credits: left }
    : { ok: false, statusCode: 402, credits: 0, errorMessage: "今日 AI 额度不足" };
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
  const replyDraft = pickField(obj.rectification_reply_draft, obj.rectificationReplyDraft);
  return {
    hazard_description: hazard,
    rectification_measures: measures,
    rectification_reply_draft: replyDraft,
    risk_level: risk,
    accident_category_major: pickField(obj.accident_category_major, obj.accidentCategoryMajor),
    accident_category_minor: pickField(obj.accident_category_minor, obj.accidentCategoryMinor),
    legal_basis: pickField(obj.legal_basis, obj.legalBasis),
  };
}

function normalizeNoticeField(raw, fallbackConfidence = 0.92) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    const value = pickField(raw.value, raw.text);
    const confidence = Number(raw.confidence);
    return {
      value,
      confidence: Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : fallbackConfidence,
      sourceSnippet: pickField(raw.source_snippet, raw.sourceSnippet) || undefined,
      needsReview: Boolean(raw.needs_review ?? raw.needsReview ?? !value),
    };
  }
  const value = raw == null ? "" : String(raw).trim();
  return {
    value,
    confidence: value ? fallbackConfidence : 0,
    sourceSnippet: undefined,
    needsReview: !value,
  };
}

function normalizeNoticeDraft(obj) {
  const typeRaw = pickField(obj.document_type, obj.documentType).toLowerCase();
  const documentType = ["hazardNotice", "rectificationReply", "inspectionRecord", "meetingMinutes", "unknown"]
    .includes(typeRaw)
    ? typeRaw
    : (typeRaw.includes("reply") || typeRaw.includes("回复") ? "rectificationReply" : "hazardNotice");
  const hazardsRaw = Array.isArray(obj.hazards) ? obj.hazards : [];
  const hazards = hazardsRaw.map((h) => ({
    location: normalizeNoticeField(h?.location, 0.9),
    description: normalizeNoticeField(h?.description ?? h?.hazard_description ?? h?.hazardDescription, 0.9),
    requirement: normalizeNoticeField(h?.requirement ?? h?.rectification_requirement ?? h?.rectificationRequirement, 0.9),
    dueDate: normalizeNoticeField(h?.due_date ?? h?.dueDate, 0.88),
    responsibleParty: normalizeNoticeField(h?.responsible_party ?? h?.responsibleParty, 0.88),
  })).filter((h) => h.description.value || h.requirement.value || h.location.value);

  const confidence = Number(obj.confidence);
  return {
    documentType,
    projectName: normalizeNoticeField(obj.project_name ?? obj.projectName, 0.9),
    issuer: normalizeNoticeField(obj.issuer, 0.92),
    inspectedUnit: normalizeNoticeField(obj.inspected_unit ?? obj.inspectedUnit, 0.92),
    noticeNo: normalizeNoticeField(obj.notice_no ?? obj.noticeNo, 0.92),
    noticeDate: normalizeNoticeField(obj.notice_date ?? obj.noticeDate, 0.92),
    rectificationDeadline: normalizeNoticeField(obj.rectification_deadline ?? obj.rectificationDeadline, 0.9),
    hazards,
    legalBasis: normalizeNoticeField(obj.legal_basis ?? obj.legalBasis, 0.88),
    summary: pickField(obj.summary, obj.document_summary ?? obj.documentSummary),
    confidence: Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : 0.9,
    warnings: Array.isArray(obj.warnings) ? obj.warnings.map((x) => String(x)).filter(Boolean).slice(0, 12) : [],
  };
}

const MAX_ANALYZE = {
  location: 500,
  supplementary: 4000,
  vision: 12000,
};

const PLAN = {
  monthlyPriceCNY: Number(fileConfig.planMonthlyPriceCNY) > 0 ? Number(fileConfig.planMonthlyPriceCNY) : 48,
  dailyLimit: Number(fileConfig.planDailyLimit) > 0 ? Number(fileConfig.planDailyLimit) : 20,
  dailyAIUnitLimit: Number(fileConfig.planDailyAIUnitLimit) > 0
    ? Number(fileConfig.planDailyAIUnitLimit)
    : 200,
  aiUnitTokens: Number(fileConfig.aiUnitTokens) > 0 ? Number(fileConfig.aiUnitTokens) : 1000,
  trialDays: 30,
};

let usageSchemaPromise = null;

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
  return remainingAIUnits(row);
}

async function loadUserRow(sub) {
  await ensureUsageSchema();
  const [rows] = await pool.execute(
    "SELECT apple_sub, credits, plan_status, plan_expires_at, daily_limit, daily_used, daily_ai_unit_limit, daily_ai_unit_used, daily_quota_date, report_unlimited FROM users WHERE apple_sub = ? LIMIT 1",
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
    "UPDATE users SET daily_used = 0, daily_ai_unit_used = 0, daily_quota_date = ? WHERE apple_sub = ?",
    [today, sub]
  );
  row.daily_used = 0;
  row.daily_ai_unit_used = 0;
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
    dailyLimit: Number(row.daily_ai_unit_limit ?? PLAN.dailyAIUnitLimit),
    dailyUsed: Number(row.daily_ai_unit_used ?? 0),
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

function decodeTextBuffer(buf) {
  if (!buf || !buf.length) return "";
  const candidates = ["utf8", "utf16le", "latin1"];
  for (const enc of candidates) {
    const s = Buffer.from(buf).toString(enc).trim();
    if (s) return s;
  }
  return "";
}

function extOf(name = "") {
  return path.extname(String(name).toLowerCase()).replace(".", "");
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

async function tableHasColumn(tableName, columnName) {
  if (!/^[A-Za-z0-9_]+$/.test(tableName) || !/^[A-Za-z0-9_]+$/.test(columnName)) {
    throw new Error("非法数据表或字段名");
  }
  const [rows] = await pool.execute(
    "SHOW COLUMNS FROM `" + tableName + "` LIKE '" + columnName + "'"
  );
  return Array.isArray(rows) && rows.length > 0;
}

async function ensureUsageSchema() {
  if (!pool) return;
  if (!usageSchemaPromise) {
    usageSchemaPromise = (async () => {
      if (!(await tableHasColumn("users", "daily_ai_unit_limit"))) {
        await pool.execute(
          "ALTER TABLE users ADD COLUMN daily_ai_unit_limit INT NOT NULL DEFAULT " +
            Number(PLAN.dailyAIUnitLimit) +
            " COMMENT '每日 AI 点数额度'"
        );
      }
      if (!(await tableHasColumn("users", "daily_ai_unit_used"))) {
        await pool.execute(
          "ALTER TABLE users ADD COLUMN daily_ai_unit_used INT NOT NULL DEFAULT 0 COMMENT '当日已用 AI 点数'"
        );
      }
      await pool.execute(
        "UPDATE users SET daily_ai_unit_limit = ? WHERE daily_ai_unit_limit IS NULL OR daily_ai_unit_limit <= 0",
        [PLAN.dailyAIUnitLimit]
      );
      await pool.execute(`
        CREATE TABLE IF NOT EXISTS ai_usage_logs (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          apple_sub VARCHAR(64) NOT NULL,
          feature VARCHAR(64) NOT NULL DEFAULT '',
          model VARCHAR(64) NOT NULL DEFAULT '',
          prompt_tokens INT NOT NULL DEFAULT 0,
          completion_tokens INT NOT NULL DEFAULT 0,
          total_tokens INT NOT NULL DEFAULT 0,
          units_charged INT NOT NULL DEFAULT 0,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (id),
          KEY idx_ai_usage_apple_sub_created (apple_sub, created_at),
          KEY idx_ai_usage_feature_created (feature, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
      `);
    })();
  }
  return usageSchemaPromise;
}

async function insertAIUsageLog({ appleSub, feature, model, usage, unitsCharged }) {
  if (!pool) return;
  const normalized = normalizeModelUsage(usage);
  await pool.execute(
    "INSERT INTO ai_usage_logs (apple_sub, feature, model, prompt_tokens, completion_tokens, total_tokens, units_charged) VALUES (?, ?, ?, ?, ?, ?, ?)",
    [
      appleSub,
      String(feature || "").slice(0, 64),
      String(model || "").slice(0, 64),
      normalized.promptTokens,
      normalized.completionTokens,
      normalized.totalTokens,
      normalizeAIUnits(unitsCharged),
    ]
  );
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
          dailyLimit: PLAN.dailyAIUnitLimit,
          dailyUsed: PLAN.dailyAIUnitLimit - left,
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
      credits: PLAN.dailyAIUnitLimit,
      subscription: {
        active: true,
        status: "demo",
        expiresAt: null,
        dailyLimit: PLAN.dailyAIUnitLimit,
        dailyUsed: 0,
        dailyRemaining: PLAN.dailyAIUnitLimit,
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

/**
 * GET /v1/laws/status
 * 用于确认服务端法规库加载状态与实际目录（便于运维热更新核对）。
 */
app.get("/v1/laws/status", (req, res) => {
  try {
    const status = lawRetriever.getStatus();
    return res.json({
      ok: true,
      status,
      activeLawDomain: defaultLawDomain || "construction",
      note: "法规库由服务端本地文件提供。更新 lawsDir 下文件后，接口将按文件修改时间自动重载。",
    });
  } catch (e) {
    return res.status(500).json({ ok: false, error: "读取法规库状态失败：" + e.message });
  }
});

app.post("/v1/auth/apple", authLimiter, async (req, res) => {
  const token = req.body?.identityToken;
  if (!token || typeof token !== "string") {
    return res.status(400).json({
      ok: false,
      error: "缺少 identityToken（JSON：{\"identityToken\":\"...\"}）",
    });
  }

  const sub = appleSubFromToken(token);

  if (!pool) {
    demoCreditsByToken.set(sub, PLAN.dailyAIUnitLimit);
    return res.json({
      ok: true,
      accessToken: sub,
      credits: PLAN.dailyAIUnitLimit,
      subscription: {
        active: true,
        status: "demo",
        expiresAt: null,
        dailyLimit: PLAN.dailyAIUnitLimit,
        dailyUsed: 0,
        dailyRemaining: PLAN.dailyAIUnitLimit,
        dailyQuotaDate: cnDateKey(),
        reportUnlimited: true,
        monthlyPriceCNY: PLAN.monthlyPriceCNY,
      },
      note: "演示：未连数据库，扣次在内存中模拟（重启服务会重置）",
      version: "0.4-demo",
    });
  }

  try {
    await ensureUsageSchema();
    const trialDays = normalizePlanDays(PLAN.trialDays);
    await pool.execute(
      "INSERT INTO users (apple_sub, credits, plan_status, plan_expires_at, daily_limit, daily_used, daily_ai_unit_limit, daily_ai_unit_used, daily_quota_date, report_unlimited) VALUES (?, ?, 'active', DATE_ADD(NOW(), INTERVAL " + trialDays + " DAY), ?, 0, ?, 0, ?, 1) ON DUPLICATE KEY UPDATE apple_sub = apple_sub",
      [sub, PLAN.dailyAIUnitLimit, PLAN.dailyLimit, PLAN.dailyAIUnitLimit, cnDateKey()]
    );
    let row = await loadUserRow(sub);
    if (row && !row.plan_expires_at) {
      await pool.execute(
        "UPDATE users SET plan_status = 'active', plan_expires_at = DATE_ADD(NOW(), INTERVAL " + trialDays + " DAY), daily_limit = ?, daily_used = 0, daily_ai_unit_limit = ?, daily_ai_unit_used = 0, daily_quota_date = ? WHERE apple_sub = ?",
        [PLAN.dailyLimit, PLAN.dailyAIUnitLimit, cnDateKey(), sub]
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
      note: "已写入数据库（首次登录赠送30天会员，按每日 AI 点数额度计费）",
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
app.post("/v1/credits/consume", creditsLimiter, async (req, res) => {
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
    demoCreditsByToken.set(sub, PLAN.dailyAIUnitLimit);
    return res.json({
      ok: true,
      credits: PLAN.dailyAIUnitLimit,
      subscription: {
        active: true,
        status: "demo",
        expiresAt: null,
        dailyLimit: PLAN.dailyAIUnitLimit,
        dailyUsed: 0,
        dailyRemaining: PLAN.dailyAIUnitLimit,
        dailyQuotaDate: cnDateKey(),
        reportUnlimited: true,
        monthlyPriceCNY: PLAN.monthlyPriceCNY,
      },
      note: "演示模式：已重置每日配额",
    });
  }
  let days = Number(req.body?.days);
  if (!Number.isFinite(days) || days < 1) days = 30;
  days = normalizePlanDays(days, 30);
  try {
    const [result] = await pool.execute(
      "UPDATE users SET plan_status = 'active', plan_expires_at = DATE_ADD(GREATEST(COALESCE(plan_expires_at, NOW()), NOW()), INTERVAL " + days + " DAY), daily_limit = ?, daily_used = 0, daily_ai_unit_limit = ?, daily_ai_unit_used = 0, daily_quota_date = ?, report_unlimited = 1 WHERE apple_sub = ?",
      [PLAN.dailyLimit, PLAN.dailyAIUnitLimit, cnDateKey(), sub]
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
      "UPDATE users SET plan_status = 'active', plan_expires_at = GREATEST(COALESCE(plan_expires_at, '1970-01-01 00:00:00'), ?), daily_limit = ?, daily_ai_unit_limit = ?, report_unlimited = 1 WHERE apple_sub = ?",
      [expiresAtSql, PLAN.dailyLimit, PLAN.dailyAIUnitLimit, sub]
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
 * Bearer accessToken；服务端代调 DeepSeek，成功后按模型 usage 折算 AI 点数。
 * Body: { hasPhoto, location, supplementaryText, visionBlock, industryDomain? }
 * 说明：法规检索全部在服务端完成，App 不再上传本地法规块。
 */
app.post("/v1/hazard/analyze", analyzeLimiter, async (req, res) => {
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

  const quota = await preflightAIQuota(sub);
  if (!quota.ok) {
    return res.status(quota.statusCode).json({
      ok: false,
      error: quota.errorMessage,
      credits: quota.credits,
    });
  }
  let creditsAfter = quota.credits;

  const hasPhoto = Boolean(req.body?.hasPhoto);
  const visionBlock = clampStr(req.body?.visionBlock ?? "", MAX_ANALYZE.vision);
  const locationRaw = clampStr(req.body?.location ?? "", MAX_ANALYZE.location);
  const supplementaryRaw = clampStr(req.body?.supplementaryText ?? "", MAX_ANALYZE.supplementary);

  const place = locationRaw.trim() || "未填写";
  const text = supplementaryRaw.trim();
  const userExtra = text ? text : "（用户未填写补充文字）";
  const retrievalQuery = `${place}\n${userExtra}\n${visionBlock}`;
  const industryDomain = String(req.body?.industryDomain || defaultLawDomain || "construction").trim();

  let playbookBlock = "";
  let lawEvidenceBlock = "";
  try {
    const evidence = lawRetriever.retrieveBlocks({
      query: retrievalQuery,
      userEmphasis: text,
      playbookTopK: 8,
      basisTopK: 6,
      domain: industryDomain,
    });
    playbookBlock = evidence.playbookBlock;
    lawEvidenceBlock = evidence.basisBlock;
  } catch (e) {
      return res.status(503).json({
        ok: false,
        error: "服务端法规库不可用：" + e.message,
      credits: creditsAfter,
    });
  }

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
    const usage = normalizeModelUsage(dj.usage);
    const unitsCharged = usageUnitsFromTokens(usage.totalTokens);
    const charged = await consumeCreditsInternal(sub, unitsCharged, {
      allowOverage: true,
      usageLog: {
        feature: "hazard_analyze",
        model: "deepseek-chat",
        usage,
      },
    });
    if (charged.ok) {
      creditsAfter = charged.credits;
    }
    return res.json({
      ok: true,
      credits: creditsAfter,
      usage: {
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        totalTokens: usage.totalTokens,
        unitsCharged,
      },
      version: pool ? "0.7" : "0.7-demo",
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

/**
 * POST /v1/import/extract-text
 * Bearer accessToken；上传文件后服务端提取文本（docx/doc/txt/rtf）。
 * multipart/form-data:
 * - file: 二进制文件
 * - cleanWithAI: "1" | "true"（可选，默认开启）
 */
app.post("/v1/import/extract-text", analyzeLimiter, upload.single("file"), async (req, res) => {
  const sub = bearerToken(req);
  if (!sub) {
    return res.status(401).json({ ok: false, error: "需要 Bearer accessToken" });
  }
  const file = req.file;
  if (!file || !file.buffer || !file.originalname) {
    return res.status(400).json({ ok: false, error: "缺少上传文件（字段名 file）" });
  }
  const ext = extOf(file.originalname);
  let extracted = "";
  try {
    if (ext === "docx") {
      const result = await mammoth.extractRawText({ buffer: file.buffer });
      extracted = String(result.value || "").trim();
    } else if (ext === "doc" || ext === "rtf" || ext === "txt") {
      extracted = decodeTextBuffer(file.buffer);
    } else {
      return res.status(415).json({
        ok: false,
        error: "当前仅支持 doc/docx/rtf/txt 云端提取",
      });
    }
  } catch (e) {
    return res.status(502).json({ ok: false, error: "文档解析失败：" + e.message });
  }

  if (!extracted) {
    return res.status(422).json({ ok: false, error: "未能提取到可读文本" });
  }

  const cleanWithAI = ["1", "true", "yes", "on"].includes(
    String(req.body?.cleanWithAI ?? "1").trim().toLowerCase()
  );
  if (!cleanWithAI) {
    return res.json({ ok: true, text: extracted, source: "parser" });
  }

  const apiKey = getDeepseekKey();
  if (!apiKey) {
    return res.json({
      ok: true,
      text: extracted,
      source: "parser",
      note: "服务器未配置 DeepSeek，已返回解析原文",
    });
  }
  const quota = await preflightAIQuota(sub);
  if (!quota.ok) {
    return res.json({
      ok: true,
      text: extracted,
      source: "parser",
      note: "AI 额度不足，已返回解析原文",
      credits: quota.credits,
    });
  }
  let creditsAfter = quota.credits;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 90000);
  try {
    const prompt = [
      "你是文档文本清洗助手。",
      "请在不改动原意的前提下，修复明显乱码、去掉无意义符号，尽量保留原文结构。",
      "若内容本来正常，请原样返回。",
      "",
      "【文档原文开始】",
      extracted.slice(0, 120000),
      "【文档原文结束】",
    ].join("\n");

    const dr = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer " + apiKey,
      },
      body: JSON.stringify({
        model: "deepseek-chat",
        messages: [
          { role: "system", content: "你只输出清洗后的正文文本，不要解释。" },
          { role: "user", content: prompt },
        ],
        temperature: 0.1,
      }),
      signal: controller.signal,
    });
    const raw = await dr.text();
    if (!dr.ok) {
      return res.json({ ok: true, text: extracted, source: "parser", note: "AI清洗失败，已回退原文" });
    }
    const parsed = JSON.parse(raw);
    const content = String(parsed?.choices?.[0]?.message?.content || "").trim();
    if (!content) {
      return res.json({ ok: true, text: extracted, source: "parser", note: "AI无输出，已回退原文" });
    }
    const usage = normalizeModelUsage(parsed.usage);
    const unitsCharged = usageUnitsFromTokens(usage.totalTokens);
    const charged = await consumeCreditsInternal(sub, unitsCharged, {
      allowOverage: true,
      usageLog: {
        feature: "import_extract_text_clean",
        model: "deepseek-chat",
        usage,
      },
    });
    if (charged.ok) {
      creditsAfter = charged.credits;
    }
    return res.json({
      ok: true,
      text: content,
      source: "ai",
      credits: creditsAfter,
      usage: {
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        totalTokens: usage.totalTokens,
        unitsCharged,
      },
    });
  } catch (e) {
    return res.json({ ok: true, text: extracted, source: "parser", note: "AI异常，已回退原文" });
  } finally {
    clearTimeout(timer);
  }
});

/**
 * POST /v1/import/parse-notice
 * Bearer accessToken；把已提取正文结构化为通知单草稿字段，按模型 usage 折算 AI 点数。
 * Body: { text, fileName? }
 */
app.post("/v1/import/parse-notice", analyzeLimiter, async (req, res) => {
  const sub = bearerToken(req);
  if (!sub) {
    return res.status(401).json({ ok: false, error: "需要 Bearer accessToken" });
  }

  const apiKey = getDeepseekKey();
  if (!apiKey) {
    return res.status(503).json({
      ok: false,
      error: "服务器未配置 DeepSeek：请在环境变量 DEEPSEEK_API_KEY 或 config.json 的 deepseekApiKey 中填写密钥",
    });
  }

  const quota = await preflightAIQuota(sub);
  if (!quota.ok) {
    return res.status(quota.statusCode).json({
      ok: false,
      error: quota.errorMessage,
      credits: quota.credits,
    });
  }
  let creditsAfter = quota.credits;

  const fileName = clampStr(req.body?.fileName ?? "", 300).trim();
  const text = clampStr(req.body?.text ?? "", 60000).trim();
  if (!text) {
    return res.status(400).json({ ok: false, error: "缺少可识别正文 text" });
  }

  const systemPrompt = [
    "你是施工安全资料员助手，负责从安全隐患整改通知单、检查通知、整改回复或排查报告中抽取结构化字段。",
    "只输出 JSON，不要解释，不要 Markdown。",
    "不要编造原文没有的信息；不确定就留空并在 warnings 说明。",
    "日期统一输出 yyyy-MM-dd；通知编号保留原文格式。",
  ].join("\n");
  const userPrompt = [
    "请从下面文档中提取字段，输出 JSON：",
    "{",
    '  "documentType": "hazardNotice|rectificationReply|inspectionRecord|meetingMinutes|unknown",',
    '  "projectName": "项目/工程名称",',
    '  "issuer": "发文单位/检查单位/下发单位",',
    '  "inspectedUnit": "被检查单位/受检单位/施工单位/项目部",',
    '  "noticeNo": "通知编号/文号/编号",',
    '  "noticeDate": "通知日期/检查日期/来文日期，yyyy-MM-dd",',
    '  "rectificationDeadline": "整改期限，yyyy-MM-dd；没有则空",',
    '  "legalBasis": "法律法规或标准依据；没有则空",',
    '  "summary": "一句话摘要",',
    '  "confidence": 0.0,',
    '  "warnings": ["需要人工核对的点"],',
    '  "hazards": [',
    '    { "location": "部位/地点", "description": "存在问题", "requirement": "整改要求", "dueDate": "yyyy-MM-dd", "responsibleParty": "责任单位/责任人" }',
    "  ]",
    "}",
    "",
    fileName ? `文件名：${fileName}` : "",
    "【文档正文开始】",
    text,
    "【文档正文结束】",
  ].filter(Boolean).join("\n");

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
        temperature: 0.1,
      }),
      signal: controller.signal,
    });

    const rawText = await dr.text();
    if (!dr.ok) {
      console.error("[import.parse-notice] HTTP", dr.status, rawText.slice(0, 600));
      return res.status(502).json({
        ok: false,
        error: "模型服务错误（HTTP " + dr.status + "）",
        credits: creditsAfter,
      });
    }

    let parsed;
    try {
      parsed = JSON.parse(rawText);
    } catch (e) {
      return res.status(502).json({ ok: false, error: "模型响应不是 JSON", credits: creditsAfter });
    }
    const content = String(parsed?.choices?.[0]?.message?.content || "").trim();
    if (!content) {
      return res.status(502).json({ ok: false, error: "模型未返回内容", credits: creditsAfter });
    }
    let obj;
    try {
      obj = JSON.parse(stripMarkdownJSONFence(content));
    } catch (e) {
      console.error("[import.parse-notice] 内容 JSON 解析失败", e.message, content.slice(0, 400));
      return res.status(502).json({ ok: false, error: "模型返回不是有效 JSON", credits: creditsAfter });
    }

    const usage = normalizeModelUsage(parsed.usage);
    const unitsCharged = usageUnitsFromTokens(usage.totalTokens);
    const charged = await consumeCreditsInternal(sub, unitsCharged, {
      allowOverage: true,
      usageLog: {
        feature: "import_parse_notice",
        model: "deepseek-chat",
        usage,
      },
    });
    if (charged.ok) {
      creditsAfter = charged.credits;
    }
    return res.json({
      ok: true,
      credits: creditsAfter,
      usage: {
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        totalTokens: usage.totalTokens,
        unitsCharged,
      },
      draft: normalizeNoticeDraft(obj),
    });
  } catch (e) {
    const msg = e.name === "AbortError" ? "模型请求超时" : e.message;
    console.error("[v1/import/parse-notice]", e);
    return res.status(502).json({
      ok: false,
      error: "通知单识别失败：" + msg,
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
      <li>GET /v1/me（Bearer；返回会员状态与每日剩余 AI 点数）</li>
      <li>POST /v1/auth/apple</li>
      <li>POST /v1/credits/consume（Bearer，开发接口：扣 AI 点数）</li>
      <li>POST /v1/subscription/mock/renew（Bearer，开发联调用：续期与重置配额）</li>
      <li>GET /v1/laws/status（法规库状态与目录）</li>
      <li>POST /v1/hazard/analyze（Bearer，服务端代调 DeepSeek，按 usage 折算 AI 点数）</li>
    </ul>`
  );
});

app.listen(port, "0.0.0.0", () => {
  console.log(`SafeMaster API 监听 http://0.0.0.0:${port} （dbMode=${dbMode}）`);
});
