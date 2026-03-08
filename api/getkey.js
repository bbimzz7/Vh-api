// GET /api/getkey?hwid=XXXX
// Dipanggil setelah user selesai Linkvertise
// Returns { key: "VH-XXXX-XXXX-XXXX", expires: "ISO" }

import crypto from "crypto";

const GITHUB_TOKEN  = process.env.GITHUB_TOKEN;
const GITHUB_REPO   = process.env.GITHUB_REPO;
const GITHUB_FILE   = process.env.GITHUB_FILE;
const KEY_EXPIRE_MS = 24 * 60 * 60 * 1000;

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
            body: JSON.stringify({ message: "generate key via getkey", content, sha }),
        }
    );
    if (res.status === 409) throw new Error("Konflik data, coba lagi sebentar");
    if (!res.ok) throw new Error("Gagal simpan ke GitHub");
}

function generateKey() {
    const part = () => crypto.randomBytes(3).toString("hex").toUpperCase();
    return `VH-${part()}-${part()}-${part()}`;
}

export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    if (req.method === "OPTIONS") return res.status(200).end();
    if (req.method !== "GET")    return res.status(405).json({ error: "Method not allowed" });

    const hwid = (req.query.hwid || "").trim();

    if (!hwid)          return res.status(400).json({ error: "HWID tidak boleh kosong" });
    if (hwid.length > 128) return res.status(400).json({ error: "HWID tidak valid" });

    try {
        const { keys, sha } = await getKeys();

        if (sha === null) {
            return res.status(500).json({ error: "File keys.json tidak ditemukan di repo" });
        }

        const now = Date.now();

        // Cek kalau HWID ini udah punya key yang masih valid
        for (const [k, v] of Object.entries(keys)) {
            if (v.hwid === hwid && new Date(v.expires).getTime() > now) {
                return res.json({ key: k, expires: v.expires, reused: true });
            }
        }

        // Generate key baru, pastikan unik
        let key;
        do { key = generateKey(); } while (keys[key]);

        const expires = new Date(now + KEY_EXPIRE_MS).toISOString();
        keys[key]     = { expires, hwid, createdAt: new Date().toISOString() };

        await saveKeys(keys, sha);
        return res.json({ key, expires, reused: false });
    } catch (e) {
        console.error("[getkey] Error:", e.message);
        return res.status(500).json({ error: "Server error, coba lagi" });
    }
}
