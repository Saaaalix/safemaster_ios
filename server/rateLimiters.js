const rateLimit = require("express-rate-limit");

function parsePositiveInt(raw, fallback) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.floor(n);
}

function makeLimiter({ windowMs, max, message }) {
  return rateLimit({
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      ok: false,
      error: message,
    },
  });
}

function buildRateLimiters(fileConfig = {}) {
  return {
    authLimiter: makeLimiter({
      windowMs: parsePositiveInt(
        process.env.RATE_LIMIT_AUTH_WINDOW_MS ?? fileConfig.rateLimitAuthWindowMs,
        15 * 60 * 1000
      ),
      max: parsePositiveInt(
        process.env.RATE_LIMIT_AUTH_MAX ?? fileConfig.rateLimitAuthMax,
        40
      ),
      message: "登录请求过于频繁，请稍后再试。",
    }),
    analyzeLimiter: makeLimiter({
      windowMs: parsePositiveInt(
        process.env.RATE_LIMIT_ANALYZE_WINDOW_MS ?? fileConfig.rateLimitAnalyzeWindowMs,
        5 * 60 * 1000
      ),
      max: parsePositiveInt(
        process.env.RATE_LIMIT_ANALYZE_MAX ?? fileConfig.rateLimitAnalyzeMax,
        20
      ),
      message: "分析请求过于频繁，请稍后再试。",
    }),
    creditsLimiter: makeLimiter({
      windowMs: parsePositiveInt(
        process.env.RATE_LIMIT_CREDITS_WINDOW_MS ?? fileConfig.rateLimitCreditsWindowMs,
        5 * 60 * 1000
      ),
      max: parsePositiveInt(
        process.env.RATE_LIMIT_CREDITS_MAX ?? fileConfig.rateLimitCreditsMax,
        60
      ),
      message: "请求过于频繁，请稍后再试。",
    }),
  };
}

module.exports = {
  buildRateLimiters,
};
