// POST /api/genkey
// Body: { secret: "ADMIN_SECRET", hwid?: "optional", count?: 1, expireDays?: 1 }
// Returns { keys: ["KEY1", "KEY2"], expires }

import crypto from "crypto";

const GITHUB_TOKEN  = process.env.GITHUB_TOKEN;
const GITHUB_REPO   = process.env.GITHUB_REPO;
const GITHUB_FILE   = process.env.GITHUB_FILE;
const ADMIN_SECRET  = process.env.ADMIN_SECRET;

async function getKeys() {
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${GITHUB_FILE}`,
        { headers: { Authorization: `token ${GITHUB_TOKEN}`, "User-Agent": "vh-key-api", "Cache-Control": "no-cache" } }
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
            body: JSON.stringify({ message: "generate keys", content, sha }),
        }
    );
    if (res.status === 409) throw new Error("Konflik data, coba lagi");
    if (!res.ok) throw new Error("Gagal simpan ke GitHub");
    return true;
}

function generateKey() {
    const part = () => crypto.randomBytes(3).toString("hex").toUpperCase();
    return `VH-${part()}-${part()}-${part()}`;
}

export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.status(200).end();
    if (req.method !== "POST")   return res.status(405).json({ error: "Method not allowed" });

    // [FIX] Constant-time comparison biar gak timing attack
    const { secret, hwid, count = 1, expireDays = 1 } = req.body || {};

    if (!secret || !ADMIN_SECRET) return res.status(401).json({ error: "Unauthorized" });

    const secretBuf = Buffer.from(secret.padEnd(64));
    const adminBuf  = Buffer.from(ADMIN_SECRET.padEnd(64));
    if (!crypto.timingSafeEqual(secretBuf.slice(0, 64), adminBuf.slice(0, 64))) {
        return res.status(401).json({ error: "Unauthorized" });
    }

    const num     = Math.min(Math.max(parseInt(count) || 1, 1), 50);
    // [NEW] Bisa custom durasi expiry (max 30 hari)
    const days    = Math.min(Math.max(parseInt(expireDays) || 1, 1), 30);
    const expireMs = days * 24 * 60 * 60 * 1000;

    try {
        const { keys, sha } = await getKeys();

        // [FIX] Cek kalau sha null (file belum ada)
        if (sha === null) {
            return res.status(500).json({ error: "File keys.json tidak ditemukan di repo" });
        }

        const generated = [];
        const expires   = new Date(Date.now() + expireMs).toISOString();

        for (let i = 0; i < num; i++) {
            let key;
            // Pastikan key unik (anti-collision)
            do { key = generateKey(); } while (keys[key]);
            keys[key] = { expires, hwid: hwid || null, createdAt: new Date().toISOString() };
            generated.push(key);
        }

        await saveKeys(keys, sha);
        return res.json({ keys: generated, expires, expireDays: days });
    } catch (e) {
        console.error("[genkey] Error:", e.message);
        return res.status(500).json({ error: "Server error: " + e.message });
    }
}
