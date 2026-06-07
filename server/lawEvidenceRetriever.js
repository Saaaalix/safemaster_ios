const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const CJK_STOP_UNIGRAMS = new Set([
  "的", "了", "在", "是", "和", "与", "及", "或", "等", "应", "将", "对", "为", "以", "中", "有", "不", "可", "需", "须", "宜", "并", "其", "该", "此", "均", "所", "由", "被", "于", "而", "之", "也", "又", "若", "则", "但", "如", "即",
]);

const DOMAIN_KEYWORDS = {
  construction: [
    "建筑", "施工", "工地", "施工现场", "基坑", "脚手架", "高处", "临边", "洞口",
    "塔吊", "起重", "临时用电", "配电箱", "模板", "钢筋", "宿舍", "办公区", "安全网",
  ],
  chemical: [
    "化工", "危化", "危险化学品", "化学品", "生产装置", "储罐", "罐区", "反应釜", "工艺管道",
    "泄漏", "有毒", "有害", "易燃", "可燃", "爆炸", "石化", "化工过程",
  ],
};

const HARD_EXCLUDE_FOR_CONSTRUCTION = [
  "危险化学品",
  "危化",
  "化工",
  "石油化工",
  "化工过程",
  "储罐",
  "反应釜",
  "罐区",
];

const TOPIC_HINTS = [
  {
    name: "electrical",
    queryKeywords: ["电", "电缆", "充电", "漏电", "短路", "触电", "插座", "配电", "导线", "绝缘"],
    recordKeywords: ["电", "电缆", "触电", "漏电", "短路", "配电", "接地", "绝缘", "临时用电", "开关箱", "电气"],
  },
  {
    name: "fire",
    queryKeywords: ["火灾", "起火", "燃烧", "明火", "动火", "可燃", "易燃", "消防"],
    recordKeywords: ["火灾", "消防", "灭火", "动火", "易燃", "可燃", "防火", "火警"],
  },
  {
    name: "height",
    queryKeywords: ["高处", "临边", "洞口", "坠落", "脚手架", "安全带", "防护栏杆"],
    recordKeywords: ["高处", "临边", "洞口", "坠落", "脚手架", "栏杆", "安全带", "防护网"],
  },
];

function isDormChargingCableHazard(query) {
  const q = normalize(query);
  const hasDorm = ["宿舍", "生活区", "寝室"].some((w) => q.includes(normalize(w)));
  const hasCable = ["充电线", "电线", "导线", "线缆", "插排"].some((w) => q.includes(normalize(w)));
  const hasDamage = ["破损", "裸露", "老化", "破皮", "损坏"].some((w) => q.includes(normalize(w)));
  const hasRisk = ["触电", "短路", "火灾", "漏电"].some((w) => q.includes(normalize(w)));
  return hasCable && hasDamage && (hasDorm || hasRisk);
}

function normalize(s) {
  const raw = typeof s === "string" ? s : "";
  return raw
    .replace(/\u3000/g, " ")
    .replace(/\u00a0/g, " ")
    .trim()
    .split(/\s+/)
    .join(" ")
    .toLowerCase();
}

function normalizeDomainValue(raw) {
  const t = normalize(String(raw || ""));
  if (!t) return "construction";
  if (t.includes("all") || t.includes("全部") || t.includes("通用")) return "all";
  if (t.includes("chemical") || t.includes("化工") || t.includes("危化")) return "chemical";
  if (t.includes("construction") || t.includes("建筑") || t.includes("施工")) return "construction";
  return "construction";
}

function domainScore(blob, words) {
  let score = 0;
  for (const w of words) {
    if (blob.includes(normalize(w))) score += 1;
  }
  return score;
}

function recordBlob(rec) {
  const parts = [
    rec.law_name,
    rec.chapter,
    rec.article_title,
    rec.article_no,
    rec.title,
    rec.text,
    rec.search_text,
    ...(Array.isArray(rec.scene_tags) ? rec.scene_tags : []),
    ...(Array.isArray(rec.keywords) ? rec.keywords : []),
  ];
  return normalize(parts.join(" "));
}

function detectTopics(query) {
  const q = normalize(query);
  if (!q) return [];
  const topics = [];
  for (const t of TOPIC_HINTS) {
    if (t.queryKeywords.some((w) => q.includes(normalize(w)))) {
      topics.push(t);
    }
  }
  return topics;
}

function matchTopic(rec, topic) {
  const blob = recordBlob(rec);
  return topic.recordKeywords.some((w) => blob.includes(normalize(w)));
}

function matchDomain(rec, domain) {
  if (domain === "all") return true;
  const blob = recordBlob(rec);
  if (domain === "construction") {
    for (const w of HARD_EXCLUDE_FOR_CONSTRUCTION) {
      if (blob.includes(normalize(w))) return false;
    }
  }
  const cScore = domainScore(blob, DOMAIN_KEYWORDS.construction);
  const hScore = domainScore(blob, DOMAIN_KEYWORDS.chemical);

  if (domain === "construction") {
    if (hScore >= 2 && cScore === 0) return false;
    return cScore > 0 || hScore === 0;
  }
  if (domain === "chemical") {
    if (cScore >= 2 && hScore === 0) return false;
    return hScore > 0 || cScore === 0;
  }
  return true;
}

function filterByDomain(rows, domain) {
  const d = normalizeDomainValue(domain);
  if (d === "all") return rows;
  return rows.filter((r) => matchDomain(r, d));
}

function filterByTopics(rows, query) {
  const topics = detectTopics(query);
  if (topics.length === 0) return rows;
  const filtered = rows.filter((rec) => topics.some((t) => matchTopic(rec, t)));
  // 避免过窄导致空结果：若筛完过少则回退原集合。
  if (filtered.length < 3) return rows;
  return filtered;
}

function forceElectricalRowsForDormCable(rows, query) {
  if (!isDormChargingCableHazard(query)) return rows;
  const keepWords = ["临时用电", "用电", "电气", "触电", "漏电", "绝缘", "线路", "配电"];
  const out = rows.filter((r) => {
    const blob = recordBlob(r);
    return keepWords.some((w) => blob.includes(normalize(w)));
  });
  // 仍保留回退，避免极端数据集导致空集合。
  return out.length >= 3 ? out : rows;
}

function contextualExclude(rec, query) {
  const q = normalize(query);
  const titleBlob = normalize(`${rec.law_name || ""} ${rec.chapter || ""} ${rec.title || ""}`);

  if (titleBlob.includes("起重机械")) {
    const liftWords = ["起重", "吊装", "塔吊", "吊车", "吊钩", "钢丝绳"];
    if (!liftWords.some((w) => q.includes(normalize(w)))) return true;
  }
  if (titleBlob.includes("基坑")) {
    const pitWords = ["基坑", "支护", "开挖", "土方", "围护"];
    if (!pitWords.some((w) => q.includes(normalize(w)))) return true;
  }
  if (titleBlob.includes("hazop") || titleBlob.includes("危险与可操作性")) {
    const hazopWords = ["hazop", "化工", "工艺", "偏差", "引导词"];
    if (!hazopWords.some((w) => q.includes(normalize(w)))) return true;
  }
  if (titleBlob.includes("个体防护装备术语")) {
    const ppeWords = ["个体防护", "防护装备", "ppe", "安全帽", "防护服"];
    if (!ppeWords.some((w) => q.includes(normalize(w)))) return true;
  }
  if (titleBlob.includes("绿色施工评价标准")) {
    const greenWords = ["扬尘", "噪声", "节能", "节水", "绿色施工", "环保"];
    if (!greenWords.some((w) => q.includes(normalize(w)))) return true;
  }
  return false;
}

function tokenizeQuery(query) {
  const n = normalize(query);
  if (!n) return [];

  const out = [];
  const seen = new Set();
  const maxTerms = 160;
  const add = (s) => {
    if (!s || out.length >= maxTerms) return;
    if (s.length === 1) {
      const ch = s[0];
      if (!/[\u4e00-\u9fff]/.test(ch)) return;
      if (CJK_STOP_UNIGRAMS.has(ch)) return;
    }
    if (!seen.has(s)) {
      seen.add(s);
      out.push(s);
    }
  };

  const ascii = n.match(/[a-z0-9][a-z0-9\-.]*/g) || [];
  ascii.forEach(add);

  const cjkRuns = n.match(/[\u4e00-\u9fff]+/g) || [];
  for (const run of cjkRuns) {
    const chars = Array.from(run);
    const L = chars.length;
    if (L <= 10) add(run);
    for (let i = 0; i + 1 < L; i += 1) add(chars[i] + chars[i + 1]);
    for (let i = 0; i + 2 < L; i += 1) add(chars[i] + chars[i + 1] + chars[i + 2]);
  }
  return out;
}

function termCount(text, term) {
  if (!text || !term) return 0;
  let count = 0;
  let start = 0;
  while (start < text.length) {
    const idx = text.indexOf(term, start);
    if (idx < 0) break;
    count += 1;
    start = idx + term.length;
  }
  return count;
}

function scoreRecord(rec, terms) {
  const searchText = normalize(rec.search_text);
  if (!searchText) return 0;

  const kw = Array.isArray(rec.keywords) ? rec.keywords.map(normalize) : [];
  const tags = Array.isArray(rec.scene_tags) ? rec.scene_tags.map(normalize) : [];
  const title = normalize(rec.title);
  let score = 0;

  for (const t of terms) {
    const c = termCount(searchText, t);
    if (c > 0) score += 1.8 * (1 + Math.log(1 + c));
    if (title.includes(t)) score += 1.2;
    if (kw.some((k) => t.includes(k) || k.includes(t))) score += 1.0;
    if (tags.some((k) => t.includes(k) || k.includes(t))) score += 1.0;
  }

  const pr = Number.isFinite(rec.priority) ? rec.priority : 2;
  if (pr === 3) score += 1.0;
  else if (pr !== 1) score += 0.6;
  return score;
}

function emphasisBonusTerms(raw) {
  const trimmed = String(raw || "").trim();
  if (!trimmed) return [];
  const seen = new Set();
  const out = [];
  const push = (s) => {
    const n = normalize(s);
    if (n.length < 2 || seen.has(n)) return;
    seen.add(n);
    out.push(n);
  };

  tokenizeQuery(trimmed).forEach(push);
  const low = normalize(trimmed);
  if (low.includes("锁") || low.includes("箱门") || low.includes("未锁") || low.includes("闭合") || low.includes("敞开")) {
    ["上锁", "关门", "配锁"].forEach(push);
  }
  if (low.includes("缆") || low.includes("杂乱") || low.includes("拖地") || low.includes("绞绕")) {
    ["明设", "地面", "敷设", "机械损伤"].forEach(push);
  }
  return out;
}

function userEmphasisMatchBonus(rec, emphTerms) {
  if (!Array.isArray(emphTerms) || emphTerms.length === 0) return 0;
  const blob = normalize(`${rec.search_text || ""} ${rec.text || ""}`);
  let bonus = 0;
  for (const t of emphTerms) {
    if (t.length >= 2 && blob.includes(t)) bonus += 4.0;
  }
  return Math.min(bonus, 30.0);
}

function priorityFallbackPrefix(all, topK) {
  return [...all]
    .sort((a, b) => (Number(b.priority || 2) - Number(a.priority || 2)))
    .slice(0, topK);
}

function rankAndTopK(all, query, userEmphasis, topK) {
  const k = Math.max(1, Math.min(Number(topK) || 1, 28));
  if (!Array.isArray(all) || all.length === 0) return [];
  const terms = tokenizeQuery(query);
  if (terms.length === 0) return all.slice(0, k);
  const emphTerms = emphasisBonusTerms(userEmphasis);

  const scored = [];
  for (const rec of all) {
    let s = scoreRecord(rec, terms);
    if (emphTerms.length > 0) s += userEmphasisMatchBonus(rec, emphTerms);
    if (s > 0) scored.push([s, rec]);
  }

  if (scored.length === 0) {
    const hasCJK = terms.some((t) => t.length >= 2 && /[\u4e00-\u9fff]/.test(t));
    return hasCJK ? priorityFallbackPrefix(all, k) : [];
  }

  scored.sort((a, b) => b[0] - a[0]);
  const bestScore = scored[0][0];
  const floorScore = Math.max(2.2, bestScore * 0.38);
  const seen = new Set();
  const seenSignature = new Set();
  const out = [];
  for (const [, rec] of scored) {
    if (contextualExclude(rec, query)) continue;
    const sig = normalize(`${rec.law_name || ""}|${rec.article_no || ""}|${rec.article_title || ""}`);
    if (sig && seenSignature.has(sig)) continue;
    const score = scoreRecord(rec, terms) + (emphTerms.length > 0 ? userEmphasisMatchBonus(rec, emphTerms) : 0);
    if (score < floorScore) continue;
    if (!rec || !rec.id || seen.has(rec.id)) continue;
    seen.add(rec.id);
    if (sig) seenSignature.add(sig);
    out.push(rec);
    if (out.length >= k) break;
  }
  if (out.length === 0) {
    // 保底给 1-2 条最相关，避免完全空导致模型胡编。
    const fallback = scored.slice(0, Math.min(2, scored.length)).map((x) => x[1]);
    return fallback;
  }
  return out;
}

function formatPlaybookBlock(rows) {
  if (!rows || rows.length === 0) {
    return [
      "【安全操作准则匹配】（最高优先级 · 整改措施）",
      "（本段无命中：请结合现场与通用施工安全要求提出整改措施。）",
    ].join("\n");
  }
  const lines = [
    "【安全操作准则匹配】（最高优先级 · 整改措施）",
    "编写 hazard_description 与 rectification_measures 时，必须优先下列条目中的「操作要求」「检查要点」与逻辑说明，可改写为分条措施但不要改变安全含义。",
    "",
  ];
  rows.forEach((r, idx) => {
    lines.push(`[P${idx + 1}] ${r.chapter || ""} · ${r.article_title || ""}`);
    if (String(r.article_no || "").trim()) lines.push(`要点：${String(r.article_no).trim()}`);
    lines.push(`内容：「${String(r.text || "").trim()}」`);
    lines.push("");
  });
  return lines.join("\n");
}

function formatBasisBlock(rows) {
  if (!rows || rows.length === 0) {
    return [
      "【法规条文依据】（整改依据）",
      "（无匹配条目：legal_basis 中请说明内置法规库未命中，仅可建议对照的规范主题方向，禁止编造条号与原文。）",
    ].join("\n");
  }
  const lines = [
    "【法规条文依据】（整改依据）",
    "legal_basis 必须仅引用本段中的规范原文；使用证据编号 [E1]、[E2]… 与下列条文对应。不得把「建筑安全操作准则」当作国家法律或强制性标准条文引用。",
    "若用户或画面涉及箱门未锁、电缆拖地等，应优先引用本段中**语义可对应**的条文（如「关门上锁」对应箱门未闭、「严禁沿地面明设」对应电缆拖地），并在 legal_basis 中简要说明对应关系；勿因条文未逐字出现「配电箱」「锁闭」而拒引。避免仅用三级配电间距、漏保额定值等与本次可见现象无关的条目凑数。",
    "",
  ];
  rows.forEach((r, idx) => {
    const name = r.law_name || "（未知规范）";
    const no = r.article_no ? `条文编号：${r.article_no}` : "";
    lines.push(`[E${idx + 1}] 《${name}》${no}`);
    if (String(r.chapter || "").trim()) lines.push(`章节：${String(r.chapter).trim()}`);
    lines.push(`原文：「${String(r.text || "").trim()}」`);
    lines.push("");
  });
  return lines.join("\n");
}

function parseJsonlBuffer(buf) {
  const text = buf.toString("utf8");
  const lines = text.split(/\r?\n/);
  const rows = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      rows.push(JSON.parse(trimmed));
    } catch (_) {
      // ignore malformed line
    }
  }
  return rows;
}

function resolveLawFile(dir, baseName) {
  const plain = path.join(dir, `${baseName}.jsonl`);
  if (fs.existsSync(plain)) return { path: plain, gzip: false };
  const gz = path.join(dir, `${baseName}.jsonl.gz`);
  if (fs.existsSync(gz)) return { path: gz, gzip: true };
  return null;
}

class LawEvidenceRetriever {
  constructor(options = {}) {
    const configuredDir = String(options.lawsDir || "").trim();
    this.lawsDir = configuredDir || path.join(__dirname, "laws");
    this.cache = {
      playbook: null,
      basis: null,
      meta: {
        playbook: null,
        basis: null,
      },
    };
  }

  getStatus() {
    const pb = resolveLawFile(this.lawsDir, "laws_playbook");
    const bs = resolveLawFile(this.lawsDir, "laws_basis");
    return {
      lawsDir: this.lawsDir,
      playbookFile: pb ? path.basename(pb.path) : null,
      basisFile: bs ? path.basename(bs.path) : null,
      playbookLoaded: Array.isArray(this.cache.playbook),
      basisLoaded: Array.isArray(this.cache.basis),
      playbookCount: this.cache.playbook?.length ?? 0,
      basisCount: this.cache.basis?.length ?? 0,
    };
  }

  ensureLoaded(kind) {
    const baseName = kind === "basis" ? "laws_basis" : "laws_playbook";
    const resolved = resolveLawFile(this.lawsDir, baseName);
    if (!resolved) {
      throw new Error(`未找到 ${baseName}.jsonl 或 ${baseName}.jsonl.gz（目录：${this.lawsDir}）`);
    }

    const st = fs.statSync(resolved.path);
    const oldMeta = this.cache.meta[kind];
    const unchanged = oldMeta
      && oldMeta.path === resolved.path
      && oldMeta.mtimeMs === st.mtimeMs
      && oldMeta.size === st.size
      && Array.isArray(this.cache[kind]);
    if (unchanged) return this.cache[kind];

    const raw = fs.readFileSync(resolved.path);
    const buf = resolved.gzip ? zlib.gunzipSync(raw) : raw;
    const rows = parseJsonlBuffer(buf);
    this.cache[kind] = rows;
    this.cache.meta[kind] = {
      path: resolved.path,
      mtimeMs: st.mtimeMs,
      size: st.size,
    };
    return rows;
  }

  retrieveBlocks({ query, userEmphasis = "", playbookTopK = 8, basisTopK = 12, domain = "construction" }) {
    const playbookAll = this.ensureLoaded("playbook");
    const basisAll = this.ensureLoaded("basis");
    const playbookDomainRows = forceElectricalRowsForDormCable(
      filterByTopics(filterByDomain(playbookAll, domain), query),
      query
    );
    const basisDomainRows = forceElectricalRowsForDormCable(
      filterByTopics(filterByDomain(basisAll, domain), query),
      query
    );
    const k = String(userEmphasis || "").trim() ? Math.max(6, basisTopK) : basisTopK;
    const playbookRows = rankAndTopK(playbookDomainRows, query, "", playbookTopK);
    const basisRows = rankAndTopK(basisDomainRows, query, userEmphasis, k);
    return {
      playbookRows,
      basisRows,
      playbookBlock: formatPlaybookBlock(playbookRows),
      basisBlock: formatBasisBlock(basisRows),
    };
  }
}

module.exports = { LawEvidenceRetriever };
