# ZYVPAY

Net ho ya na ho, payment ho jaye. ZYVPAY ek UPI-style payment app hai jo online
ho to internet se, aur offline ho to **SMS** se payment bhejti hai. SMS hamesha
user khud bhejta hai (phone ki SMS app khul kar) — koi chhupa/background SMS nahi.

> **Status:** working prototype. Asli paise ke liye ek RBI-compliant wallet/PPI
> partner aur PayU payout ki real keys chahiye. Tab tak `PAYOUT_MODE=mock` par
> chalega aur paise nakli honge.

## Hisse

| Folder | Kya hai |
|---|---|
| `backend/` | Node + Postgres. ZP1 SMS protocol, ledger, PIN verify, limits, PayU payout adapter, gateway API. |
| `app/` | Flutter user app (UPI-style UI). Online + user-confirmed SMS payment. |
| `gateway/` | Flutter app aapke service SIM wale phone ke liye — user ke SMS backend ko bhejta hai aur reply SMS bhejta hai. |
| `packages/zyv_sms/` | Android SMS send/receive plugin (dono apps isi ko use karti hain). |

## Payment kaise chalta hai

```
User app                 Gateway phone (service SIM)        Backend              PayU
  | online? --net--------------------------------------------> /api/request -----> payout
  | offline: SMS composer khulta hai, user "Send" dabata hai
  |---- ZP1 SMS ---------> inbound -----> /gateway/inbound ---> verify+debit -----> payout
  |<--- reply SMS <------- outbox  <----- /gateway/outbox <---- confirmation
```

- Har payment par ek **counter (nonce)** aur **HMAC (PIN se bana)** hota hai —
  isse replay aur galat PIN ruk jaate hain. Ek SMS dobara aaye to dobara charge
  nahi hota.
- **Limits:** ek payment ₹2,000, roz ₹5,000 (config se badal sakte hain).
- Galat PIN 5 baar → device lock.

## Chalana (test mode)

**Backend**
```bash
cd backend
npm install
export DATABASE_URL=postgres://localhost:5432/zyvpay
export GATEWAY_TOKEN=... ADMIN_TOKEN=... GATEWAY_NUMBER=91XXXXXXXXXX
export PAYOUT_MODE=mock
npm run migrate && npm start
# tests: TEST_DATABASE_URL=postgres://.../zyvtest npm test
```

**APK build:** `git push` karte hi GitHub Actions dono APK (`app`, `gateway`)
bana deta hai — Actions → run → Artifacts se download karein. Ya local:
`cd app && flutter build apk`.

**Phone setup**
1. Gateway app service SIM wale phone par daalein, Backend URL + token bharein, Start.
2. User app mein naam/number/PIN set karein; verify SMS bhejein.
3. Admin se wallet load (abhi): `POST /admin/credit {phone, amountPaise}`.

## PayU payout
`PAYOUT_MODE=payu` aur `PAYU_CLIENT_ID / USERNAME / PASSWORD / PAYOUT_MERCHANT_ID`
set karein. `backend/src/payout.js` ke request shapes PayU ke docs se confirm kar
lein. Final status PayU webhook (`/webhooks/payu`) se aata hai.

## Zaroori / legal
- Wallet mein logon ka paisa rakhna RBI-regulated hai. Launch se pehle licensed
  partner ya PPI license zaroori.
- User app background mein SMS nahi bhejti — ye jaan-boojh kar safe rakha gaya hai.
