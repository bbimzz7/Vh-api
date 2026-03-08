// GET /api/getkey?hwid=XXXX&username=XXXX&userId=XXXX
// Returns { key, expires, reused }

import crypto from "crypto";

const GITHUB_TOKEN  = process.env.GITHUB_TOKEN;
const GITHUB_REPO   = process.env.GITHUB_REPO;
const GITHUB_FILE   = process.env.GITHUB_FILE;
const CONFIG_FILE   = process.env.GITHUB_CONFIG_FILE || "config.json";
const KEY_EXPIRE_MS = 24 * 60 * 60 * 1000;

async function ghGet(file) {
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${file}`,
        { headers: { Authorization: `token ${GITHUB_TOKEN}`, "User-Agent": "vh-key-api", "Cache-Control": "no-cache" } }
    );
    if (!res.ok) return { data: {}, sha: null };
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
}

function generateKey() {
    const part = () => crypto.randomBytes(3).toString("hex").toUpperCase();
    return `VH-${part()}-${part()}-${part()}`;
}

function getTodayStr() {
    return new Date().toISOString().substring(0, 10);
}

export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    if (req.method === "OPTIONS") return res.status(200).end();
    if (req.method !== "GET")    return res.status(405).json({ error: "Method not allowed" });

    const hwid     = (req.query.hwid     || "").trim();
    const username = (req.query.username || "").trim();
    const userId   = (req.query.userId   || "").trim();

    if (!hwid)             return res.status(400).json({ error: "HWID tidak boleh kosong" });
    if (hwid.length > 128) return res.status(400).json({ error: "HWID tidak valid" });

    // Kalau dari browser (bukan fetch/script/HttpGet), redirect ke halaman web
    const userAgent = req.headers["user-agent"] || "";
    const accept    = req.headers["accept"] || "";
    const isBrowser = userAgent.includes("Mozilla") || userAgent.includes("Chrome") || userAgent.includes("Safari");
    const isScript  = userAgent.includes("Roblox") || userAgent.includes("vh-key") || req.headers["x-script"] === "1";
    const isFetch   = accept.includes("application/json") || req.headers["x-requested-with"] === "XMLHttpRequest";
    if (isBrowser && !isScript && !isFetch) {
        const params = new URLSearchParams({ hwid, ...(username && {username}), ...(userId && {userId}) });
        return res.redirect(302, `/?${params.toString()}`);
    }

    try {
        // Load keys + config secara paralel
        const [{ data: keys, sha: keysSha }, { data: config }] = await Promise.all([
            ghGet(GITHUB_FILE),
            ghGet(CONFIG_FILE),
        ]);

        const now     = Date.now();
        const today   = getTodayStr();

        // Ambil limit dari config (default unlimited jika belum diset)
        const maxPerDay   = config.maxPerDay   || 0; // 0 = unlimited
        const maxTotal    = config.maxTotal    || 0; // 0 = unlimited

        // Hitung stats
        const allKeys     = Object.values(keys);
        const totalActive = allKeys.filter(v => new Date(v.expires).getTime() > now).length;
        const todayCount  = allKeys.filter(v => (v.createdAt || "").startsWith(today)).length;

        // Cek apakah HWID sudah punya key aktif → return key yang sama + update username
        for (const [k, v] of Object.entries(keys)) {
            if (v.hwid === hwid && new Date(v.expires).getTime() > now) {
                // Update username & userId kalau ada yang baru
                let updated = false;
                if (username && v.username !== username) { keys[k].username = username; updated = true; }
                if (userId   && v.userId   !== userId)   { keys[k].userId   = userId;   updated = true; }
                if (updated) await ghPut(GITHUB_FILE, keys, keysSha, "update username");
                return res.json({ key: k, expires: v.expires, reused: true });
            }
        }

        // Cek limit total
        if (maxTotal > 0 && totalActive >= maxTotal) {
            return res.status(429).json({
                error: `Limit tercapai! Max ${maxTotal} key aktif. Coba lagi nanti.`
            });
        }

        // Cek limit per hari
        if (maxPerDay > 0 && todayCount >= maxPerDay) {
            return res.status(429).json({
                error: `Limit harian tercapai! Max ${maxPerDay} key per hari. Coba besok.`
            });
        }

        // Generate key baru
        let key;
        do { key = generateKey(); } while (keys[key]);

        const expires = new Date(now + KEY_EXPIRE_MS).toISOString();
        keys[key] = {
            expires,
            hwid,
            username:  username || null,
            userId:    userId   || null,
            createdAt: new Date().toISOString(),
        };

        await ghPut(GITHUB_FILE, keys, keysSha, "generate key via getkey");
        return res.json({ key, expires, reused: false });

    } catch (e) {
        console.error("[getkey] Error:", e.message);
        return res.status(500).json({ error: "Server error, coba lagi" });
    }
}
