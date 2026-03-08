// POST /api/token
// Body: { hwid, username, userId }
// Returns { url: "/?d=...&s=..." }
// Token expired 5 menit, signed pakai HMAC-SHA256

import crypto from "crypto";

const SECRET = process.env.TOKEN_SECRET || process.env.ADMIN_SECRET || "fallback-secret";

function sign(data) {
    return crypto.createHmac("sha256", SECRET).update(data).digest("hex").substring(0, 32);
}

export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.status(200).end();
    if (req.method !== "POST")   return res.status(405).json({ error: "Method not allowed" });

    const { hwid, username, userId } = req.body || {};

    if (!hwid)             return res.status(400).json({ error: "HWID wajib diisi" });
    if (hwid.length > 128) return res.status(400).json({ error: "HWID tidak valid" });

    // Payload: hwid|username|userId|timestamp
    const ts      = Date.now();
    const payload = JSON.stringify({
        hwid:     hwid.trim(),
        username: (username || "").trim().substring(0, 64),
        userId:   (userId   || "").trim().substring(0, 32),
        ts,
        exp: ts + 5 * 60 * 1000 // expired 5 menit
    });

    // Enkripsi base64 + signature
    const encoded = Buffer.from(payload).toString("base64url");
    const sig     = sign(encoded);

    const url = `/?d=${encoded}&s=${sig}`;
    return res.json({ url });
}
