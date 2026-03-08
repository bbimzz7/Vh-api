# VH Key System - Setup Guide

## File Structure
```
vh-key-api/
├── api/
│   ├── checkkey.js   ← cek apakah key valid
│   ├── genkey.js     ← generate key manual (admin)
│   └── getkey.js     ← generate key otomatis via Linkvertise
├── public/
│   └── getkey.html   ← halaman web user ambil key
├── vercel.json
├── package.json
└── keys.json         ← upload ke GitHub repo (bbimzz7/log)
```

---

## Step 1 — Upload keys.json ke GitHub
Upload file `keys.json` ke repo `bbimzz7/log` (branch main).

---

## Step 2 — Buat GitHub Personal Access Token
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token → centang `repo` (full control)
3. Copy tokennya, simpan

---

## Step 3 — Deploy ke Vercel
1. Push folder `vh-key-api` ke GitHub repo baru (misal `bbimzz7/vh-key-api`)
2. Buka vercel.com → New Project → Import repo tersebut
3. Tambah Environment Variables:

| Key | Value |
|-----|-------|
| `GITHUB_TOKEN` | token dari Step 2 |
| `GITHUB_REPO` | `bbimzz7/log` |
| `GITHUB_FILE` | `keys.json` |
| `ADMIN_SECRET` | password bebas (buat gen key manual) |

4. Deploy → dapat URL misal `https://vh-key-api.vercel.app`

---

## Step 4 — Update URL di key_checker.lua
Ganti baris ini:
```lua
local API_BASE = "https://vh-key-api.vercel.app"
```
Dengan URL Vercel kamu.

---

## Step 5 — Tempel key_checker.lua di sssource
Copy isi `key_checker.lua` → paste di **paling atas** `sssource-1.lua` sebelum semua kode lain.

---

## Step 6 — Setup Linkvertise
1. Daftar di linkvertise.com
2. Buat link baru → destination URL: `https://vh-key-api.vercel.app/getkey?hwid={hwid}`
3. Copy USER_ID kamu dari dashboard Linkvertise
4. Edit `getkey.html` baris ini:
```js
const LINKVERTISE_URL = `https://linkvertise.com/USER_ID/vertichub-key?o=sharing`;
```
Ganti `USER_ID` dengan ID kamu.

---

## Generate Key Manual (Admin)
```bash
curl -X POST https://vh-key-api.vercel.app/api/genkey \
  -H "Content-Type: application/json" \
  -d '{"secret":"PASSWORD_KAMU","count":5}'
```
Returns:
```json
{
  "keys": ["VH-A1B2C3-D4E5F6-G7H8I9", ...],
  "expires": "2025-01-02T..."
}
```

---

## Alur User
1. Execute script → muncul GUI key
2. Klik "Belum punya key?" → link disalin ke clipboard
3. Buka link di browser → selesaikan Linkvertise (±15 detik)
4. Dapat key → paste di GUI → klik Verifikasi
5. Key disimpan otomatis → besok tinggal execute langsung (auto re-check)
