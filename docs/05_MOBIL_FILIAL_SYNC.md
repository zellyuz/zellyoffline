# Mobil ilova · Ko'p filiallik · Online/Offline sinxronizatsiya

> Manba: [`taklif.md`](taklif.md) · Bog'liq: [`01_ARCHITECTURE.md`](01_ARCHITECTURE.md) ·
> [`04_ROADMAP.md`](04_ROADMAP.md) · [`API.md`](../API.md)
>
> **Sana:** 2026-08-20 · **Holat:** taklif (hali boshlanmagan)

---

## 0. Qisqacha xulosa

So'ralgan 3 ta band bir-biridan mustaqil emas. Tartib muhim:

| # | Band | Aslida nima | Tartib |
|---|------|-------------|--------|
| 3 | Online/Offline sync | **Poydevor.** Ma'lumot modeli va cloud backend | 1-chi |
| 2 | Ko'p filiallik | Sync ustiga `branch_id` + markaziy baza | 2-chi |
| 1 | Mobil ilova | REST/WS allaqachon tayyor — eng oson qism | 3-chi (qisman parallel) |

**Sabab:** ko'p filiallik = ikkita bazani birlashtirish, ya'ni sync'siz mumkin
emas. Mobil ilova esa filialdan tashqarida ishlashi uchun cloud relay talab
qiladi — u ham sync infratuzilmasi.

**Eng muhim qaror:** jadvallarni **egalik (ownership)** bo'yicha ikkiga bo'lish.
Shunda konfliktlarning 90% umuman paydo bo'lmaydi (§2.4).

---

## 1. Hozirgi holat — nimadan boshlaymiz

Bu bo'lim taxmin emas, koddan olingan faktlar. Reja shularga tayanadi.

### 1.1. Bor va foydali

| Nima | Qayerda | Nega muhim |
|---|---|---|
| REST API — 53 endpoint + WebSocket | `lib/core/server/routes/` | Mobil ilova uchun deyarli tayyor |
| Token auth, rol/huquqlar, brute-force himoyasi | `auth_token_service.dart`, `api_context.dart` | Mobil auth qayta yozilmaydi |
| `ConnectivityMode { local, server, client }` | `connectivity_provider.dart` | "Bir POS — ikkinchisining mijozi" modeli allaqachon ishlaydi |
| `BaseRepository` — remote→lokal kesh | `lib/data/repositories/base_repository.dart` | Sync uchun tayyor ilgak |
| Data layer 100% (18 repozitoriy) | `lib/data/repositories/` | SQL bir joyda — migratsiya osonlashadi |
| Cloudflare Tunnel | `core/services/tunnel_service.dart` | Serverni tashqariga chiqarish allaqachon sinalgan |
| `audit_logs` jadvali | `database_helper.dart` | O'zgarishlar jurnalining yarmi tayyor |
| Modellar immutable + `toMap`/`fromMap` | `lib/models/` | JSON sync uchun to'g'ri shakl |

### 1.2. Yo'q va to'sqinlik qiladigan narsalar

| Muammo | Bugungi holat | Nega sync'ni buzadi |
|---|---|---|
| **ID lar global emas** | Ko'p jadvalda `INTEGER PRIMARY KEY AUTOINCREMENT` | Ikki filialda `products.id = 7` — ikki xil mahsulot. Birlashtirilsa to'qnashadi |
| **`orders.id` — vaqt tamg'asi** | `DateTime.now().millisecondsSinceEpoch.toString()` | Ikki qurilma bir millisekundda buyurtma ochsa — bir xil ID |
| **`updated_at` yo'q** | Faqat ba'zi jadvalda `created_at` | "Kim yangiroq?" degan savolga javob yo'q |
| **Hard delete** | `dbHelper.delete(...)` — yozuv yo'qoladi | Offline qurilma o'chirilganini bilmaydi, keyin qaytadan tiklaydi |
| **`branch_id` yo'q** | Hech qayerda | Ma'lumotlar aralashib ketadi |
| **`is_synced` — faqat `orders` da** | Ishlatilmaydigan ustun | Boshqa jadvallarda navbat yo'q |
| **Cloud backend yo'q** | Faqat LAN server | Filiallar bir-birini ko'rmaydi |
| **Litsenziya qurilmaga bog'langan** | `license.json` → `device_id` | Har filialda alohida litsenziya kerak bo'ladi |
| **Faqat Windows target** | `windows/` bor, `android/` yo'q | Mobil ilova shu loyihada qurilmaydi |
| **`win32`, `print_usb`, `ffi` bog'liqliklari** | `pubspec.yaml` | Android build'ini buzadi — mobil alohida ilova bo'lishi kerak |

---

## 2. Band 3 — Online/Offline gibrid (poydevor)

### 2.1. Topologiya

Tavsiya: **filial POS — o'z ma'lumotining egasi (source of truth)**,
cloud — nusxa yig'uvchi va tarqatuvchi.

```
    ┌──────────────── CLOUD (markaz) ────────────────┐
    │  Postgres  +  Sync API  +  Admin konsol        │
    └───▲────────────────▲───────────────────▲───────┘
        │ push/pull      │                   │
        │ (HTTPS)        │                   │
  ┌─────┴─────┐   ┌──────┴─────┐      ┌──────┴───────┐
  │ Filial A  │   │  Filial B  │      │ Mobil admin  │
  │ POS+SQLite│   │ POS+SQLite │      │ (faqat o'qish)│
  └─────▲─────┘   └────────────┘      └──────────────┘
        │ LAN (bugungi API)
  ┌─────┴──────────────┐
  │ Ofitsiant telefoni │
  └────────────────────┘
```

Nega shunday:
- Internet uzilsa **kassa to'liq ishlaydi** — hech narsa cloudga bog'liq emas.
- Ofitsiant telefoni filial ichida **LAN orqali** ishlaydi (kechikish ~1 ms),
  cloud faqat filialdan tashqarida kerak.
- Cloud yiqilsa — savdo to'xtamaydi, faqat sync navbatda kutadi.

### 2.2. Ma'lumot modelini tayyorlash (Faza 0)

Har bir sinxronlanadigan jadvalga **4 ta ustun** qo'shiladi:

```sql
uuid       TEXT    NOT NULL UNIQUE   -- global identifikator
branch_id  TEXT    NOT NULL          -- qaysi filialniki
updated_at TEXT    NOT NULL          -- ISO-8601 UTC, har yozishda yangilanadi
deleted_at TEXT                      -- soft delete (NULL = tirik)
```

Qoidalar:
- **`id` (INTEGER) qoladi** — lokal foreign key va indekslar buzilmasin.
  `uuid` — faqat tarmoq bo'ylab. Bu eng kam xarajatli yo'l: 60 jadval va
  54 migratsiyani qayta yozish shart emas.
- **Yangi `uuid` — UUID v7** (vaqt bo'yicha tartiblanadi, indeks do'sti).
  `uuid` paketi allaqachon `pubspec.yaml` da bor.
- **Hard delete taqiqlanadi.** `deleteById` → `deleted_at = now()`.
  UI `WHERE deleted_at IS NULL` bilan o'qiydi. Bu `BaseRepository` da
  **bitta joyda** o'zgaradi — 18 repozitoriy avtomatik to'g'rilanadi.
- **`orders.id`** — vaqt tamg'asi o'rniga `branchCode + UUIDv7`.
  Odam o'qiydigan raqam (`daily_number`, chek raqami) alohida qoladi:
  `A-260820-014` (filial kodi + sana + kunlik tartib).

Migratsiya `_onUpgrade` da bitta sikl bilan bajariladi — jadval ro'yxati
bo'yicha `ALTER TABLE` va mavjud satrlarga `uuid` backfill.

### 2.3. Sync mexanikasi

Ikki yangi lokal jadval:

```sql
-- Yuborilishi kerak bo'lgan o'zgarishlar navbati
CREATE TABLE sync_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  row_uuid   TEXT NOT NULL,
  op         TEXT NOT NULL,        -- insert | update | delete
  payload    TEXT NOT NULL,        -- JSON
  created_at TEXT NOT NULL,
  attempts   INTEGER DEFAULT 0,
  last_error TEXT
);

-- Har bir jadval bo'yicha "qayergacha o'qidim"
CREATE TABLE sync_state (
  table_name TEXT PRIMARY KEY,
  cursor     TEXT,                 -- oxirgi pull ning server kursori
  synced_at  TEXT
);
```

Oqim:

1. **Push** — `sync_outbox` dan 200 tagacha yozuv paket qilib yuboriladi.
   Server `row_uuid + updated_at` bo'yicha **idempotent** qabul qiladi
   (takror yuborilsa dublikat bo'lmaydi). Muvaffaqiyatda satr navbatdan
   o'chadi, xatoda `attempts++` va eksponensial kutish.
2. **Pull** — `sync_state.cursor` dan keyingi o'zgarishlar so'raladi,
   lokalga yoziladi, kursor suriladi.
3. **Trigger** — internet paydo bo'lganda, har 60 soniyada, va muhim
   voqealardan keyin (to'lov, smena yopilishi) darhol.
4. **UI** — sarlavhada holat: `✔ sinxron` / `⟳ 14 ta kutmoqda` / `⚠ xato`.
   Foydalanuvchi hech qachon "yuborildimi?" deb o'ylab qolmasligi kerak.

`sync_outbox` ni to'ldirish **`BaseRepository` ichida** bo'ladi — har bir
`add`/`update`/`deleteById` chaqiruvi bir tranzaksiyada ham jadvalga, ham
navbatga yozadi. Domen kodiga tegilmaydi.

### 2.4. Konfliktlarni hal qilish — asosiy g'oya

Konfliktni **hal qilishdan ko'ra oldini olish** arzon. Buning uchun har bir
jadvalga bitta ega beriladi:

| Sinf | Jadvallar | Ega | Yo'nalish | Konflikt |
|---|---|---|---|---|
| **Katalog** (ma'lumotnoma) | `products`, `categories`, `locations`, `tables`, `users`, `waiters`, `printers`, `recipes`, `settings` | Markaz (admin) | Cloud → filial | Filial faqat o'qiydi → konflikt **yo'q** |
| **Tranzaksion** (voqealar) | `orders`, `order_items`, `order_payments`, `transactions`, `expenses`, `shifts`, `cash_movements`, `stock_movements`, `audit_logs` | Filial | Filial → cloud | Append-only, o'zgarmas → konflikt **yo'q** |
| **Aralash** | `customers`, `ingredient_stock`, `products.quantity` | Ikki tomon | Ikki tomonlama | Qoida kerak (pastga qarang) |

**Aralash sinf qoidalari:**

- `customers` — **maydon darajasida LWW** (Last-Write-Wins, `updated_at`
  bo'yicha; teng bo'lsa `branch_id` alifbo tartibida). Mijoz bir filialda
  telefon, boshqasida ism yangilasa — ikkisi ham saqlanadi.
- **Qoldiq (`products.quantity`, `ingredient_stock`) hech qachon LWW emas.**
  Qoldiq — qiymat emas, **harakatlar yig'indisi**. Sync qilinadigan narsa —
  `stock_movements` / `product_movements` satrlari (append-only), qoldiq esa
  har tomonda shulardan qayta hisoblanadi. Aks holda ikki filial bir vaqtda
  yozsa qoldiq yo'qoladi.
- **Bekor qilish o'chirish emas.** To'langan buyurtma hech qachon
  o'chirilmaydi — teskari yozuv (reversal) qo'shiladi. Buxgalteriya ham,
  sync ham shundan yutadi.

### 2.5. Offline kassa operatsiyalari — nozik joylar

| Holat | Yechim |
|---|---|
| Chek raqami takrorlanishi | Raqam **filialga xos**: `A-260820-014`. Cloud hech qachon raqam bermaydi |
| Smena (`shifts`) offline yopildi | Smena — filial voqeasi, append-only. Cloud faqat qabul qiladi |
| Offline paytda narx o'zgardi | Buyurtma **o'z paytidagi narxni** saqlaydi (`order_items.price` allaqachon shunday) — retroaktiv o'zgarish yo'q |
| Offline paytda mahsulot o'chirildi | Soft delete. Offline ochilgan buyurtma yaroqli qoladi, chunki `product_name` va `price` buyurtma ichida saqlangan |
| Bir necha kun offline | Outbox o'sadi, cheklov qo'yilmaydi. 30 kundan oshsa ogohlantirish. Pull kursorli bo'lgani uchun qaytish og'riqsiz |
| Qurilma soati noto'g'ri | `updated_at` — qurilma vaqti. Cloud qabul qilganda `server_received_at` ham yozadi; 5 daqiqadan katta og'ish ogohlantiriladi |
| Bir buyurtma ikki qurilmada | Bugungi holat saqlanadi: filial ichida **bitta POS** — server, qolganlari mijoz. Buyurtma egaligi LAN da hal bo'ladi, cloudga faqat natija boradi |

### 2.6. Cloud backend — nima ustiga qurish

| Variant | Ijobiy | Salbiy | Tavsiya |
|---|---|---|---|
| **Dart + shelf + Postgres** | Modellar, `toMap/fromMap`, auth kodi qayta ishlatiladi; jamoa shelf'ni biladi | Hosting, monitoring o'zimizda | ✅ **Tavsiya** |
| Supabase / Firebase | Tez start, auth tayyor | Vendor lock-in, murakkab sync qoidalari cheklangan, narx filial soniga qarab o'sadi | Prototip uchun |
| Node/Go | Ko'p misol | Modellar ikki tilda takrorlanadi | ❌ |

Dart tanlansa: `lib/models/` ni **umumiy paketga** (`packages/tezzro_shared`)
chiqarish kerak — desktop, mobil va server bitta modeldan foydalanadi.
Bu ish baribir mobil ilova uchun ham kerak (§4).

---

## 3. Band 2 — Ko'p filiallik

### 3.1. Ierarxiya

```
Organization (tashkilot)
└── Branch (filial)          ← branch_id shu yerdan
    ├── User / Waiter        ← filialga biriktiriladi
    ├── Location → Table
    ├── Order → OrderItem
    └── Shift, Expense, Stock
```

Yangi cloud jadvallar: `organizations`, `branches`, `branch_users`
(kim qaysi filialga kira oladi), `org_admins`.

### 3.2. Nima markazda, nima filialda

Bu — mahsulot qarori, texnik emas. Tavsiya etilgan standart:

| Ma'lumot | Kim boshqaradi | Izoh |
|---|---|---|
| Menyu, kategoriya, retsept | **Markaz** | Bitta brend — bitta menyu |
| Narx | **Markaz, filial bo'yicha override bilan** | Aeroport filiali qimmatroq bo'lishi mumkin |
| Xodimlar, PIN, huquqlar | Markaz yaratadi, filialga biriktiradi | Xodim filialdan filialga ko'chirilishi mumkin |
| Zal, stol, joylashuv | **Filial** | Har zalning o'z chizmasi |
| Printerlar, chek matni | **Filial** | Uskuna filialga xos |
| Ombor, qoldiq | **Filial** | Qoldiq umumiy bo'lmaydi |
| Xarajat, smena, kassa | **Filial** | Markaz faqat ko'radi |
| Hisobotlar | **Markaz — barcha filial kesimida** | Asosiy qiymat shu yerda |

Buning uchun `settings` jadvali ikkiga bo'linadi: `org_settings` (umumiy) va
`branch_settings` (filialga xos). Hozirgi `settings` — to'liq filialga xos
deb boshlanadi, keyin kerakli kalitlar markazga ko'chiriladi.

### 3.3. Admin uchun ko'p filial ko'rinishi

- **Konsolidatsiyalangan dashboard:** bugungi tushum — filiallar kesimida,
  yonma-yon.
- **Filialga "kirish"** (drill-down): bitta filialni tanlab, hozirgi hisobot
  ekranlarining aynan o'zini ko'rish.
- **Solishtirish:** filiallar reytingi (tushum, o'rtacha chek, food cost).
- Muhim: bu ekranlar **cloud read-model** ustida ishlaydi, filial POS'iga
  so'rov yubormaydi — filial o'chirilgan bo'lsa ham hisobot ochiladi.

### 3.4. Litsenziya

Hozir `license.json` bitta `device_id` ga bog'langan. Ko'p filialda:
`organization_id` + `branch_count` + har filial uchun `device_id` ro'yxati.
Imzo mexanizmi (RSA) o'zgarmaydi, faqat payload kengayadi.

> ⚠️ `private_key.pem` git'da turibdi (`03_SECURITY.md` da qayd etilgan).
> Cloud joriy qilinishidan **oldin** kalit almashtirilishi shart — cloud
> litsenziya tekshiruvining markaziga aylanadi.

---

## 4. Band 1 — Mobil ilova

### 4.1. Alohida ilovami yoki shu loyihagami?

**Alohida Flutter ilova + umumiy paket.** Sabab texnik va qat'iy:
hozirgi `pubspec.yaml` da `win32`, `ffi`, `print_usb`, `window_manager`,
`sqflite_common_ffi` bor — bular Android build'ini buzadi yoki mantiqsiz.

Tavsiya etilgan monorepo:

```
tezzro/
├── apps/
│   ├── pos_desktop/     ← hozirgi ilova (o'z joyida qoladi)
│   └── mobile/          ← yangi: ofitsiant + admin
├── packages/
│   ├── tezzro_shared/   ← modellar, enum'lar, formatlash, tarjima
│   └── tezzro_api/      ← REST/WS mijoz (API.md ning Dart qobig'i)
└── server/              ← cloud backend (Faza 1 da)
```

`tezzro_shared` — bu baribir cloud backend uchun ham kerak, ya'ni bir ish
uch joyga xizmat qiladi.

### 4.2. Bitta ilova, ikki rol

Alohida "ofitsiant ilovasi" va "admin ilovasi" **qilinmasin**. Bitta ilova,
login'dan keyin rolga qarab boshqa ekran:

- **`waiter`** → stollar xaritasi, buyurtma olish, chek so'rash.
  Server allaqachon huquq tekshiradi (`change_table`, `print_receipt`).
- **`admin`/`cashier`** → filiallar dashboard'i, hisobotlar, ombor.

`GET /auth/me` rol va huquqlarni qaytaradi — ekran shunga qarab quriladi.
Bu API tayyor, o'zgartirish shart emas.

### 4.3. Ulanish: LAN va cloud

Ilova **ikki manzilni** biladi va avtomatik tanlaydi:

1. **LAN** (`http://192.168.1.10:8080`) — filial ichida. Tez, internetsiz
   ishlaydi. QR kod orqali sozlanadi (POS ekranda QR ko'rsatadi — `qr_flutter`
   allaqachon bog'liqliklarda bor).
2. **Cloud relay** (`https://api.tezzro.uz/branch/<id>/...`) — tashqarida.
   Faza 5 gacha vaqtinchalik yechim sifatida mavjud **Cloudflare Tunnel**
   ishlatilishi mumkin (`tunnel_service.dart` — allaqachon ishlaydi).

Ofitsiant ilovasi uchun **offline yozish tavsiya etilmaydi** — ofitsiant
zaldan chiqmaydi, LAN bor. Offline holatda "aloqa yo'q" deb ko'rsatish
xato ma'lumot ko'rsatishdan xavfsizroq. Faqat menyu va stol chizmasi
keshlanadi (o'qish uchun).

### 4.4. Real-time

WebSocket kanali tayyor (`ws://host:8080/ws`, `tables_updated` /
`order_updated`). Mobil ilova:
- ulanish uzilsa — eksponensial backoff bilan qayta ulanadi;
- har 20 soniyada `ping` (NAT uchun);
- signal kelganda `GET /tables/summary` ni **bir marta** chaqiradi (polling yo'q).

Bu talablar `API.md` §4 da hujjatlangan.

### 4.5. API tomonidan nima yetishmaydi

Bugungi 53 endpoint mobil uchun deyarli yetarli. Qo'shilishi kerak:

| Endpoint | Nega |
|---|---|
| `GET /orders?status=open&waiter_id=me` | Ofitsiant "mening buyurtmalarim" ro'yxati |
| Pagination (`?limit`/`?offset`) | `API.md` §8 da qayd etilgan qarz. Telefonda butun tarixni yuklab bo'lmaydi |
| `POST /push/register` | Push bildirishnoma (chek tayyor, hisob so'raldi) |
| `/v1/` prefiksi | Mobil ilova versiyasi serverdan orqada qolishi tabiiy |
| **TLS** | Telefon → LAN trafigi hozir ochiq. Self-signed sertifikat + pinning |

---

## 5. Roadmap

Har bir faza **mustaqil qiymat** beradi — oxirigacha kutish shart emas.

### Faza 0 — Ma'lumot modelini tayyorlash · ~2 hafta
> Cloud yo'q, foydalanuvchi hech narsani sezmaydi. Lekin busiz keyingisi mumkin emas.

1. `uuid`, `branch_id`, `updated_at`, `deleted_at` — sinxronlanadigan
   jadvallarga migratsiya + backfill.
2. `BaseRepository` da hard delete → soft delete; barcha o'qishlarga
   `deleted_at IS NULL`.
3. `orders.id` → UUIDv7; `daily_number` / chek raqami filialga xos formatga.
4. Qoldiqni `stock_movements` dan qayta hisoblash — allaqachon shunday
   bo'lsa, tasdiqlash va test bilan qotirish.
5. **Test:** migratsiya testi (`db_migration_test.dart` kengaytiriladi).

**Natija:** baza sync'ga tayyor, xatti-harakat o'zgarmagan.

### Faza 1 — Cloud skeleti · ~2 hafta
1. `packages/tezzro_shared` — modellarni ajratish.
2. `server/` — Dart shelf + Postgres; `organizations`, `branches`, `users`.
3. Auth: filial qurilmasi uchun uzoq muddatli token (device token).
4. Deploy + monitoring + backup (kunlik).

**Natija:** cloud bor, hali hech narsa yubormaydi.

### Faza 2 — Push (filial → cloud) · ~2 hafta
1. `sync_outbox` + `SyncService` (batch, backoff, idempotentlik).
2. Tranzaksion jadvallar yuboriladi: `orders`, `order_items`,
   `order_payments`, `shifts`, `expenses`, `stock_movements`.
3. UI da sync holati indikatori.
4. **Test:** internetni uzib-ulab, 1000 buyurtmani yo'qotmasdan yuborish.

**Natija:** ✅ Cloudda barcha savdo tarixi bor — **bu allaqachon ko'p filial
hisobotini beradi**, admin konsolisiz ham (SQL orqali).

### Faza 3 — Admin konsol (ko'p filial) · ~3 hafta
1. Cloud read-model + hisobot API.
2. Veb dashboard: filiallar kesimida tushum, solishtirish, drill-down.
3. Mavjud `reports/view` HTML paneli shu yerga ko'chiriladi (endi u
   `views/mobile_report_html.dart` da alohida turibdi).

**Natija:** ✅ **Band 2 ning asosiy qiymati yetkazildi** — admin bir joydan
barcha filialni ko'radi.

### Faza 4 — Pull (cloud → filial) · ~2 hafta
1. Katalog jadvallari markazdan tarqatiladi: `products`, `categories`,
   `recipes`, narx override'lari.
2. `customers` uchun maydon darajasida LWW.
3. Konflikt jurnali va qo'lda hal qilish ekrani (kam holatlar uchun).

**Natija:** ✅ Menyu markazdan boshqariladi — **Band 2 to'liq**.

### Faza 5 — Mobil ilova · ~4 hafta
1. `apps/mobile` — Flutter (Android + iOS), `tezzro_api` mijozi.
2. Ofitsiant oqimi: login → stollar → buyurtma → chek so'rash.
3. Admin oqimi: filiallar dashboard'i (cloud API dan).
4. LAN/cloud avtomatik almashish, QR bilan sozlash.
5. Push bildirishnomalar.

**Natija:** ✅ **Band 1 to'liq.**

### Faza 6 — Qotirish · doimiy
1. TLS (LAN uchun self-signed + pinning).
2. `/v1/` versiyalash, pagination.
3. PIN hash (bcrypt) — `API.md` §8 dagi qarz.
4. `private_key.pem` almashtirish va git tarixidan olib tashlash.
5. Umumiy rate limit.

**Jami taxminiy:** ~15 hafta (bir dasturchi, to'liq band). Fazalar 3 va 5
qisman parallel ketishi mumkin.

---

## 6. Qaror kerak bo'lgan savollar

Bularga javob bermasdan Faza 1 ni boshlab bo'lmaydi:

1. **Cloud qayerda turadi?** O'zbekiston ichida (ma'lumot rezidentligi,
   kechikish) yoki xorijda (arzon, ishonchli)?
2. **Nechta filial ko'zlanmoqda?** 3 tami yoki 50 ta — arxitektura bir xil,
   lekin hosting va narx modeli boshqa.
3. **Narx modeli:** cloud abonent to'lovi bormi? Litsenziya modeli shunga
   qarab o'zgaradi.
4. **Menyu markazdan majburiymi?** Yoki filial o'z menyusini qo'shishi
   mumkinmi (franshiza modeli)?
5. **Mobil: iOS kerakmi?** Faqat Android bo'lsa muddat ~1 hafta qisqaradi
   (App Store, sertifikatlar).
6. **Offline chegarasi:** filial necha kun internetsiz ishlashi kerak?
   (Tavsiya: 30 kun, keyin ogohlantirish.)

---

## 7. Xavflar

| Xavf | Ta'sir | Yumshatish |
|---|---|---|
| Faza 0 migratsiyasi mavjud bazalarni buzishi | Yuqori — ishlab turgan kafelar | Migratsiya testi + avtomatik backup + bosqichma-bosqich chiqarish |
| Sync xatosi tushumni ikki marta hisoblashi | Yuqori | Idempotentlik `row_uuid` bo'yicha; cloudda dublikat testi |
| Qoldiqni LWW bilan sync qilish | Yuqori — ombor buziladi | §2.4: qoldiq hech qachon LWW emas, faqat harakatlar |
| Monorepo ko'chirish ishni to'xtatishi | O'rta | Faza 1 da faqat `tezzro_shared` ajratiladi, desktop o'z joyida qoladi |
| Cloud yiqilsa savdo to'xtashi | Yuqori | Arxitektura sharti: cloud **hech qachon** savdo yo'lida bo'lmaydi |
| God file'lar (`pos_screen`, `database_helper`) sync ishini sekinlashtirishi | O'rta | `database_helper` ni `schema/` + `migrations/` ga bo'lish Faza 0 dan oldin (`01_ARCHITECTURE.md` §5) |

---

## 8. Birinchi qadam (agar bugun boshlansa)

`01_ARCHITECTURE.md` §5 dagi 7-band — **`database_helper.dart` ni
`schema/` + `migrations/` ga bo'lish** — Faza 0 ning tabiiy boshlanishi.
2 500 satrli faylga `uuid`/`branch_id` migratsiyasini qo'shish hozir
xavfli; bo'lingandan keyin esa oddiy ish.

Ya'ni: **god file'larni bo'lish** va **sync poydevori** — bir yo'nalishdagi
ish, alohida emas.
