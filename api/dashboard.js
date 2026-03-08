// /api/dashboard.js
// GET  ?secret=X&action=list|logs
// POST { secret, action: "delete"|"resethwid"|"genkey"|"extend"|"bulkdelete", ... }

const GITHUB_TOKEN  = process.env.GITHUB_TOKEN;
const GITHUB_REPO   = process.env.GITHUB_REPO;
const GITHUB_FILE   = process.env.GITHUB_FILE;
const LOG_FILE      = process.env.GITHUB_LOG_FILE || "logs.json"; // file log terpisah
const ADMIN_SECRET  = process.env.ADMIN_SECRET;

import crypto from "crypto";

// ── GitHub helpers ─────────────────────────────────────────
async function ghGet(file) {
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${file}`,
        { headers: { Authorization: `token ${GITHUB_TOKEN}`, "User-Agent": "vh-key-api", "Cache-Control": "no-cache" } }
    );
    if (!res.ok) return { data: file.endsWith(".json") ? {} : [], sha: null };
    const json = await res.json();
    const content = JSON.parse(Buffer.from(json.content, "base64").toString("utf8"));
    return { data: content, sha: json.sha };
}

async function ghPut(file, data, sha, message) {
    const content = Buffer.from(JSON.stringify(data, null, 2)).toString("base64");
    const body = { message, content };
    if (sha) body.sha = sha;
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${file}`,
        {
            method: "PUT",
            headers: { Authorization: `token ${GITHUB_TOKEN}`, "Content-Type": "application/json", "User-Agent": "vh-key-api" },
            body: JSON.stringify(body),
        }
    );
    if (res.status === 409) throw new Error("Konflik data, coba lagi");
    if (!res.ok) throw new Error("Gagal simpan ke GitHub");
    return res.ok;
}

function generateKey() {
    const part = () => crypto.randomBytes(3).toString("hex").toUpperCase();
    return `VH-${part()}-${part()}-${part()}`;
}

// ── Log helper ─────────────────────────────────────────────
async function addLog(action, detail) {
    try {
        const { data: logs, sha } = await ghGet(LOG_FILE);
        const arr = Array.isArray(logs) ? logs : [];
        arr.unshift({ ts: new Date().toISOString(), action, detail });
        // Simpan max 200 log terakhir
        const trimmed = arr.slice(0, 200);
        await ghPut(LOG_FILE, trimmed, sha, "add log");
    } catch(e) {
        // Log gagal gak perlu throw, jangan sampai ganggu operasi utama
        console.error("[log] Failed:", e.message);
    }
}

// ── Auth helper ────────────────────────────────────────────
function authOk(secret) {
    if (!secret || !ADMIN_SECRET) return false;
    try {
        const a = Buffer.from(secret.padEnd(64).slice(0, 64));
        const b = Buffer.from(ADMIN_SECRET.padEnd(64).slice(0, 64));
        return crypto.timingSafeEqual(a, b);
    } catch { return false; }
}

// ── Handler ────────────────────────────────────────────────
export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.status(200).end();

    const secret = req.method === "GET" ? req.query.secret : (req.body || {}).secret;
    if (!authOk(secret)) return res.status(401).json({ error: "Unauthorized" });

    const action = req.method === "GET" ? req.query.action : (req.body || {}).action;

    try {
        const now = Date.now();

        // ── LIST ──────────────────────────────────────────
        if (action === "list") {
            const { data: keys } = await ghGet(GITHUB_FILE);
            const list = Object.entries(keys).map(([k, v]) => ({
                key:       k,
                expires:   v.expires,
                expired:   new Date(v.expires).getTime() < now,
                hwid:      v.hwid || null,
                boundAt:   v.boundAt || null,
                createdAt: v.createdAt || null,
                lastUsed:  v.lastUsed || null,
                label:     v.label || null,
            }));
            const total   = list.length;
            const active  = list.filter(x => !x.expired).length;
            const expired = list.filter(x => x.expired).length;
            const bound   = list.filter(x => x.hwid).length;
            return res.json({ keys: list, stats: { total, active, expired, bound } });
        }

        // ── LOGS ──────────────────────────────────────────
        if (action === "logs") {
            const { data: logs } = await ghGet(LOG_FILE);
            return res.json({ logs: Array.isArray(logs) ? logs : [] });
        }

        // ── DELETE ────────────────────────────────────────
        if (action === "delete") {
            const key = (req.body.key || "").toUpperCase();
            const { data: keys, sha } = await ghGet(GITHUB_FILE);
            if (!keys[key]) return res.json({ error: "Key tidak ditemukan" });
            delete keys[key];
            await ghPut(GITHUB_FILE, keys, sha, "delete key");
            addLog("delete", `Key ${key} dihapus`);
            return res.json({ success: true });
        }

        // ── BULK DELETE EXPIRED ───────────────────────────
        if (action === "bulkdelete") {
            const { data: keys, sha } = await ghGet(GITHUB_FILE);
            let count = 0;
            for (const [k, v] of Object.entries(keys)) {
                if (new Date(v.expires).getTime() < now) {
                    delete keys[k];
                    count++;
                }
            }
            if (count > 0) await ghPut(GITHUB_FILE, keys, sha, "bulk delete expired");
            addLog("bulkdelete", `${count} key expired dihapus`);
            return res.json({ success: true, deleted: count });
        }

        // ── RESET HWID ────────────────────────────────────
        if (action === "resethwid") {
            const key = (req.body.key || "").toUpperCase();
            const { data: keys, sha } = await ghGet(GITHUB_FILE);
            if (!keys[key]) return res.json({ error: "Key tidak ditemukan" });
            keys[key].hwid    = null;
            keys[key].boundAt = null;
            await ghPut(GITHUB_FILE, keys, sha, "reset hwid");
            addLog("resethwid", `HWID key ${key} direset`);
            return res.json({ success: true });
        }

        // ── EXTEND EXPIRY ─────────────────────────────────
        if (action === "extend") {
            const key  = (req.body.key || "").toUpperCase();
            const days = Math.min(Math.max(parseInt(req.body.days) || 1, 1), 30);
            const { data: keys, sha } = await ghGet(GITHUB_FILE);
            if (!keys[key]) return res.json({ error: "Key tidak ditemukan" });
            // Extend dari sekarang atau dari expiry yang ada (ambil yang lebih besar)
            const currentExpiry = new Date(keys[key].expires).getTime();
            const base = Math.max(currentExpiry, now);
            keys[key].expires = new Date(base + days * 24 * 60 * 60 * 1000).toISOString();
            await ghPut(GITHUB_FILE, keys, sha, "extend key expiry");
            addLog("extend", `Key ${key} diperpanjang ${days} hari`);
            return res.json({ success: true, expires: keys[key].expires });
        }

        // ── GENERATE KEY ──────────────────────────────────
        if (action === "genkey") {
            // [BUG FIX] Baca expireDays dari body, jangan hardcode
            const count      = Math.min(Math.max(parseInt(req.body.count) || 1, 1), 50);
            const expireDays = Math.min(Math.max(parseInt(req.body.expireDays) || 1, 1), 30);
            const expireMs   = expireDays * 24 * 60 * 60 * 1000;
            const expires    = new Date(now + expireMs).toISOString();

            const { data: keys, sha } = await ghGet(GITHUB_FILE);
            const generated = [];
            for (let i = 0; i < count; i++) {
                let key;
                do { key = generateKey(); } while (keys[key]);
                keys[key] = { expires, hwid: null, createdAt: new Date().toISOString() };
                generated.push(key);
            }
            await ghPut(GITHUB_FILE, keys, sha, "generate keys");
            addLog("genkey", `${count} key dibuat, expire ${expireDays} hari`);
            return res.json({ success: true, keys: generated, expires, expireDays });
        }

        return res.status(400).json({ error: "Unknown action" });

    } catch (e) {
        console.error("[dashboard] Error:", e.message);
        return res.status(500).json({ error: "Server error: " + e.message });
    }
}
