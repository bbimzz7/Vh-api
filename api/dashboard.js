// /api/dashboard.js
// GET  ?secret=X&action=list
// POST { secret, action: "delete"|"resethwid"|"genkey", key?, count? }

const GITHUB_TOKEN  = process.env.GITHUB_TOKEN;
const GITHUB_REPO   = process.env.GITHUB_REPO;
const GITHUB_FILE   = process.env.GITHUB_FILE;
const ADMIN_SECRET  = process.env.ADMIN_SECRET;
const KEY_EXPIRE_MS = 24 * 60 * 60 * 1000;

import crypto from "crypto";

async function getKeys() {
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${GITHUB_FILE}`,
        { headers: { Authorization: `token ${GITHUB_TOKEN}`, "User-Agent": "vh-key-api" } }
    );
    if (!res.ok) return { keys: {}, sha: null };
    const data = await res.json();
    const content = JSON.parse(Buffer.from(data.content, "base64").toString("utf8"));
    return { keys: content, sha: data.sha };
}

async function saveKeys(keys, sha) {
    const content = Buffer.from(JSON.stringify(keys, null, 2)).toString("base64");
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${GITHUB_FILE}`,
        {
            method: "PUT",
            headers: {
                Authorization: `token ${GITHUB_TOKEN}`,
                "Content-Type": "application/json",
                "User-Agent": "vh-key-api",
            },
            body: JSON.stringify({ message: "dashboard update", content, sha }),
        }
    );
    return res.ok;
}

function generateKey() {
    const part = () => crypto.randomBytes(3).toString("hex").toUpperCase();
    return `VH-${part()}-${part()}-${part()}`;
}

export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.status(200).end();

    // Auth
    const secret = req.method === "GET"
        ? req.query.secret
        : (req.body || {}).secret;

    if (secret !== ADMIN_SECRET)
        return res.status(401).json({ error: "Unauthorized" });

    const action = req.method === "GET"
        ? req.query.action
        : (req.body || {}).action;

    try {
        const { keys, sha } = await getKeys();
        const now = Date.now();

        // ── LIST ──────────────────────────────────────
        if (action === "list") {
            const list = Object.entries(keys).map(([k, v]) => ({
                key:       k,
                expires:   v.expires,
                expired:   new Date(v.expires).getTime() < now,
                hwid:      v.hwid || null,
                boundAt:   v.boundAt || null,
                createdAt: v.createdAt || null,
            }));
            // Stats
            const total   = list.length;
            const active  = list.filter(x => !x.expired).length;
            const expired = list.filter(x => x.expired).length;
            const bound   = list.filter(x => x.hwid).length;
            return res.json({ keys: list, stats: { total, active, expired, bound } });
        }

        // ── DELETE ────────────────────────────────────
        if (action === "delete") {
            const key = (req.body.key || "").toUpperCase();
            if (!keys[key]) return res.json({ error: "Key tidak ditemukan" });
            delete keys[key];
            await saveKeys(keys, sha);
            return res.json({ success: true, message: `Key ${key} dihapus` });
        }

        // ── RESET HWID ────────────────────────────────
        if (action === "resethwid") {
            const key = (req.body.key || "").toUpperCase();
            if (!keys[key]) return res.json({ error: "Key tidak ditemukan" });
            keys[key].hwid    = null;
            keys[key].boundAt = null;
            await saveKeys(keys, sha);
            return res.json({ success: true, message: `HWID key ${key} direset` });
        }

        // ── GENERATE KEY ──────────────────────────────
        if (action === "genkey") {
            const count   = Math.min(Math.max(parseInt(req.body.count) || 1, 1), 50);
            const expires = new Date(now + KEY_EXPIRE_MS).toISOString();
            const generated = [];
            for (let i = 0; i < count; i++) {
                const key = generateKey();
                keys[key] = { expires, hwid: null, createdAt: new Date().toISOString() };
                generated.push(key);
            }
            await saveKeys(keys, sha);
            return res.json({ success: true, keys: generated, expires });
        }

        return res.status(400).json({ error: "Unknown action" });

    } catch (e) {
        return res.status(500).json({ error: "Server error: " + e.message });
    }
}
