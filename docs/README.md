# Tezzro POS — Hujjatlar

Bu papka loyihaning texnik holati, tahlili va rivojlanish rejasini saqlaydi.
Kod tahlili asosida tuzilgan (2026-08-07).

| Hujjat | Mazmun |
|--------|--------|
| [00_OVERVIEW.md](00_OVERVIEW.md) | Loyiha umumiy holati: texnologiyalar, tuzilish, ko'lam, umumiy baho |
| [01_ARCHITECTURE.md](01_ARCHITECTURE.md) | Arxitektura tahlili va tavsiyalar (Clean Architecture, SOLID) |
| [02_CODE_QUALITY.md](02_CODE_QUALITY.md) | Linting (393 issue), kod sifati, texnik qarz |
| [03_SECURITY.md](03_SECURITY.md) | Xavfsizlik topilmalari (⚠️ kritik: git'dagi maxfiy kalit) |
| [04_ROADMAP.md](04_ROADMAP.md) | Global standartlarga bosqichma-bosqich o'tish rejasi |
| [05_MOBIL_FILIAL_SYNC.md](05_MOBIL_FILIAL_SYNC.md) | **Mobil ilova · ko'p filiallik · online/offline sync** — arxitektura va Roadmap ([taklif.md](taklif.md) ga javob) |
| [06_ADMIN_APP_API.md](06_ADMIN_APP_API.md) | **Admin mobil ilovasi — API spetsifikatsiyasi**: ekran→endpoint xaritasi, yetishmayotgan endpoint'lar, MVP bosqichlari |
| [07_ADMIN_APP_TZ.md](07_ADMIN_APP_TZ.md) | **Admin mobil ilovasi — texnik topshiriq (TZ)**: WebView arxitekturasi, native qobiq talablari, ekranlar, qabul mezonlari |
| [ombor.md](ombor.md) | Omborxona moduli — asl g'oya (foydalanuvchi yozgan) |
| [ombor_tahlil.md](ombor_tahlil.md) | Omborxona modulining chuqur tahlili |
| [ombor_final.md](ombor_final.md) | **Omborxona — YAKUNIY, kodga tayyor spetsifikatsiya** (DB + oqim + refaktor) |

## Tezkor xulosa

Tezzro — funksional jihatdan **kuchli** Windows desktop POS ilovasi
(Flutter + Provider + SQLite, ~59.5k satr, 134 fayl).

**Bajarilgan ishlar (2026-08-07):**
- ✅ **Data layer to'liq joriy qilindi** — 18 repozitoriy; barcha 18 provider va
  10 ekrandagi SQL repo'ga ko'chirildi; `flutter analyze` 0 xato.
  (`UI → Provider → Repository → DataSource`). Batafsil: [01_ARCHITECTURE.md](01_ARCHITECTURE.md) §4.5.

**Qolgan asosiy yo'nalishlar:**
1. 🔴 **Xavfsizlik** — RSA maxfiy kaliti git'dan olib tashlanib, yangilanishi kerak.
2. 🟡 **Kod sifati** — analyzer issue'lar (255 tasi `dart fix` bilan avtomatik tuzatiladi).
3. 🟡 **God file'lar** — 5+ fayl 2000 satrdan oshgan, bo'linishi kerak.
4. 🔴 **Testlar** — 134 fayldan atigi 5 test.

Batafsil reja va holat: [04_ROADMAP.md](04_ROADMAP.md).
