# Admin mobil ilovasi — Texnik topshiriq (TZ)

> **Sana:** 2026-08-24 · **Versiya:** 1.0 · **Holat:** tasdiqlashga tayyor
> **Arxitektura qarori:** ilova **WebView** qobig'i sifatida quriladi
> **Bog'liq:** [`06_ADMIN_APP_API.md`](06_ADMIN_APP_API.md) (endpoint spetsifikatsiyasi) ·
> [`05_MOBIL_FILIAL_SYNC.md`](05_MOBIL_FILIAL_SYNC.md) · [`../API.md`](../API.md)

---

## 1. Maqsad

Kafe rahbari/egasi **telefondan kafeni kuzatishi va sozlashi** kerak — u
kafeda bo'lmasa ham. Bugun bu faqat Windows POS oldida o'tirib mumkin.

**Foydalanuvchi:** kafe egasi, direktor, buxgalter (1–3 kishi, bitta filial).
**Platforma:** Android 8+ (majburiy), iOS 14+ (ixtiyoriy, 2-bosqich).
**Tarmoq:** ilova filialdagi POS bilan **relay domen** orqali gaplashadi —
`https://<filial>.zelly.uz` (`RelayService`, 1.0.22 dan boshlab ishlaydi).

---

## 2. Arxitektura qarori — nega WebView

### 2.1. Sxema

```
┌──────────────────────────┐        ┌─────────────────────────────────┐
│  Android ilova (qobiq)   │        │  Filialdagi POS (Windows)       │
│                          │        │                                 │
│  ┌────────────────────┐  │ HTTPS  │  ┌───────────────────────────┐  │
│  │  WebView           │◄─┼────────┼─►│ shelf server :8080        │  │
│  │  <filial>.zelly.uz │  │ relay  │  │  GET /admin/view  → HTML  │  │
│  │  /admin/view       │  │        │  │  GET /admin/*     → JSON  │  │
│  └────────────────────┘  │        │  │  WS  /ws                  │  │
│                          │        │  └───────────┬───────────────┘  │
│  Native qism:            │        │              │                  │
│   · FCM push             │        │        SQLite (lokal)           │
│   · QR skaner            │        │                                 │
│   · Xavfsiz xotira       │        └─────────────────────────────────┘
│   · Offline banner       │
└──────────────────────────┘
```

**HTML sahifa POS'ning o'zidan keladi.** Ya'ni admin panelining butun mantig'i
`lib/core/server/views/` ichida yashaydi va POS yangilanganda panel ham
yangilanadi — ilovani Play Store'ga qayta chiqarish shart emas.

### 2.2. Nega WebView, native emas

| Sabab | Izoh |
|---|---|
| Panel POS bilan birga yangilanadi | Yangi hisobot qo'shildi → foydalanuvchi ilovani yangilamaydi, sahifa o'zi yangi |
| Bitta kod bazasi | Panel Telegram WebApp'da ham, brauzerda ham, ilovada ham bir xil ishlaydi |
| Tayyor asos bor | `mobile_report_html.dart` (1000+ satr) — login, davr filtri, hisobot ekranlari allaqachon yozilgan va ishlaydi |
| Tez | MVP-1 uchun native Flutter ilovasidan sezilarli kam ish |
| Versiya muammosi yo'q | Server va mijoz doim bir xil versiyada — `/v1/` prefiksi (06 §K4) kerak emas |

**Cheklovlar — ochiq aytiladi:**

| Cheklov | Yechim |
|---|---|
| Push bildirishnoma WebView'dan kelmaydi | Native qobiq FCM ni o'zi ushlaydi (§4.3) |
| Kamera/QR HTML'dan cheklangan | Native skaner, natija WebView'ga uzatiladi (§4.2) |
| Internet uzilsa panel ochilmaydi | Bu **qabul qilingan qaror** — `06` §7.3: admin ilovasi offline ishlamaydi, eski ma'lumot ko'rsatish noto'g'ri qaror keltiradi. Uzilganda native banner chiqadi |
| Animatsiya/silliqlik native'dan past | Panel — jadval va raqamlar, og'ir animatsiya yo'q |

---

## 3. Qamrov

`06_ADMIN_APP_API.md` §0 dagi qoida kuchida qoladi:

> **Admin ilovasi ko'radi va sozlaydi — sotmaydi.**

**Qiladi:** dashboard, jonli zal, buyurtmalar tarixi, hisobotlar, smenalar,
xarajatlar, mijozlar/qarzlar, ombor qoldig'i (o'qish), xodimlar, menyu
boshqaruvi (narx!), zal/stol sozlamalari, audit jurnali.

**Qilmaydi (ataylab):** buyurtma ochish, to'lov qabul qilish, chek chop etish,
ombor kirim/chiqim, smena yopish. Bularning hammasi desktop POS'da qoladi.

---

## 4. Native qobiq — talablar

Qobiq **Flutter** (`webview_flutter`) yoki toza Android (Kotlin + `WebView`)
bilan yozilishi mumkin. Tavsiya: **Flutter** — jamoa allaqachon Flutter
biladi va iOS versiyasi keyin arzon chiqadi.

### 4.1. Majburiy funksiyalar (MVP-1)

| # | Funksiya | Talab |
|---|---|---|
| N1 | **Server ulanishi** | Birinchi ochilishda domen so'raladi: qo'lda kiritish yoki QR. Domen xavfsiz xotirada saqlanadi (`flutter_secure_storage`) |
| N2 | **QR skaner** | POS'dagi "Ulanish QR" ni skanerlaydi. QR ichida: `zelly://connect?url=https://x.zelly.uz` |
| N3 | **Server tekshiruvi** | Domen kiritilgach `GET /server/info` (06 §K1) chaqiriladi — kafe nomi ko'rsatiladi; xato bo'lsa aniq matn ("Server javob bermayapti" / "Bu Zelly serveri emas") |
| N4 | **WebView** | `https://<domen>/admin/view` yuklanadi. JS yoqilgan, DOM storage yoqilgan, zoom o'chirilgan |
| N5 | **Orqaga tugmasi** | Android "back" — avval WebView tarixi, tarix tugasa ilovadan chiqish so'raladi |
| N6 | **Pull-to-refresh** | Sahifani qayta yuklaydi |
| N7 | **Offline banner** | Internet yo'q yoki server javob bermasa — WebView ustida native banner + "Qayta urinish" tugmasi. Oq ekran **ko'rsatilmasin** |
| N8 | **Yuklanish indikatori** | Birinchi yuklashda splash + progress |
| N9 | **Rasm tanlash** | `<input type="file">` uchun `onShowFileChooser` ulanadi — menyu rasmini galereyadan yuklash (`POST /upload/image`) |
| N10 | **Tashqi havolalar** | `tel:`, `https://t.me/...` va boshqa tashqi URL'lar tashqi brauzer/ilovada ochiladi, WebView ichida emas |

### 4.2. Native ↔ Web ko'prigi

WebView'ga `ZellyNative` nomli JS kanali qo'shiladi. Sahifa uning mavjudligini
`typeof ZellyNative !== 'undefined'` bilan tekshiradi (brauzerda yo'q).

| Chaqiruv | Yo'nalish | Ma'no |
|---|---|---|
| `ZellyNative.pushToken()` | web → native | FCM tokenini so'raydi, natija `window.onPushToken(t)` ga qaytadi |
| `ZellyNative.scanQr()` | web → native | Skanerni ochadi, natija `window.onQrResult(text)` |
| `ZellyNative.share(text)` | web → native | Tizim "ulashish" oynasi (hisobotni yuborish) |
| `ZellyNative.haptic()` | web → native | Qisqa tebranish |
| `ZellyNative.setBadge(n)` | web → native | Ilova ikonkasidagi raqam |
| `window.onNativeBack()` | native → web | Back bosildi; sahifa modal ochiq bo'lsa yopadi va `true` qaytaradi |

> Ko'prik **ixtiyoriy** — biror chaqiruv bo'lmasa panel baribir ishlaydi.
> Bu panelni brauzerda va Telegram WebApp'da sinash imkonini beradi.

### 4.3. Push bildirishnomalar (MVP-3+)

- Qobiq FCM tokenini oladi va `POST /push/register` (06 §I1) ga yuboradi.
- Bildirishnoma bosilganda WebView tegishli ekranga o'tadi:
  `/admin/view#/shifts/108` ko'rinishidagi hash-route orqali.
- **Bog'liqlik:** push filialdagi POS'dan emas, cloud'dan yuboriladi
  (telefon LAN'dan tashqarida bo'ladi). Shungacha vaqtinchalik kanal —
  **Telegram bot** (bugun ishlaydi, `telegram_bot_service.dart`).

### 4.4. Ilova metama'lumotlari

| Nima | Qiymat |
|---|---|
| Nomi | Zelly Admin |
| Package | `uz.zelly.admin` |
| Ikonka/splash | Zelly brendi, to'q fon (`#0F172A`) |
| Ruxsatlar | `INTERNET`, `CAMERA` (QR), `POST_NOTIFICATIONS` (Android 13+), `READ_MEDIA_IMAGES` (rasm yuklash) |
| Orientatsiya | Faqat portret |
| Minimal SDK | 26 (Android 8) |

---

## 5. Web panel — talablar

Manba: `lib/core/server/views/admin/` (yangi), `GET /admin/view` orqali
beriladi.

### 5.1. Kod tashkiloti

`mobile_report_html.dart` — bitta 1000-satrli Dart string. Admin panel undan
kattaroq bo'ladi, shuning uchun **bo'lib yoziladi**:

```
lib/core/server/views/admin/
  admin_panel_html.dart     // sahifa yig'uvchi (head + qismlar)
  _styles.dart              // CSS
  _shell.dart               // login, header, pastki navigatsiya
  _dashboard.dart
  _hall.dart                // jonli zal
  _orders.dart
  _reports.dart             // mavjud mobile_report_html'dan ko'chiriladi
  _shifts.dart
  _money.dart               // xarajat, kassa, qarzlar
  _menu.dart                // menyu boshqaruvi (yozish!)
  _staff.dart
  _settings.dart
  _audit.dart
```

Har fayl `String part…()` qaytaradi; `admin_panel_html.dart` ularni ketma-ket
yopishtiradi. **Tashqi CDN ishlatilmaydi** — kafe interneti sekin va panel
LAN'da ham ochilishi kerak: CSS/JS/shrift sahifa ichida bo'ladi.

### 5.2. Texnologiya

| Nima | Qaror |
|---|---|
| Freymvork | **Yo'q** — toza JS (`mobile_report_html.dart` dagidek). React/Vue build bosqichi keltiradi |
| Marshrutlash | Hash-router: `#/dashboard`, `#/orders/171234…` — back tugmasi tabiiy ishlaydi |
| Holat | Bitta `state` obyekti + `render()` funksiyalari |
| Grafiklar | Toza SVG (soatlik grafik `mobile_report_html.dart` da shunday qilingan) |
| Shrift | Tizim shrifti (`-apple-system, Segoe UI, system-ui`) |

### 5.3. Dizayn

Mavjud hisobot panelining palitrasi saqlanadi (to'q rejim):

```
--bg:#0F172A  --sf:#1E293B  --bd:#334155
--tx:#F8FAFC  --mu:#94A3B8  --ac:#6C5CE7
--gr:#10B981  --rd:#EF4444  --yw:#F59E0B
```

- Maksimal kenglik `520px`, markazda (planshet/brauzerda ham chiroyli).
- Pastda **5 ta bo'limli navigatsiya:** Bosh · Zal · Buyurtma · Hisobot · Yana.
- "Yana" ichida: smenalar, xarajat, mijozlar, ombor, xodimlar, menyu,
  sozlamalar, audit.
- Barcha pul raqamlari `1 234 567` formatida, ming ajratgich — probel.
- Har ro'yxat `?limit` bilan so'raladi va pastga scroll'da davom etadi
  (`{data, meta}` javobi).

### 5.4. Ekranlar va endpointlar

To'liq xarita — `06_ADMIN_APP_API.md` §2. Bu yerda ekranlar ro'yxati va
bosqichi:

| # | Ekran | Bosqich | Yangi endpoint kerakmi |
|---|---|---|---|
| E1 | Ulanish + login (PIN) | MVP-1 | K1, K2 |
| E2 | Dashboard | MVP-1 | — |
| E3 | Jonli zal (WS bilan) | MVP-1 | — |
| E4 | Buyurtmalar ro'yxati + tafsilot | MVP-1 | A4 (to'lovlar) |
| E5 | Hisobotlar (9 ta ko'rinish) | MVP-1 | — (ko'chiriladi) |
| E6 | Ombor qoldig'i + harakatlar | MVP-1 | — |
| E7 | Smenalar + kassa farqi | MVP-2 | B1, B2, C1 |
| E8 | Xarajatlar | MVP-2 | D1, D2 |
| E9 | Mijozlar va qarzdorlar | MVP-2 | E1, E2, E3 |
| E10 | Audit jurnali | MVP-2 | **H1** |
| E11 | Menyu boshqaruvi (narx) | MVP-3 | **A1, A1a, A2, A3** |
| E12 | Xodimlar + avans | MVP-3 | F1, F2 |
| E13 | Sozlamalar | MVP-3 | J1 |
| E14 | Zal/stol sozlamalari | MVP-3 | — |

> **Qat'iy shart (`06` §A1a):** menyu ekrani (E11) audit jurnali ekrani (E10)
> **chiqqandan keyin** chiqadi. Narx telefondan o'zgartiriladigan bo'lsa,
> uni kim o'zgartirganini ko'radigan joy ham bo'lishi shart.

### 5.5. Real-time

Panel `wss://<domen>/ws` ga ulanadi va quyidagi hodisalarda tegishli ekranni
yangilaydi: `tables_updated`, `order_updated`, hamda 06 §K3 dagi yangilar
(`order_paid`, `bill_requested`, `shift_closed`, `catalog_updated`).

Ulanish uzilsa — 1s, 2s, 4s… (max 30s) bilan qayta ulanadi, header'da kulrang
nuqta ko'rsatiladi.

---

## 6. Autentifikatsiya va sessiya

1. Panel ochiladi → `localStorage` da token bormi?
2. Bor bo'lsa `GET /auth/me` bilan tekshiriladi. `401` → login ekrani.
3. Login: **4 xonali PIN** → `POST /auth/login` → `{token, expires_at, user}`.
4. Token `localStorage` da saqlanadi, har so'rovda
   `Authorization: Bearer <token>`.
5. Har `401` javobda token o'chiriladi va login ekrani ochiladi.
6. `429` javobida (brute-force himoyasi) qolgan vaqt ko'rsatiladi
   (`retry_after`).

**Rol tekshiruvi:** panel `user.role !== 'admin'` bo'lsa "Bu bo'lim faqat
administrator uchun" deb chiqadi va login ekraniga qaytaradi. Server ham
`403` beradi — bu ikkinchi qatlam, birinchisi emas.

**Token muddati:** 12 soat, sliding expiry (server allaqachon shunday).
Rahbar kuniga bir marta PIN kiritadi — bu qabul qilingan.

---

## 7. Server tomonidagi ishlar

| # | Ish | Bosqich | Baho |
|---|---|---|---|
| S1 | `GET /admin/view` — panel HTML (tokensiz ochiladi, o'zi login so'raydi) | MVP-1 | 1 kun |
| S2 | `GET /server/info`, `GET /health` (06 §K1, K2) | MVP-1 | 0.5 kun |
| S3 | Panelni yozish (E1–E6) | MVP-1 | 6–8 kun |
| S4 | MVP-2 endpointlari: A4, B1, B2, C1, D1, D2, E1–E3, **H1** + `user_id` tuzatish | MVP-2 | 5 kun |
| S5 | Panel E7–E10 | MVP-2 | 4 kun |
| S6 | MVP-3 endpointlari: A1, A1a, A2, A3, F1, F2, J1, K3 | MVP-3 | 5 kun |
| S7 | Panel E11–E14 | MVP-3 | 4 kun |
| S8 | Native qobiq (N1–N10) | MVP-1 bilan parallel | 3 kun |
| S9 | Push (I1 + FCM + cloud) | MVP-4 | cloud'ga bog'liq |

**MVP-1 yakuni: ~2 hafta** (panel va qobiq parallel yoziladi).

---

## 8. Xavfsizlik

| Talab | Izoh |
|---|---|
| **TLS majburiy** | Panel faqat `https://` orqali. `http://` domen kiritilsa qobiq ogohlantiradi. Relay nginx TLS beradi (`deploy/README.md`) |
| WebView sozlamalari | `allowFileAccess=false`, `allowContentAccess=false`, `mixedContentMode=NEVER_ALLOW`, `domStorageEnabled=true` |
| Domen cheklovi | WebView faqat saqlangan domen ichida navigatsiya qiladi; boshqa host — tashqi brauzerga |
| Token | `localStorage` (WebView ichida, ilovaga xos, boshqa ilova o'qiy olmaydi). Domen esa `flutter_secure_storage` da |
| Chiqish | "Chiqish" tugmasi `POST /auth/logout` + `localStorage.clear()` + WebView cookie/storage tozalash |
| Audit | Har yozish amali `audit_logs` ga **serverda** yoziladi, `user_id` majburiy (06 §A1a) |
| Skrinshot | Moliyaviy ma'lumot — `FLAG_SECURE` ixtiyoriy, sozlamadan yoqiladigan |
| Rate limit | Login `429` bilan cheklangan (server tomonida bor) |

---

## 9. Qabul qilish mezonlari (MVP-1)

Ilova quyidagilar bajarilganda topshirilgan hisoblanadi:

1. Toza telefonda ilova o'rnatiladi, QR skanerlanadi, kafe nomi ko'rsatiladi.
2. PIN kiritiladi → 3 soniya ichida dashboard ochiladi (4G da).
3. Dashboard bugungi tushum, chek soni, o'rtacha chek, to'lov turlari, zal
   holati va top mahsulotlarni ko'rsatadi; raqamlar POS'dagi bilan **aynan
   mos tushadi**.
4. Kassada yangi buyurtma ochiladi → jonli zal ekrani **5 soniya ichida**
   o'zi yangilanadi (WS).
5. Hisobot ekranida "hafta" tanlanadi → raqamlar desktopdagi hisobot bilan
   bir xil.
6. Internet o'chiriladi → oq ekran emas, banner chiqadi; internet
   qaytarilganda "Qayta urinish" bosilib panel tiklanadi.
7. Telefon 12 soatdan ko'p turadi → keyingi ochilishda login so'raladi,
   xato emas.
8. Ofitsiant PIN'i bilan kirilganda admin bo'limlari ochilmaydi.
9. Ilova Android 8 va Android 14 da sinaladi.
10. Panel brauzerda (`https://<domen>/admin/view`) ham ishlaydi — qobiqsiz.

---

## 10. Ochiq savollar

| # | Savol | Tavsiya |
|---|---|---|
| 1 | iOS kerakmi? | Flutter qobig'i bo'lsa qo'shimcha ~3 kun. MVP-1 dan keyin |
| 2 | Play Store'ga chiqariladimi yoki APK havolasi? | Boshida APK (tez), keyin Store |
| 3 | Ofitsiant ilovasi ham shu qobiqda bo'ladimi? | `/waiter/view` qo'shilsa, login roli ekranni tanlaydi (`05` §4.2 shuni tavsiya qiladi). Lekin ofitsiant ekrani **offline ishlashi kerak** — WebView bunga mos emas, alohida qaror talab qiladi |
| 4 | Panel Telegram WebApp sifatida ham qolsinmi? | Ha — bir xil HTML, `/reports/view` orqaga muvofiq qoladi |
| 5 | Ko'p filial (bir nechta domen) qachon? | Cloud Faza 3 (`05_MOBIL_FILIAL_SYNC.md`). Qobiq bir nechta domen saqlashga bugundan tayyorlansin |
| 6 | Push kanali: FCM yoki Telegram? | MVP-3 gacha Telegram, keyin FCM |
