# Zelly relay — serverga chiqarish

POS API'sini internetga chiqarish uchun sozlamalar. Admin mobil ilovasi
([`../docs/06_ADMIN_APP_API.md`](../docs/06_ADMIN_APP_API.md)) kafedan
tashqarida shu orqali ishlaydi.

---

## Nega relay, "backend yuklash" emas

Tezzro API'si alohida backend **emas** — u POS ilovasining ichida ishlaydi
(`lib/core/server/api_server.dart`, `ApiServer.start(8080)`) va o'sha
kompyuterdagi SQLite fayliga hamda USB printerga bog'langan.

Ya'ni bu kodni Linux serverga ko'chirib bo'lmaydi: bazasi yo'q, printeri
yo'q, `win32`/`ffi` bog'liqliklari ishlamaydi.

**Server API'ni yuritmaydi — uni tashqariga chiqaradi:**

```
Telefon (admin)
    │  HTTPS  mehmon.zelly.uz:443
    ▼
┌────────────────────────────────────────┐
│ 5.104.108.235                          │
│  nginx :443 ──┬─ /~!frp ──► frps :7000 │  ← boshqaruv kanali (wss)
│               └─ /*      ──► frps :8081│  ← foydalanuvchi trafigi
└───────────▲────────────────────────────┘
            │ wss (443) — POS o'zi ulanadi
┌───────────┴──────────┐
│ Kafedagi POS         │
│ ApiServer :8080      │  ← baza va printer shu yerda
└──────────────────────┘
```

Kafeda oq IP, port forwarding, router sozlash **kerak emas**.

### ⚠️ Nega hamma narsa 443 orqali

Dastlab frp uchun 7000-port ochilgan edi. **Ishlamadi:** serverga SYN paketi
ham yetib bormaydi (`tcpdump` bilan tasdiqlangan). Sinov ko'rsatdiki, 22, 80
va 443 dan **boshqa hamma port yopiq** — provayder darajasida.

Bu aslida yaxshi natija: kafe tarmoqlari ham odatda nostandart portlarni
bloklaydi, ya'ni 443 orqali ishlash yagona ishonchli yo'l edi.

Shuning uchun:
- `frps` faqat `127.0.0.1` da tinglaydi (tashqariga ochiq emas)
- nginx `location = /~!frp` ni frps ga uzatadi (WebSocket, 7 kunlik timeout)
- POS `transport.protocol = "wss"` bilan 443 ga ulanadi
- Tashqi portlar o'zgarmadi: **22, 80, 443**

> Bu **Faza 1 emas.** Haqiqiy cloud backend (Postgres + Sync API) keyinroq,
> `uuid`/`branch_id` migratsiyasidan so'ng —
> [`../docs/05_MOBIL_FILIAL_SYNC.md`](../docs/05_MOBIL_FILIAL_SYNC.md).
> Relay o'shanda ham o'z joyida qolaveradi.

---

## ⚠️ zelly.uz saytiga tegilmaydi

Serverda ishlaydigan sayt bor (`nginx/1.18.0`, Let's Encrypt sertifikati).
`server_setup.sh` uni himoya qiladi:

- mavjud nginx fayllari **o'zgartirilmaydi** — faqat yangi
  `sites-available/mehmon.zelly.uz` qo'shiladi
- `/etc/nginx` to'liq zaxiralanadi (`/root/zelly-relay-backup-*`)
- `nginx -t` yiqilsa — yangi fayl darhol o'chiriladi va reload qaytariladi
- certbot faqat `mehmon.zelly.uz` uchun ishlaydi

---

## Qadamlar

### 1. DNS (ahost.uz panelida — qo'lda)

| Turi | Nomi | Qiymat |
|---|---|---|
| A | `mehmon` | `5.104.108.235` |
| A | `*.mehmon` | `5.104.108.235` |

Ikkinchisi ko'p filial uchun: `a1.mehmon.zelly.uz`, `a2.mehmon.zelly.uz`.
Busiz ham ishlaydi, lekin har yangi filialda DNS'ga qaytish kerak bo'ladi.

Tekshirish: `nslookup mehmon.zelly.uz 8.8.8.8`

### 2. SSH kalit (bir marta)

```bash
ssh-copy-id -i ~/.ssh/zelly_server.pub root@5.104.108.235
ssh zelly "hostnamectl"
```

Ishlagach parol bilan kirishni yoping:

```bash
ssh zelly "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
  /etc/ssh/sshd_config && sshd -t && systemctl reload ssh"
```

### 3. Server

```bash
scp deploy/server_setup.sh zelly:/root/
ssh zelly "bash /root/server_setup.sh"
```

Skript oxirida **frp token** chiqadi — u keyingi bosqichda kerak.

### 4. POS kompyuteri — `frpc.exe`

1. [frp releases](https://github.com/fatedier/frp/releases) dan
   `frp_0.61.1_windows_amd64.zip` ni yuklang
2. `frpc.exe` ni **ilova papkasiga** qo'ying (`zelly_pos.exe` yonida)

`RelayService` uni shu tartibda qidiradi:

```
<ilova papkasi>\frpc.exe        ← tavsiya etiladi
<ilova papkasi>\data\frpc.exe
<ilova papkasi>\relay\frpc.exe
C:\frp\frpc.exe
%USERPROFILE%\Downloads\frpc.exe
```

> `frpc.toml` ni **qo'lda yozish shart emas** — `RelayService` uni
> sozlamalardan `%LOCALAPPDATA%\Zelly\relay\frpc.toml` ga o'zi yaratadi.
> `deploy/frpc.example.toml` faqat qo'lda sinash uchun namuna.

### 5. Ilovada sozlash

**Developer → Tashqi domen (relay) → Sozlash:**

| Maydon | Qiymat |
|---|---|
| Domen | `mehmon.zelly.uz` |
| Relay server | `mehmon.zelly.uz:443` (standart) |
| Token | `/etc/frp/token` dan |
| Yoqilgan | ✅ |

"Saqlash va ulash" — kartada holat ko'rinadi (`Ulangan` / xato sababi) va
tayyor havola nusxa olish uchun chiqadi.

**⚠️ Har kassada domen BOSHQA bo'lishi shart.** Ikkinchi kassa bir xil
domenni ishlatsa, u ulanolmaydi (`Bu domen boshqa kassa tomonidan band
qilingan`). ahost.uz da wildcard (`*.mehmon`) qabul qilinmadi, shuning uchun
har yangi kassa uchun oddiy A yozuv qo'shiladi:

| Turi | Nomi | Qiymat |
|---|---|---|
| A | `a2.mehmon` | `5.104.108.235` |

### 6. Nima o'zgardi (kod)

| Fayl | O'zgarish |
|---|---|
| `core/services/relay_service.dart` | **Yangi** — frpc boshqaruvi, holat, `frpc.toml` generatsiyasi |
| `providers/connectivity_provider.dart` | Server ishga tushganda `RelayService` ham ishga tushadi |
| `core/services/telegram_bot_service.dart` | "Hisobot Paneli" tugmasi barqaror domenni ishlatadi |
| `core/services/tunnel_service.dart` | Relay yoqilgan bo'lsa Telegram xabarini yubormaydi (ikkilanish bo'lmasin) |
| `features/mgmt/developer_mgmt_screen.dart` | "Tashqi domen (relay)" kartasi va sozlash oynasi |

**Buzuvchi o'zgarish yo'q:** relay o'chirilgan bo'lsa hammasi avvalgidek —
Cloudflare tunneli ishlaydi.

---

## Foydali buyruqlar

```bash
# Holat
ssh zelly "systemctl status frps --no-pager; ss -tlnp | grep -E '7000|8081'"

# Qaysi filiallar ulangan (panel, SSH tunnel orqali)
ssh -L 7500:127.0.0.1:7500 zelly    # → http://127.0.0.1:7500

# Loglar
ssh zelly "tail -f /var/log/frps.log"
ssh zelly "tail -f /var/log/nginx/mehmon.zelly.uz.error.log"

# Token
ssh zelly "cat /etc/frp/token"

# Sertifikat muddati
ssh zelly "certbot certificates"
```

## Xavfsizlik eslatmalari

| Nima | Holat |
|---|---|
| POS API endi internetdan ochiq — yagona to'siq token auth | Brute-force himoyasi bor (`API.md` §2), lekin **PIN'lar bazada ochiq matnda** |
| Telefon→server trafigi | ✅ TLS (Let's Encrypt) |
| Server→POS trafigi | frp tunnel ichida; `transport.tls.enable` bilan kuchaytirilsin |
| `frpc.toml` dagi token | Git'ga **qo'yilmasin** (`.gitignore` da) |
| frps paneli va vhost porti | Faqat localhost (`ufw deny`) |

> PIN hash (bcrypt) — `API.md` §8 dagi qarz. API internetga chiqqach bu
> qarzning narxi oshadi.
