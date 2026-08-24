Salom Claude! Bizning Tezzro POS (Zelly) loyihamizga quyidagi 3 ta yangi funksionallik va imkoniyatni qo'shishimiz kerak.

Loyiha va arxitektura talablaridan kelib chiqib, har bir band bo'yicha aniq yechim va amalga oshirish rejasini ishlab chiqishda yordam ber:

1. **Mobil ilova (Admin & Ofitsiantlar uchun):**
   - Hozirda desktop ilovamiz bor, lekin mobil admin va ofitsiantlar uchun alohida ilova (yoki moslashtirilgan modul) mavjud emas.
   - Buni qanday qatlamlar va REST API/WebSocket orqali to'g'ri integratsiya qilish mumkin?

2. **Ko'p filialli (Multi-branch) tizim:**
   - Hozir ilovada ko'p filiallik yo'q. Bir admin bir vaqtning o'zida bir nechta oshxona/filialni nazorat qila olishi kerak.
   - DB arxitektura va ma'lumotlar tuzilmasiga qanday o'zgartirishlar kiritish lozim?

3. **Online / Offline gibrid ishlash rejasi:**
   - Tizim internet bo'lmaganda ham offline ishlayverishi, internet kelganda esa cloud/markaziy server bilan ma'lumotlarni muammosiz sinxronizatsiya (Sync Engine) qilishi kerak.
   - Ushbu Online + Offline rejimni arxitektura tomondan qanday to'g'ri tashkil etsak bo'ladi (konfliktlarni hal qilish, offline kassa operatsiyalari va h.k.)?

Iltimos, har bir band uchun qisqa, tushunarli arxitektura tavsiyalari va qilinadigan ishlar ketma-ketligini (Roadmap) berib o'tsang.