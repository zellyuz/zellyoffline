# Arxitektura Tahlili va Tavsiyalar

> Bog'liq: [`00_OVERVIEW.md`](00_OVERVIEW.md) · [`04_ROADMAP.md`](04_ROADMAP.md)

Bu hujjat loyihaning arxitektura holatini global standartlar (Clean
Architecture, SOLID, layered design) nuqtai nazaridan tahlil qiladi.

---

## 1. Hozirgi arxitektura

Loyiha **feature-first + Provider** yondashuvidan foydalanadi. Bu yaxshi asos,
lekin qatlamlar aniq ajratilmagan.

```
┌─────────────────────────────────────────────┐
│  PRESENTATION  (lib/features/*)              │
│  Ekranlar + Widget'lar                       │
│  ⚠️ ba'zilari to'g'ridan-to'g'ri SQL yozadi  │
└───────────────┬─────────────────────────────┘
                │
┌───────────────▼─────────────────────────────┐
│  STATE  (lib/providers/*)  ChangeNotifier    │
│  ⚠️ business logic + SQL + state bir joyda   │
└───────────────┬─────────────────────────────┘
                │  (repository qatlami ko'pincha yo'q)
┌───────────────▼─────────────────────────────┐
│  DATA  (lib/core/database_helper.dart)       │
│  60 jadval, 54 migratsiya — bitta faylda     │
└─────────────────────────────────────────────┘
```

---

## 2. Asosiy muammolar

### 🔴 2.1. Ma'lumotlarga kirish qatlami (Data Layer) yo'q

SQL so'rovlari butun kod bazasiga tarqalgan:

- **18 / 19 provider** `DatabaseHelper`ga to'g'ridan-to'g'ri murojaat qiladi.
- **10 ta ekran** (`pos_screen`, `dashboard_screen`, `login_screen`,
  `order_details_dialog`, `filter_bar`, `payment_dialog`, ...) o'zi `rawQuery`
  yozadi — bu qatlam buzilishining eng og'ir ko'rinishi.
- Repository qatlami faqat **2 modulda** (`inventory`, `shift`) bor —
  demak pattern boshlangan, lekin oxirigacha yetkazilmagan.

**Nega muammo:**
- Bir jadval sxemasi o'zgarsa, o'nlab joyni qidirib tuzatish kerak.
- SQL'ni test qilib bo'lmaydi (UI'ga bog'langan).
- Bir xil so'rov bir necha joyda takrorlanadi (DRY buzilishi).

**Tavsiya:** Har bir domen uchun repository joriy qilish va **barcha SQL'ni
faqat repository ichida** saqlash:

```
lib/data/
├── datasources/
│   └── local/  (DatabaseHelper — faqat ulanish + migratsiya)
└── repositories/
    ├── product_repository.dart
    ├── order_repository.dart
    ├── customer_repository.dart
    └── ...  (har bir domen uchun)
```

Provider'lar faqat repository'ni chaqiradi:
```dart
class ProductProvider extends ChangeNotifier {
  final ProductRepository _repo;
  ProductProvider(this._repo);

  Future<void> loadProducts() async {
    _products = await _repo.getAll();   // ← SQL emas
    notifyListeners();
  }
}
```

Qoida: **ekran (feature) hech qachon `DatabaseHelper`ni import qilmasligi
kerak.**

---

### 🔴 2.2. "God files" — juda katta fayllar

| Fayl | Satr | Muammo |
|------|-----:|--------|
| ~~`api_server.dart`~~ | ~~2 830~~ | ✅ bo'lindi — §4.7 |
| `pos_screen.dart` | 2 422 | UI + business logic + SQL aralash |
| `printing_service.dart` | 2 221 | Har xil chek turlari bitta klassda |
| `database_helper.dart` | 2 176 | 60 jadval + migratsiya + failsafe hack |
| `cart_provider.dart` | 2 043 | Savat + to'lov + chop etish + SQL |

**Tavsiya:**
- ~~`api_server.dart` → route'larni modul bo'yicha bo'lish~~ ✅ bajarildi (§4.7).
- `pos_screen.dart` → kichik widget'larga va logika provider/servicega.
- `printing_service.dart` → `ReceiptBuilder`, `ShiftReportBuilder` kabi
  alohida klasslarga.
- `database_helper.dart` → jadval sxemalarini va migratsiyalarni alohida
  fayllarga (`schema/`, `migrations/`) chiqarish.

Amaliy o'lchov: **bitta fayl ~400 satrdan oshsa, bo'lishni ko'rib chiqing.**

---

### 🟡 2.3. Business logic UI va provider'da aralashgan

`cart_provider.dart` ichida savat holati bilan birga to'lov hisob-kitobi,
chop etish chaqiruvlari va SQL bor. `use_build_context_synchronously`
ogohlantirishlari (36 ta) shuni ko'rsatadiki, provider `BuildContext`ni
async operatsiyalar orasida ushlab turibdi — bu Provider modelini buzadi.

**Tavsiya:** hisob-kitob va biznes qoidalarini `core/services/` ichidagi
sof (context'siz) service klasslarga chiqarish. Provider faqat holat +
service chaqiruvi bo'lib qolsin.

---

### 🟡 2.4. Migratsiya qarzi (`database_helper.dart`)

Kodda "failsafe" bloklar bor — ilova ishga tushganda ustun bor-yo'qligini
tekshirib, yo'q bo'lsa `ALTER TABLE` qiladi:

```dart
try {
  await db.rawQuery('SELECT permissions FROM users LIMIT 1');
} catch (e) {
  if (e.toString().contains('no such column')) {
    await db.execute('ALTER TABLE users ADD COLUMN permissions TEXT');
  }
}
```

Bu migratsiya tizimiga to'liq ishonilmasligining belgisi. 54 versiya +
runtime failsafe = texnik qarz.

**Tavsiya:** barcha sxema o'zgarishlarini tartibli `_onUpgrade` migratsiyalarida
saqlash; runtime failsafe'larni bosqichma-bosqich olib tashlash.

---

### 🟢 2.5. Yaxshi tomonlar (saqlab qolinsin)

- **Modellar toza:** immutable, `toMap`/`fromMap`, `copyWith` (sentinel bilan
  null-ni to'g'ri boshqaradi). Bu global standartga mos.
- **Feature-first** papka tuzilishi.
- Markazlashgan `AppLogger`, `AppTheme`, tarjima tizimi.
- `runZonedGuarded` + `FlutterError.onError` bilan global xato ushlash.
- `DatabaseHelper`da `databasePathOverride` — testlar uchun o'ylangan.

---

## 3. Maqsadli arxitektura (tavsiya)

```
lib/
├── core/            # framework, DI, logger, theme, xatolar, utils
├── data/
│   ├── datasources/ # SQLite ulanish, API mijoz
│   ├── models/      # DTO / DB modellar (hozirgi models/ shu yerga)
│   └── repositories/# har bir domen uchun (SQL faqat shu yerda)
├── domain/          # (ixtiyoriy) entity + use-case + repo interfeyslari
├── presentation/    # = hozirgi features/ (UI + provider)
│   └── <feature>/
│       ├── screens/
│       ├── widgets/
│       └── providers/
└── main.dart
```

Minimal (kam xarajatli) variant — `domain/` qatlamsiz:
`UI → Provider → Repository → DataSource`. Bu loyiha uchun eng amaliy qadam.

---

## 4. Dependency Injection

Hozir `main.dart`da 19 provider qo'lda `MultiProvider` da ro'yxatlangan va
ba'zilari `..loadProducts()` kabi yon ta'sir bilan yaratiladi. Repository
joriy qilingach, provider'lar repository'ni **konstruktor orqali** olishi
kerak (`ProxyProvider` yoki oddiy `create`da uzatish). Bu test qilishni
osonlashtiradi.

---

## 4.5. Bajarilgan ishlar (Data Layer) — 2026-08-07 ✅ TUGADI

> **Data layer to'liq joriy qilindi (100%).**
> - Barcha **18 provider** ma'lumotga faqat repozitoriy orqali murojaat qiladi.
> - **Barcha 10 ekrandagi** to'g'ridan-to'g'ri SQL olib tashlandi —
>   `lib/features/` da endi bitta ham `DatabaseHelper`/`rawQuery` yo'q.
> - Yagona istisno — `connectivity_provider`, u remote data source (server
>   mijozi)ning o'zi bo'lgani uchun ataylab `DatabaseHelper`ni ishlatadi.
> - Jami **18 repozitoriy**. `flutter analyze`: **0 xato**; savat charge testi
>   o'tadi.
>
> Natijada `UI → Provider → Repository → DataSource(SQLite/API)` arxitekturasi
> izchil qo'llanildi. §2.1 dagi "data layer yo'q" muammosi **hal qilindi**.

**Batafsil:** `lib/data/repositories/` yaratildi:

- **`BaseRepository<T>`** — umumiy lokal/remote CRUD (getAll + remote→lokal
  kesh, add/update/deleteById, client-rejim tarmoqqa yo'naltirish).
- Migratsiya qilingan domenlar (SQL provider'lardan olib tashlandi):
  `category`, `location`, `customer`, `waiter`, `table`, `user`, `saboy`,
  `developer`, `expense` — **9 domen**.
- **`OrderRepository`** — `cart_provider.dart` (2043 satr) dagi barcha lokal SQL
  (`orders`/`order_items`/`tables`/`products`) shu yerga ko'chirildi. Provider
  faqat orkestratsiyani (HTTP client rejim, WebSocket broadcast, chop etish,
  audit, savat holat-mashinasi) saqlaydi. Tranzaksiya chegaralari aynan
  saqlangan; `commitCheckout` yakuniy to'lovni bitta tranzaksiyada bajaradi.
- **`DeliveryRepository`** — `delivery_provider.dart` (kuryerlar, hududlar,
  yetkazish buyurtmalari, statistika, telefon qidiruv, checkout, createOrder)
  dagi barcha SQL shu yerga ko'chirildi. Provider savat holati, filtrlar,
  chop etish va Telegram xabarlarini saqlaydi.
- Provider'lar endi repozitoriyni konstruktor orqali oladi (test uchun
  almashtirilishi mumkin), public API o'zgarmadi (ekranlar ta'sirlanmadi).
- `flutter analyze`: 0 xato; savat charge testi o'tadi.

**Qolgan kichik qarz:** repozitoriylar ikki papkada — `lib/data/repositories/`
(16 ta) va `lib/repositories/` (`inventory`, `shift`). Ikkinchisini birinchisiga
ko'chirish kerak.

---

## 4.6. Bajarilgan ishlar (API xavfsizligi) — 2026-08-18 ✅

> Serverning autentifikatsiya qatlami butunlay qayta yozildi.
> Batafsil: [`API.md`](../API.md) §9.

**Muammo edi:** token `admin-token-<id>` ko'rinishida taxmin qilinardi —
istalgan mijoz `Authorization: Bearer admin-token-1` yuborib to'liq admin
huquqini olardi. Bundan tashqari autentifikatsiya endpoint'lar ichida
qo'lda va nomuvofiq bajarilgan, ko'p endpoint umuman tekshirmagan edi.

**Bajarildi:**
- `lib/core/server/auth_token_service.dart` — tasodifiy (32 bayt), 12 soatlik,
  serverda saqlanadigan va bekor qilinadigan token; `api_sessions` jadvali.
- `ApiServer._authMiddleware()` — **bitta joyda** barcha so'rovlarni
  tekshiradigan qatlam. Ochiq yo'llar aniq ro'yxatda (`/auth/login`,
  `/reports/view`, `/uploads/...`, `/ws`).
- Rolga qarab bo'linish: hisobot/xodim/mijoz/xarajat bo'limlari ofitsiantlar
  uchun yopildi; `pin`/`pin_code` javoblardan olib tashlandi.
- Granular huquqlar serverda ham tekshiriladi (`change_table`,
  `print_receipt`).
- Login uchun brute-force himoyasi (5 urinish → 5 daqiqa blok).
- `waiter_id` endi faqat tokendan olinadi — mijoz uni yozib yubora olmaydi.
- `test/api_auth_test.dart` — 9 ta test.

**Arxitektura darsi:** avval har bir endpoint o'zi xavfsizlikni hal qilardi
(cross-cutting concern tarqoq edi). Endi u middleware — bitta joyda,
testlanadigan va unutib bo'lmaydigan.

## 4.7. Bajarilgan ishlar (`api_server.dart` bo'lindi) — 2026-08-20 ✅

> 3 097 satrli `api_server.dart` **16 faylga** bo'lindi. Eng katta qolgan
> fayl — 612 satr, va u HTML shabloni emas, haqiqiy logika.

**Yangi tuzilma:**

```
lib/core/server/
├── api_server.dart          94   ← faqat yig'uvchi: pipeline + route registratsiya
├── api_context.dart        130   ← umumiy helper'lar (sarlavha, sessiya, ruxsat)
├── auth_token_service.dart 304   (o'zgarmadi)
├── websocket_manager.dart   74   (o'zgarmadi)
├── middleware/
│   ├── auth_middleware.dart 39
│   └── cors_middleware.dart 19
├── routes/
│   ├── auth_routes.dart    187   /auth/*
│   ├── table_routes.dart   114   /locations, /tables
│   ├── catalog_routes.dart 117   /products, /categories, /printers, /settings
│   ├── staff_routes.dart   121   /waiters, /users
│   ├── finance_routes.dart 151   /expenses, /customers, /transactions
│   ├── order_routes.dart   612   /orders/*, /tables/merge
│   ├── report_routes.dart  484   /reports/*
│   ├── media_routes.dart    48   /upload/image, /uploads/<name>
│   └── print_routes.dart   196   /print_job, /print_receipt
└── views/
    └── mobile_report_html.dart 1002  ← statik HTML (Dart logikasi yo'q)
```

**Qanday bo'lindi:**
- Har bir route moduli — `static void register(Router router)` bo'lgan klass.
  `ApiServer._setupRoutes()` ularni ketma-ket chaqiradi, boshqa hech nima
  qilmaydi.
- Endpoint'lar ichidagi kod **o'zgartirilmadi** — faqat ko'chirildi va
  `_jsonHeaders` → `ApiContext.jsonHeaders` kabi havolalar yangilandi.
- Umumiy helper'lar (`jsonHeaders`, `sessionOf`, `requireStaff`,
  `requirePermission`, `clientKey`, `getImagesDir`, `inventoryEnabled`,
  `isPublicPath`, `isStaffOnlyPath`) → `ApiContext`.
- Middleware'lar (`authMiddleware`, `corsMiddleware`) — alohida fayllarga,
  test qilish oson bo'lishi uchun.
- 995 satrlik HTML qatori (`_mobileReportHtml`) → `views/` ga. Bu yolg'iz
  o'zi faylning uchdan birini egallardi.

**Tekshirildi:** 53 ta REST route + `/ws` — ro'yxat aynan bir xil (avtomatik
solishtirildi); route tanalari va HTML bayt-ma-bayt o'zgarmagan;
`flutter analyze` — 0 xato; `flutter test` — 68/68 o'tdi.

**Tashqi API o'zgarmadi:** `ApiServer.start(port)` / `ApiServer.stop()` —
`connectivity_provider` faqat shularni ishlatadi.

---

## 5. Ustuvor qadamlar (arxitektura)

1. ~~Data layer namunasi~~ ✅
2. ~~Data layer'ni barcha domenlarga tarqatish~~ ✅
3. ~~API autentifikatsiya qatlami~~ ✅ (2026-08-18)
4. ~~`api_server.dart` ni modullarga bo'lish~~ ✅ (2026-08-20)
5. **Qolgan god file'lar** — `pos_screen` (2 400+), `printing_service`
   (2 200+), `database_helper` (2 500+). ← keyingi ish
6. `cart_provider`dan `BuildContext`ni butunlay olib tashlash — qolgan
   10 ta `use_build_context_synchronously` warning aynan shundan.
7. `database_helper`ni `schema/` + `migrations/` fayllariga ajratish.
8. `lib/repositories/` → `lib/data/repositories/` ga birlashtirish.

Batafsil bosqichli reja: [`04_ROADMAP.md`](04_ROADMAP.md).
