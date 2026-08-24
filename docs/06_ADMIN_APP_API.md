# Admin ilovasi — API spetsifikatsiyasi

> **Sana:** 2026-08-23 · **Holat:** spetsifikatsiya (kod yozilmagan)
> **Manba:** `lib/core/server/routes/` (56 route), `lib/features/` (desktop
> admin ekranlari), `database_helper.dart` (34 jadval)
> **Bog'liq:** [`../API.md`](../API.md) · [`05_MOBIL_FILIAL_SYNC.md`](05_MOBIL_FILIAL_SYNC.md)

Bu hujjat **admin mobil ilovasi** uchun kerak bo'ladigan barcha endpoint'larni
bir joyga yig'adi: qaysilari **bor**, qaysilari **yo'q**, va yo'qlari qanday
bo'lishi kerak.

---

## 0. Qamrov

### Admin ilovasi nima qiladi

Rahbar/egaga **kafeni telefondan kuzatish va boshqarish** imkonini beradi —
u kafeda bo'lmasa ham.

### Nima qilmaydi (ataylab)

| Amal | Nega yo'q |
|---|---|
| Buyurtma ochish / savat tahrirlash | Bu ofitsiant ilovasining ishi — alohida oqim |
| To'lovni qabul qilish | Kassa amali, fizik pul bilan bog'liq |
| Chek chop etish | Printer filialda, telefonda ma'nosi yo'q |
| Ombor kirim/chiqim yozish | Tannarxni o'zgartiradi, telefonda xato bosish oson (`API.md` §5.8) |
| Smena yopish | Naqd sanash — fizik amal. Telefondan yopilsa kassa hisobi buziladi |

> Qoida: **admin ilovasi ko'radi va sozlaydi, sotmaydi.**
> Pul harakati bilan bog'liq har qanday yozish amali desktop POS'da qoladi.

---

## 1. Umumiy shartlar

Bularning hammasi **allaqachon ishlaydi** — `API.md` §1–§4 da to'liq
hujjatlangan. Admin ilovasi uchun qayta yozilmaydi:

| Nima | Holat |
|---|---|
| Base URL: `http://<host>:8080` | ✅ |
| `Authorization: Bearer <token>` | ✅ |
| Token: tasodifiy, 12 soat, sliding expiry | ✅ |
| Rol/huquq tekshiruvi (`/admin/*`, `/reports/*`, `/inventory/*` — faqat admin) | ✅ |
| Brute-force himoyasi (`429`) | ✅ |
| Sahifalash `?limit`/`?offset` (max 200) | ✅ (6 endpoint'da) |
| WebSocket `ws://<host>:8080/ws` | ✅ |
| Xato formati `{ "error": "..." }` | ✅ |

**Admin ilovasi doim `?limit` yuborsin** — javob `{data, meta}` shaklida keladi.

---

## 2. Ekran → endpoint xaritasi

Har bir ekran uchun qaysi so'rovlar kerakligi. `❌` — endpoint hali yo'q (§4).

### 2.1. Kirish

| Ekran | Endpoint | Holat |
|---|---|---|
| Login (PIN) | `POST /auth/login` | ✅ |
| Sessiya tiklash | `GET /auth/me` | ✅ |
| Chiqish | `POST /auth/logout` | ✅ |
| Serverni topish / QR sozlash | `GET /server/info` | ❌ K1 |

### 2.2. Bosh ekran (Dashboard)

| Blok | Endpoint | Holat |
|---|---|---|
| Bugungi tushum, chek soni, o'rtacha chek | `GET /admin/dashboard` | ✅ |
| To'lov turlari kesimi (naqd/karta/…) | ⤴ shu javobda | ✅ |
| Kechagi bilan solishtirish | ⤴ `yesterday` | ✅ |
| Zal holati (band/bo'sh/hisob so'radi) | ⤴ `tables` | ✅ |
| Ochiq buyurtmalar summasi | ⤴ `open_orders` | ✅ |
| Top mahsulotlar | ⤴ `top_products` | ✅ |
| Faol smena + kutilayotgan naqd | ⤴ `shift` | ✅ |
| Kam qolgan xomashyo soni | ⤴ `inventory.low_stock` | ✅ |

> Bitta so'rov — 8 ta blok. Bu endpoint aynan shu ekran uchun qo'shilgan.

### 2.3. Jonli zal

| Blok | Endpoint | Holat |
|---|---|---|
| Stollar xaritasi + ochiq buyurtma summasi | `GET /tables/summary` | ✅ |
| Zallar ro'yxati (filtr uchun) | `GET /locations` | ✅ |
| Real-time yangilanish | WS `tables_updated` | ✅ |
| "Hisob so'raldi" signali | WS `bill_requested` | ❌ K3 |

### 2.4. Buyurtmalar

| Blok | Endpoint | Holat |
|---|---|---|
| Ro'yxat (ochiq + to'langan), filtrlar | `GET /orders?status&waiter_id&table_id&location_id&order_type&start&end&limit&offset` | ✅ |
| Buyurtma tafsiloti + tarkibi | `GET /orders/<id>` | ✅ |
| To'lov tafsiloti (bo'lingan to'lov) | `GET /orders/<id>` javobiga qo'shish | ❌ A4 |
| Yetkazib berish tafsiloti (manzil, kuryer) | ⤴ shu javobda | ❌ G2 |

### 2.5. Hisobotlar

| Ekran | Endpoint | Holat |
|---|---|---|
| Davr tanlash (bugun/hafta/oy) | `GET /reports/periods` | ✅ |
| Umumiy ko'rsatkichlar + top-5 | `GET /reports/stats` | ✅ |
| Soatlik savdo grafigi | `GET /reports/hourly` | ✅ |
| Mahsulotlar kesimi | `GET /reports/products` | ✅ |
| Ofitsiantlar samaradorligi | `GET /reports/waiters` | ✅ |
| Zallar kesimi | `GET /reports/locations` | ✅ |
| Stollar kesimi | `GET /reports/tables` | ✅ |
| To'langan buyurtmalar ro'yxati | `GET /reports/orders` | ✅ |
| Z-hisobot | `GET /reports/zreport` | ✅ |

**Barcha hisobot endpoint'lari quyidagi filtrlarni qabul qiladi**
(`API.md` da hujjatlanmagan — qarz, §6):

```
?start=<ISO>  ?end=<ISO>  ?shift_id=<int>
?order_type=<0|1|2>  ?location_id=<int>  ?waiter_id=<int>
```

`shift_id` berilsa `start`/`end` **e'tiborga olinmaydi** — smena bo'yicha
hisoblanadi. Bu "kecha kechqurungi smena" kabi savollar uchun muhim.

### 2.6. Smenalar

| Blok | Endpoint | Holat |
|---|---|---|
| Smenalar ro'yxati | `GET /reports/shifts?limit=20` | ✅ (sahifalash yo'q) |
| Joriy smena + kassa holati | `GET /admin/shift/current` | ✅ |
| Smena tafsiloti (yopilgan smena) | `GET /shifts/<id>` | ❌ B1 |
| Smena Z-hisoboti | `GET /reports/zreport?shift_id=<id>` | ✅ |
| Kassa kirim/chiqimlari | `GET /cash_movements?shift_id=<id>` | ❌ C1 |

### 2.7. Kassa va qarzlar

| Blok | Endpoint | Holat |
|---|---|---|
| Tranzaksiyalar tarixi | `GET /transactions?customer_id&limit&offset` | ✅ |
| Yangi to'lov/qarz yozuvi | `POST /transactions` | ✅ |
| Sana bo'yicha filtr | `GET /transactions?start&end` | ❌ E3 |

### 2.8. Xarajatlar

| Blok | Endpoint | Holat |
|---|---|---|
| Xarajatlar ro'yxati | `GET /expenses?limit&offset` | ✅ |
| Davr / kategoriya / smena filtri | `GET /expenses?start&end&category_id&shift_id` | ❌ D1 |
| Xarajat qo'shish | `POST /expenses` | ✅ |
| O'chirish | `DELETE /expenses/<id>` | ✅ |
| Xarajat turlari | `GET /expense_categories` | ✅ |
| Tur qo'shish | `POST /expense_categories` | ✅ |
| Kategoriya kesimida yig'indi | `GET /reports/expenses` | ❌ D2 |

### 2.9. Mijozlar

| Blok | Endpoint | Holat |
|---|---|---|
| Ro'yxat + qidiruv | `GET /customers?search&limit&offset` | ✅ |
| Yaratish/tahrirlash | `POST /customers` | ✅ |
| O'chirish | `DELETE /customers/<id>` | ✅ |
| Qarzdorlar ro'yxati | `GET /customers?has_debt=true&sort=debt_desc` | ❌ E1 |
| Mijoz kartasi (qarz tarixi bilan) | `GET /customers/<id>` | ❌ E2 |

### 2.10. Ombor

| Blok | Endpoint | Holat |
|---|---|---|
| Qoldiq (xomashyo + mahsulot) | `GET /inventory/stock?kind&low_only` | ✅ |
| Harakatlar tarixi | `GET /inventory/movements?start&end&types&source&item_id&search&limit&offset` | ✅ |
| Element kartasi (bitta xomashyo tarixi) | `GET /inventory/movements?item_id=<id>` | ✅ |
| Retseptlar (nima nimadan tayyorlanadi) | `GET /recipes/<product_id>` | ❌ F3 |

> Ombor **faqat o'qish** — bu qaror §0 da.

### 2.11. Xodimlar

| Blok | Endpoint | Holat |
|---|---|---|
| Ofitsiantlar ro'yxati | `GET /waiters` | ✅ |
| Yaratish/tahrirlash (huquqlar, PIN) | `POST /waiters` | ✅ |
| O'chirish (+ sessiyalarni yopadi) | `DELETE /waiters/<id>` | ✅ |
| Admin/kassirlar | `GET /users`, `POST /users`, `DELETE /users/<id>` | ✅ |
| Ofitsiant hisob-kitobi (xizmat haqi qoldig'i) | `GET /waiters/<id>/summary?start&end` | ❌ F1 |
| Ofitsiantga to'lov tarixi | `GET /waiter_payments?waiter_id&start&end` | ❌ F1 |
| To'lov qo'shish | `POST /waiter_payments` | ❌ F1 |

### 2.12. Menyu boshqaruvi

| Blok | Endpoint | Holat |
|---|---|---|
| Mahsulotlar ro'yxati | `GET /products` | ✅ (filtr/sahifalash yo'q) |
| Qidiruv, kategoriya, faollik filtri | `GET /products?search&category_id&is_active&limit&offset` | ❌ A3 |
| Mahsulot qo'shish/tahrirlash (narx!) | `POST /products` | ❌ A1 |
| Mahsulotni o'chirish/yashirish | `DELETE /products/<id>` | ❌ A1 |
| Kategoriyalar | `GET /categories` | ✅ |
| Kategoriya CRUD | `POST /categories`, `DELETE /categories/<id>` | ❌ A2 |
| Rasm yuklash | `POST /upload/image` | ✅ |
| Rasmni ko'rsatish | `GET /uploads/<file>` | ✅ |

> **Bu bo'lim admin ilovasining eng qimmatli qismi** — rahbar narxni
> telefondan o'zgartira olishi kerak. Hozir bu **umuman yo'q**: server
> menyuni faqat o'qishga beradi.

### 2.13. Zal/stol sozlamalari

| Blok | Endpoint | Holat |
|---|---|---|
| Zallar CRUD | `GET/POST /locations`, `DELETE /locations/<id>` | ✅ |
| Stollar CRUD | `GET/POST /tables`, `DELETE /tables/<id>` | ✅ |

### 2.14. Sozlamalar

| Blok | Endpoint | Holat |
|---|---|---|
| Sozlamalarni o'qish (oq ro'yxat, 21 kalit) | `GET /settings` | ✅ |
| Sozlamani o'zgartirish | `POST /settings` | ❌ J1 |
| Printerlar ro'yxati | `GET /printers` | ✅ |

### 2.15. Nazorat va bildirishnomalar

| Blok | Endpoint | Holat |
|---|---|---|
| Audit jurnali (kim nimani o'chirdi) | `GET /audit_logs?start&end&user_id&action` | ❌ H1 |
| Push bildirishnoma ro'yxatdan o'tishi | `POST /push/register` | ❌ I1 |
| Ro'yxatdan chiqish | `DELETE /push/register` | ❌ I1 |

---

## 3. Mavjud endpoint'lar — xulosa

Serverda **56 route** bor. Admin ilovasi ulardan **34 tasini** ishlatadi va
ularning hammasi bugun ishlaydi:

```
POST   /auth/login              GET    /reports/periods
GET    /auth/me                 GET    /reports/stats
POST   /auth/logout             GET    /reports/hourly
                                GET    /reports/orders
GET    /admin/dashboard         GET    /reports/products
GET    /admin/shift/current     GET    /reports/waiters
                                GET    /reports/locations
GET    /orders                  GET    /reports/tables
GET    /orders/<id>             GET    /reports/shifts
                                GET    /reports/zreport
GET    /tables/summary
GET    /tables                  GET    /inventory/stock
POST   /tables                  GET    /inventory/movements
DELETE /tables/<id>
GET    /locations               GET    /customers
POST   /locations               POST   /customers
DELETE /locations/<id>          DELETE /customers/<id>
                                GET    /transactions
GET    /products                POST   /transactions
GET    /categories              GET    /expenses
GET    /printers                POST   /expenses
GET    /settings                DELETE /expenses/<id>
                                GET    /expense_categories
GET    /waiters                 POST   /expense_categories
POST   /waiters
DELETE /waiters/<id>            POST   /upload/image
GET    /users                   GET    /uploads/<file>
POST   /users
DELETE /users/<id>              WS     /ws
```

**Xulosa:** admin ilovasining ~75% i bugungi API ustida qurilishi mumkin.
Yetishmayotgani asosan **yozish** (menyu, sozlama) va **detal** (mijoz
kartasi, smena tafsiloti) endpoint'lari.

---

## 4. Yetishmayotgan endpoint'lar — spetsifikatsiya

Har biri: nima uchun kerak, so'rov, javob, huquq.

---

### A. Menyu boshqaruvi

#### A1 · `POST /products` va `DELETE /products/<id>` 🔒 admin

**Nega:** rahbar narxni, mavjudlikni, rasmni telefondan o'zgartirishi kerak.
Bugun bu faqat desktopda mumkin.

```http
POST /products
{
  "id": 10,                    // yo'q bo'lsa — yangi mahsulot
  "name": "Osh (Palov)",
  "price": 38000,
  "category": "Asosiy taomlar",
  "image_path": "1712345678.jpg",
  "unit": "portsiya",
  "track_type": 1,
  "is_set": 0,
  "is_active": 1,
  "no_service_charge": 0
}
```

**Javob:** `{ "id": 10, "status": "success" }` — yangi yaratilganda ham `id`
qaytsin, ilova ro'yxatni qayta yuklamasin.

**Qoidalar:**
- `quantity` (ombor qoldig'i) bu endpoint orqali **o'zgartirilmaydi** —
  u faqat `stock_movements` orqali o'zgaradi (§0 qoidasi).
- `DELETE` — mahsulot buyurtmalarda ishlatilgan bo'lsa **o'chirilmaydi**,
  `is_active = 0` qilinadi va `409` bilan sabab qaytariladi.
- Har o'zgarish `audit_logs` ga yoziladi — pastdagi A1a qat'iy talab.
- WS: `catalog_updated` signali (K3) — POS menyuni yangilaydi.

#### A1a · Audit talabi (qaror: 2026-08-23) ⚠️ majburiy

> **Qaror qabul qilindi:** narxni telefondan o'zgartirishga **ruxsat beriladi**,
> lekin faqat `admin` roliga va **har bir o'zgarish `audit_logs` ga yozilishi
> sharti bilan**. Auditsiz bu endpoint chiqarilmasin.

Infratuzilma allaqachon bor — qayta yozilmaydi:

| Nima | Qayerda | Holat |
|---|---|---|
| `AuditService.instance.logAction(...)` | `lib/core/services/audit_service.dart` | ✅ |
| `audit_logs` jadvali: `user_id, action, entity, entity_id, before_json, after_json, created_at` | `database_helper.dart` | ✅ |
| `edit_product` amali (eski→yangi to'liq `toMap()`) | `product_provider.dart:96` | ✅ |

**Lekin ikkita bo'shliq bor va ular aynan shu endpoint uchun to'sqinlik qiladi:**

1. **`client` rejimda audit yozilmaydi.** `ProductProvider.updateProduct`
   auditni `if (!isClient)` sharti bilan yozadi — ya'ni tarmoq mijozi
   o'zgartirsa, iz qolmaydi. Admin ilovasi aynan tarmoq mijozi bo'ladi.
   → **Audit `POST /products` endpoint'ining ichida, serverda yozilsin**,
   provider'ga tayanmasin.

2. **`user_id` hech qayerda uzatilmaydi.** Mavjud 5 ta `logAction` chaqiruvida
   `userId` berilmagan — jurnalda "kim" ustuni doim bo'sh. Audit'ning butun
   ma'nosi shu ustunda.
   → Endpoint `ApiContext.sessionOf(request)` dan `userId` ni olib uzatsin.

**Talab qilinadigan yozuv:**

```dart
// POST /products ichida, o'zgarish saqlangandan keyin
final session = ApiContext.sessionOf(request);
await AuditService.instance.logAction(
  userId:   session.userId,               // ← majburiy, bo'sh qolmasin
  action:   isNew ? 'create_product' : 'edit_product',
  entity:   'product',
  entityId: id.toString(),
  before:   oldRow,                       // yangi mahsulotda null
  after:    newRow,
);
```

| Endpoint | `action` | `entity` |
|---|---|---|
| `POST /products` (yangi) | `create_product` | `product` |
| `POST /products` (tahrir) | `edit_product` | `product` |
| `DELETE /products/<id>` | `delete_product` | `product` |
| `POST /categories` | `create_category` / `edit_category` | `category` |
| `DELETE /categories/<id>` | `delete_category` | `category` |
| `POST /settings` (J1) | `edit_setting` | `setting` |
| `POST /waiter_payments` (F1) | `waiter_payment` | `waiter` |

**Narx o'zgarishi alohida ko'rinsin.** `before_json`/`after_json` to'liq
yozuvni saqlaydi, lekin admin ilovasi jurnalda "narx 35 000 → 38 000" ni
darhol ko'rsata olishi kerak. Buning uchun `GET /audit_logs` (H1) javobida
`changed_fields` hisoblab berilsin (§H1).

**Test:** `test/api_admin_test.dart` ga qo'shilsin — `POST /products` dan
keyin `audit_logs` da `user_id` to'ldirilgan yozuv paydo bo'lishi.

#### A2 · `POST /categories`, `DELETE /categories/<id>` 🔒 admin

```http
POST /categories
{ "id": 3, "name": "Ichimliklar", "sort_order": 2, "color": "#FF8800" }
```

`DELETE` — ichida mahsulot bo'lsa `409`.

#### A3 · `GET /products` filtrlari

```
?search=<matn>        ism bo'yicha
?category_id=<int>
?is_active=<0|1>
?limit&offset
```

**Nega:** menyu 500+ mahsulotga yetganda telefonga hammasini yuklash noto'g'ri.
Orqaga muvofiqlik: parametrsiz — bugungi yalang'och massiv.

#### A4 · `GET /orders/<id>` javobini kengaytirish

Hozir to'lov ma'lumoti yo'q. Qo'shilsin:

```json
{
  "...": "mavjud maydonlar",
  "payments": [
    { "payment_type": "cash", "amount": 150000.0, "created_at": "..." },
    { "payment_type": "card", "amount": 53500.0,  "created_at": "..." }
  ],
  "discount_total": 0.0,
  "table_name": "Stol #1",
  "location_name": "Yozgi ayvon",
  "waiter_name": "Aziz",
  "shift_id": 108
}
```

**Nega:** admin "bu chek qanday to'langan?" degan savolga javob olishi kerak.
Bo'lingan to'lov (`order_payments`) bugun tarmoqqa umuman chiqmaydi.

---

### B. Smenalar

#### B1 · `GET /shifts/<id>` 🔒 admin

Yopilgan smenaning to'liq kartasi — desktopdagi `close_shift_screen` ning
o'qish varianti.

```json
{
  "id": 108,
  "status": "closed",
  "opened_at": "2026-08-20T09:00:00.000",
  "closed_at": "2026-08-20T23:40:00.000",
  "opened_by_name": "Admin",
  "closed_by_name": "Admin",
  "opening_cash": 500000.0,
  "counted_cash": 3470000.0,
  "expected_cash": 3480000.0,
  "difference": -10000.0,
  "order_count": 42,
  "summary": {
    "cash": 3100000.0, "card": 2300000.0, "terminal": 0.0,
    "debt": 0.0, "bonus": 0.0, "transfer": 0.0,
    "total_sales": 5400000.0, "discount": 45000.0,
    "expenses": 120000.0, "in_movements": 0.0, "out_movements": 120000.0
  },
  "cash_movements": [
    { "type": "out", "amount": 120000.0, "note": "Bozor", "created_at": "..." }
  ],
  "expenses": [
    { "id": 55, "category_name": "Mahsulot", "amount": 120000.0, "note": "Guruch" }
  ]
}
```

`difference` — **kassa farqi**. Rahbar telefonda birinchi qaraydigan raqam.

#### B2 · `GET /shifts` sahifalash

Hozir `/reports/shifts?limit=20` bor, lekin `offset` yo'q — eski smenalarga
o'tib bo'lmaydi. `?limit&offset&status` qo'shilsin (`Pagination` klassi
allaqachon bor).

---

### C. Kassa harakatlari

#### C1 · `GET /cash_movements` 🔒 admin

`cash_movements` jadvali bor, lekin tarmoqqa chiqmaydi.

```
?shift_id=<int>  ?start  ?end  ?type=in|out  ?limit&offset
```

```json
[
  { "id": 12, "shift_id": 108, "type": "out", "amount": 120000.0,
    "note": "Bozorga", "user_name": "Admin", "created_at": "..." }
]
```

> **Yozish (`POST`) qo'shilmasin** — kassadan pul olish fizik amal (§0).

---

### D. Xarajatlar

#### D1 · `GET /expenses` filtrlari 🔒 admin

Hozir **filtr umuman yo'q** — butun tarix sana tartibida qaytadi. Kerak:

```
?start  ?end  ?category_id  ?shift_id  ?limit&offset
```

Javobga `category_name` qo'shilsin (hozir faqat `category_id`, ilova ikkinchi
so'rov yubormasin).

#### D2 · `GET /reports/expenses` 🔒 admin

Kategoriya kesimida yig'indi — hisobot ekranida "nimaga qancha ketdi".

```json
{
  "total": 1240000.0,
  "by_category": [
    { "category_id": 2, "name": "Mahsulot", "total": 890000.0, "count": 14 }
  ],
  "by_day": [ { "date": "2026-08-20", "total": 120000.0 } ]
}
```

---

### E. Mijozlar

#### E1 · `GET /customers` — qarzdorlar filtri 🔒 admin

```
?has_debt=true      faqat qarzi borlar
?sort=debt_desc     qarz bo'yicha kamayish tartibida
```

**Nega:** "kim qancha qarz?" — admin ilovasining eng ko'p ochiladigan ro'yxati.
Hozir butun bazani yuklab, telefonda saralash kerak.

#### E2 · `GET /customers/<id>` 🔒 admin

Mijoz kartasi — bitta so'rovda.

```json
{
  "customer": { "id": 7, "name": "Alisher", "phone": "+998901234567",
                "debt": 450000.0, "credit": 0.0 },
  "transactions": [
    { "id": 91, "type": "outlay", "amount": 200000.0,
      "note": "Nasiya", "created_at": "..." }
  ],
  "orders": [
    { "id": "1712345678901", "grand_total": 200000.0, "created_at": "..." }
  ],
  "totals": { "order_count": 34, "lifetime_value": 4200000.0 }
}
```

#### E3 · `GET /transactions?start&end` 🔒 admin

Sana filtri (hozir faqat `customer_id`).

---

### F. Xodimlar hisob-kitobi

#### F1 · Ofitsiant to'lovlari 🔒 admin

`waiter_payments` jadvali bor, tarmoqqa chiqmaydi. Desktopdagi
`waiter_payments_screen` va `waiter_profile_screen` ning API ekvivalenti.

```http
GET /waiters/<id>/summary?start=<ISO>&end=<ISO>
```
```json
{
  "waiter": { "id": 5, "name": "Aziz", "type": 0, "value": 10 },
  "period": { "start": "...", "end": "..." },
  "sales":       { "order_count": 214, "revenue": 28400000.0 },
  "service_fee": { "earned": 2840000.0, "paid": 2000000.0, "balance": 840000.0 }
}
```

```http
GET  /waiter_payments?waiter_id=<id>&start&end&limit&offset
POST /waiter_payments   { "waiter_id": 5, "amount": 500000, "note": "Avans" }
```

> `POST` — bu yagona istisno pul yozuvi bo'lib, telefonda ma'noli:
> rahbar ofitsiantga avans berganini darhol yozib qo'yadi.
> `audit_logs` ga majburiy yozilsin.

#### F2 · `GET /reports/waiters` javobiga xizmat haqi

Hozir faqat savdo. `service_earned` va `service_paid` qo'shilsa, ofitsiantlar
ekranida ikkinchi so'rov kerak bo'lmaydi.

#### F3 · `GET /recipes/<product_id>` 🔒 admin

Mahsulot nimadan tayyorlanadi + tannarx. Ombor ekranida "nega guruch tez
tugayapti?" savoliga javob.

```json
{
  "product_id": 10,
  "cost_price": 18400.0,
  "items": [
    { "ingredient_id": 4, "name": "Guruch", "qty": 0.25, "unit": "kg", "cost": 3500.0 }
  ]
}
```

---

### G. Yetkazib berish va saboy

#### G1 · `GET /couriers`, `GET /delivery_zones` 🔒 admin

Jadvallar bor, endpoint yo'q. Yetkazib berish hisoboti uchun kerak.

#### G2 · `GET /orders/<id>` — delivery maydonlari

`order_type = 2` bo'lganda javobga qo'shilsin:

```json
{
  "delivery": {
    "courier_id": 3, "courier_name": "Bobur", "zone_name": "Chilonzor",
    "delivery_fee": 15000.0, "address": "...", "phone": "+998...",
    "status": "delivered"
  }
}
```

#### G3 · `GET /orders?order_type=2` — allaqachon ishlaydi ✅

---

### H. Nazorat

#### H1 · `GET /audit_logs` 🔒 admin

`audit_logs` jadvali to'ladi, lekin hech qayerda ko'rinmaydi — na desktopda,
na tarmoqda. A1a qarori bilan bu endpoint **majburiy** bo'ldi: narx telefondan
o'zgartiriladigan bo'lsa, uni ko'radigan joy ham bo'lishi kerak.

```
?start  ?end  ?user_id  ?entity=product|order|setting|...
?action=edit_product|delete_product|change_table|...  ?entity_id  ?limit&offset
```

Javob — jadvalning haqiqiy ustunlari (`before_json`/`after_json`) ustiga
ilova uchun ikkita hisoblangan maydon qo'shiladi:

```json
[
  {
    "id": 4102,
    "user_id": 1,
    "user_name": "Admin",
    "action": "edit_product",
    "entity": "product",
    "entity_id": "10",
    "created_at": "2026-08-23T14:30:00.000",
    "changed_fields": [
      { "field": "price", "before": 35000.0, "after": 38000.0 }
    ],
    "before_json": { "id": 10, "name": "Osh (Palov)", "price": 35000.0 },
    "after_json":  { "id": 10, "name": "Osh (Palov)", "price": 38000.0 }
  }
]
```

- `user_name` — `users`/`waiters` bilan `LEFT JOIN` (jadvalda faqat `user_id` bor).
- `changed_fields` — serverda `before_json` va `after_json` ni solishtirib
  hisoblanadi. **Nega serverda:** telefon ikkita to'liq JSON ni yuklab,
  o'zi solishtirmasin — jurnalda yuzlab yozuv bo'ladi.
- Ro'yxat so'ralganda `before_json`/`after_json` **yuborilmasin**
  (`?full=true` bo'lmasa) — trafikni tejash uchun.

**Bugun yoziladigan amallar** (koddan):

| `action` | Qayerda | `user_id` |
|---|---|---|
| `edit_product` | `product_provider.dart:96` | ❌ bo'sh |
| `change_waiter` | `cart_provider.dart:255` | ❌ bo'sh |
| `change_table` | `cart_provider.dart:1698` | ❌ bo'sh |
| `merge_table` | `cart_provider.dart:1758` | ❌ bo'sh |
| `refund_inventory` | `inventory_service.dart:461` | ❌ bo'sh |

> ⚠️ **Beshtasida ham `user_id` uzatilmaydi** — jurnal bor, lekin "kim"
> ustuni doim bo'sh. H1 bilan birga bu tuzatilsin, aks holda endpoint
> foydasiz ma'lumot qaytaradi.

**Yozilmaydigan, lekin yozilishi kerak bo'lgan amallar:**
buyurtmani bekor qilish (`cancel_order`), chekni qayta chop etish
(`reprint_receipt`), narxni savatda o'zgartirish (`edit_price` — ofitsiant
huquqi bor, lekin izi yo'q), smena yopilishi (`close_shift`).

**Nega:** admin ilovasining ishonch qiymati shu yerda — "kim chekni o'chirdi?",
"narxni kim tushirdi?"

---

### I. Push bildirishnomalar

#### I1 · `POST /push/register` / `DELETE /push/register`

```json
{ "token": "<FCM token>", "platform": "android", "device_name": "Pixel 8" }
```

Server yuboradigan hodisalar:

| Hodisa | Kimga | Matn |
|---|---|---|
| Smena yopildi | admin | "Smena yopildi. Tushum: 5 400 000. Kassa farqi: −10 000" |
| Kassa farqi > chegara | admin | "⚠️ Kassa farqi 120 000 so'm" |
| Xomashyo tugadi | admin | "Guruch: 2 kg qoldi" |
| Buyurtma bekor qilindi | admin | "Aziz 185 000 so'mlik buyurtmani bekor qildi" |

> **Muhim:** push filialdagi POS'dan emas, cloud'dan yuborilishi kerak
> (telefon LAN'dan tashqarida bo'ladi). Ya'ni bu **Faza 1 ga bog'liq**
> ([`05_MOBIL_FILIAL_SYNC.md`](05_MOBIL_FILIAL_SYNC.md)). Vaqtinchalik
> yechim — Telegram bot (allaqachon bor).

---

### J. Sozlamalar

#### J1 · `POST /settings` 🔒 admin

```json
{ "restaurant_name": "Zelly Cafe", "auto_confirm_order": "1" }
```

**Cheklov:** faqat oq ro'yxatdagi kalitlar (`GET /settings` dagi 21 ta) +
admin ilovasi uchun qo'shiladiganlar: `day_reset_time`, `service_percentage`,
`currency_symbol`. Boshqa kalit yuborilsa — `400`, ruxsat etilgan ro'yxat bilan.

**Nega cheklov:** `settings` da printer portlari, litsenziya va tarmoq
sozlamalari ham bor — ular telefondan o'zgartirilmasin.

---

### K. Infratuzilma

#### K1 · `GET /server/info` — **token talab qilmaydi**

Ilova QR skanerlagandan keyin serverni tekshiradi.

```json
{
  "app": "Zelly POS", "version": "1.0.21", "api_version": "2.2",
  "restaurant_name": "Zelly Cafe", "branch_name": "Chilonzor",
  "server_time": "2026-08-23T14:30:00.000",
  "features": { "inventory": true, "delivery": true }
}
```

`server_time` — telefon soati bilan farqni tekshirish uchun
(sync uchun ham kerak bo'ladi, `05_...` §2.5).

#### K2 · `GET /health` — token talab qilmaydi

`{ "ok": true }` — ulanish tekshiruvi, avtomatik LAN↔cloud almashish uchun.

#### K3 · Yangi WebSocket hodisalari

Hozir faqat `tables_updated` va `order_updated`. Admin ilovasi uchun:

| Event | Qachon | Maydonlar |
|---|---|---|
| `order_paid` | To'lov yakunlandi | `order_id`, `grand_total` |
| `bill_requested` | Mijoz hisob so'radi | `table_id`, `order_id` |
| `shift_closed` | Smena yopildi | `shift_id`, `difference` |
| `catalog_updated` | Menyu o'zgardi | `entity` (`product`/`category`) |

#### K4 · `/v1/` prefiksi

Admin ilovasi versiyasi serverdan orqada qolishi tabiiy holat. Prefiks
qo'shilganda eski yo'llar **kamida 6 oy** ishlab tursin.

#### K5 · TLS

Telefon → LAN trafigi hozir ochiq (`API.md` §8). Admin ilovasi hisobot va
mijoz telefon raqamlarini uzatadi — bu ofitsiant ilovasidan **maxfiyroq**.

---

## 5. Bosqichlar

Har bosqich oxirida ishlaydigan ilova bo'ladi.

### MVP-1 — "Kuzatish" · server ishi deyarli yo'q 🎉

Faqat mavjud API ustida quriladi:

- Login → Dashboard → Jonli zal → Buyurtmalar → Hisobotlar → Ombor (o'qish)
- Zarur endpoint'lar: **hammasi bor**
- Qo'shiladigan yagona narsa: `GET /health`, `GET /server/info` (K1, K2) —
  QR bilan ulanish uchun, ~50 satr kod

> **Bu allaqachon to'liq qiymatli ilova.** Rahbar telefondan kafeni ko'radi.

### MVP-2 — "Nazorat"

| # | Endpoint | Sabab |
|---|---|---|
| A4 | `GET /orders/<id>` + `payments` | Chek qanday to'langan |
| B1 | `GET /shifts/<id>` | Kassa farqi |
| B2 | `GET /shifts` sahifalash | Eski smenalar |
| C1 | `GET /cash_movements` | Kassa kirim/chiqim |
| D1 | `GET /expenses` filtrlari | Davr bo'yicha xarajat |
| E1, E2 | Qarzdorlar + mijoz kartasi | Eng ko'p so'raladigan ro'yxat |
| H1 | `GET /audit_logs` | Kim nima qildi |

Taxminan ~1 hafta server ishi.

### MVP-3 — "Boshqarish"

| # | Endpoint | Sabab |
|---|---|---|
| **H1** | `GET /audit_logs` + `user_id` tuzatish | **A1 ning sharti** — MVP-2 dan ko'chirilsa ham, A1 dan **oldin** bo'lsin |
| A1, A1a, A2, A3 | Menyu CRUD + audit | Narxni telefondan o'zgartirish (qaror: 2026-08-23) |
| J1 | `POST /settings` | Sozlamalar |
| F1, F2 | Ofitsiant hisob-kitobi | Avans va xizmat haqi |
| D2 | `GET /reports/expenses` | Xarajat hisoboti |
| K3 | Yangi WS hodisalari | Real-time |

### MVP-4 — "Tashqaridan" · cloud'ga bog'liq

| # | Nima | Bog'liqlik |
|---|---|---|
| I1 | Push bildirishnomalar | Cloud (Faza 1) |
| G1, G2 | Yetkazib berish | — |
| K4 | `/v1/` versiyalash | — |
| K5 | TLS | — |
| — | Ko'p filial dashboard | Cloud (Faza 3) |

> MVP-1 dan MVP-3 gacha **cloud kerak emas** — ilova LAN'da yoki mavjud
> Cloudflare Tunnel orqali ishlaydi.

---

## 6. Hujjat qarzi (`API.md` ga qo'shilishi kerak)

Kodda bor, hujjatda yo'q:

1. Hisobot endpoint'larining `?shift_id`, `?order_type`, `?location_id`,
   `?waiter_id` filtrlari (§2.5).
2. `GET /reports/stats` javob tuzilmasi: `{ metrics, topQty, topRevenue }`.
3. `GET /reports/zreport` javob tuzilmasi: `{ summary, waiterSales,
   categorySales, topProducts }`.
4. `GET /reports/shifts` javob maydonlari.
5. `GET /transactions?customer_id` filtri.
6. `/reports/zreport` da to'lov turlari o'zbekcha nomlardan (`Naqd`, `Karta`,
   `Nasiya`) inglizchaga aylantiriladi — mijoz buni bilishi kerak.

---

## 7. Qaror kerak bo'lgan savollar

1. ~~**Menyu narxini telefondan o'zgartirishga ruxsat beramizmi?**~~
   ✅ **QAROR (2026-08-23): ha — `audit_logs` ga yozib.**
   Shartlar §4 A1a da qat'iy yozildi: faqat `admin` roli; audit
   **serverda**, endpoint ichida yoziladi (provider'dagi `if (!isClient)`
   sharti tarmoq mijozini o'tkazib yuboradi); `user_id` majburiy
   to'ldiriladi; `GET /audit_logs` (H1) shu bilan birga chiqadi.
   **Auditsiz `POST /products` chiqarilmaydi.**
2. **Ofitsiantga avans (F1) telefondan yozilsinmi?** Tavsiya: ha —
   bu naqd kassaga tegmaydi, alohida hisob.
3. **Admin ilovasi offline ishlashi kerakmi?** Tavsiya: **yo'q** —
   oxirgi ko'rilgan dashboard keshlansin, xolos. Eski ma'lumot ko'rsatish
   noto'g'ri qaror qabul qilishga olib keladi.
4. **Bitta ilova (admin + ofitsiant) yoki ikkita?**
   [`05_...`](05_MOBIL_FILIAL_SYNC.md) §4.2 bitta ilovani tavsiya qiladi
   (login rolga qarab ekranni tanlaydi). Bu qaror kuchida qoladimi?
5. **Push kanali:** FCM (cloud kerak) yoki vaqtincha Telegram bot
   (bugun ishlaydi)?
6. **iOS kerakmi?** Faqat Android bo'lsa MVP-1 ~2 hafta tezroq.
