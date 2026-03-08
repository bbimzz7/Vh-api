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

    // Parse body manual kalau req.body kosong
    let body = req.body || {};
    if (!body.hwid && req.body === undefined) {
        try {
            const chunks = [];
            for await (const chunk of req) chunks.push(chunk);
            const raw = Buffer.concat(chunks).toString("utf8");
            body = JSON.parse(raw);
        } catch(e) {
            return res.status(400).json({ error: "Body tidak valid" });
        }
    }

    const { hwid, username, userId } = body;

    if (!hwid || hwid === "undefined") return res.status(400).json({ error: "HWID wajib diisi" });
    if (hwid.length > 128)             return res.status(400).json({ error: "HWID tidak valid" });

    const ts      = Date.now();
    const payload = JSON.stringify({
        hwid:     hwid.trim(),
        username: (username || "").trim().substring(0, 64),
        userId:   (userId   || "").trim().substring(0, 32),
        ts,
        exp: ts + 5 * 60 * 1000
    });

    const encoded = Buffer.from(payload).toString("base64url");
    const sig     = sign(encoded);

    return res.json({ url: `/?d=${encoded}&s=${sig}` });
}
