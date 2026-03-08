// GET /api/checkkey?key=XXXX&hwid=YYYY
// Pertama kali → bind HWID ke key
// Selanjutnya  → cek HWID cocok atau tidak
// Returns { valid: true/false, reason?, expires?, hwid? }

const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const GITHUB_REPO  = process.env.GITHUB_REPO;
const GITHUB_FILE  = process.env.GITHUB_FILE;

// [FIX] Validasi format key biar gak spam request gak jelas
const KEY_REGEX = /^VH-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$/;

async function getKeys() {
    const res = await fetch(
        `https://api.github.com/repos/${GITHUB_REPO}/contents/${GITHUB_FILE}`,
        {
            headers: {
                Authorization: `token ${GITHUB_TOKEN}`,
                "User-Agent": "vh-key-api",
                "Cache-Control": "no-cache",
            },
        }
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
            body: JSON.stringify({ message: "bind hwid to key", content, sha }),
        }
    );
    if (res.status === 409) throw new Error("Konflik data, coba lagi sebentar");
    if (!res.ok) throw new Error("Gagal simpan data ke GitHub");
}

export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    if (req.method === "OPTIONS") return res.status(200).end();
    if (req.method !== "GET") return res.status(405).json({ valid: false, reason: "Method not allowed" });

    const key      = (req.query.key      || "").trim().toUpperCase();
    const hwid     = (req.query.hwid     || "").trim();
    const username = (req.query.username || "").trim();
    const userId   = (req.query.userId   || "").trim();

    if (!key)  return res.status(400).json({ valid: false, reason: "Key tidak boleh kosong" });
    if (!hwid) return res.status(400).json({ valid: false, reason: "HWID tidak boleh kosong" });
    if (!KEY_REGEX.test(key)) return res.status(400).json({ valid: false, reason: "Format key tidak valid" });
    if (hwid.length > 128)   return res.status(400).json({ valid: false, reason: "HWID tidak valid" });

    try {
        const { keys, sha } = await getKeys();
        const entry = keys[key];

        if (!entry) return res.json({ valid: false, reason: "Key tidak ditemukan" });

        const now     = Date.now();
        const expires = new Date(entry.expires).getTime();
        if (now > expires) return res.json({ valid: false, reason: "Key sudah expired" });

        if (!entry.hwid) {
            keys[key].hwid    = hwid;
            keys[key].boundAt = new Date().toISOString();
            await saveKeys(keys, sha);
            return res.json({ valid: true, expires: entry.expires, hwid, bound: true });
        }

        if (entry.hwid !== hwid) {
            return res.json({ valid: false, reason: "Key sudah digunakan di device lain" });
        }

        return res.json({ valid: true, expires: entry.expires, hwid, bound: false });

    } catch (e) {
        console.error("[checkkey] Error:", e.message);
        return res.status(500).json({ valid: false, reason: "Server error, coba lagi" });
    }
}
