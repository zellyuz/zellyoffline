#!/usr/bin/env bash
#
# Zelly relay — server sozlash (5.104.108.235 / mehmon.zelly.uz)
#
# Bu skript POS ilovasining API'sini internetga chiqaradi. Server API'ni
# YURITMAYDI — u faqat relay: trafikni kafedagi POS kompyuteriga uzatadi.
#
# ⚠️ zelly.uz saytiga TEGMAYDI:
#    - mavjud nginx fayllari o'zgartirilmaydi, faqat YANGI fayl qo'shiladi
#    - mavjud sertifikatlarga tegilmaydi
#    - `nginx -t` muvaffaqiyatsiz bo'lsa — o'zgarish qaytariladi
#
# Ishlatish:
#   scp deploy/server_setup.sh zelly:/root/
#   ssh zelly "bash /root/server_setup.sh"

set -euo pipefail

DOMAIN="mehmon.zelly.uz"
FRP_VERSION="0.61.1"
FRP_BIND_PORT=7000          # POS shu portga ulanadi (tashqi)
FRP_VHOST_PORT=8081         # frps → nginx (faqat localhost)
FRP_DASH_PORT=7500          # frps holat paneli (faqat localhost)
TOKEN_FILE="/etc/frp/token"
BACKUP_DIR="/root/zelly-relay-backup-$(date +%Y%m%d-%H%M%S)"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "root kerak"

# ─────────────────────────────────────────────────────────────────────────
log "0/8 · Holatni saqlash (rollback uchun)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/nginx "$BACKUP_DIR/nginx" 2>/dev/null || true
nginx -t 2>&1 | tee "$BACKUP_DIR/nginx-test-before.txt"
echo "Zaxira: $BACKUP_DIR"

# ─────────────────────────────────────────────────────────────────────────
log "1/8 · DNS tekshiruvi"
SERVER_IP="$(curl -fsS -m 10 https://api.ipify.org || echo '')"
RESOLVED="$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1 || echo '')"
echo "Server IP : ${SERVER_IP:-aniqlanmadi}"
echo "$DOMAIN → ${RESOLVED:-topilmadi}"
if [ -z "$RESOLVED" ]; then
  die "$DOMAIN hali DNS'da yo'q. ahost.uz panelida A yozuvini qo'shing:
       $DOMAIN  →  ${SERVER_IP:-5.104.108.235}
   (ko'p filial uchun: *.$DOMAIN ham shu IP ga)"
fi
[ "$RESOLVED" = "$SERVER_IP" ] || warn "DNS boshqa IP ga ishora qilyapti — davom etamiz, lekin certbot yiqilishi mumkin"

# ─────────────────────────────────────────────────────────────────────────
log "2/8 · Paketlar (minimal — server ishlab turibdi)"
# Bu serverda 4 ta production sayt bor (zelly.uz, barormebel.uz,
# selen-crm.uz, workers.uz) + PostgreSQL + Docker.
# Shuning uchun HECH NARSA yangilanmaydi va ortiqcha paket o'rnatilmaydi.
command -v nginx   >/dev/null || die "nginx topilmadi"
command -v certbot >/dev/null || die "certbot topilmadi"
command -v ufw     >/dev/null || die "ufw topilmadi"
command -v curl    >/dev/null || die "curl topilmadi"
echo "Kerakli paketlar joyida — apt-get ishlatilmadi"

# ─────────────────────────────────────────────────────────────────────────
log "3/8 · frps o'rnatish (v$FRP_VERSION)"
if ! command -v frps >/dev/null; then
  ARCH="amd64"; [ "$(uname -m)" = "aarch64" ] && ARCH="arm64"
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/frp.tar.gz" \
    "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
  tar -xzf "$TMP/frp.tar.gz" -C "$TMP" --strip-components=1
  install -m 0755 "$TMP/frps" /usr/local/bin/frps
  rm -rf "$TMP"
fi
frps --version

# ─────────────────────────────────────────────────────────────────────────
log "4/8 · frps konfiguratsiyasi"
mkdir -p /etc/frp
if [ ! -f "$TOKEN_FILE" ]; then
  head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 40 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi
TOKEN="$(cat "$TOKEN_FILE")"

DASH_PW_FILE="/etc/frp/dashboard_password"
if [ ! -f "$DASH_PW_FILE" ]; then
  head -c 18 /dev/urandom | base64 | tr -d '/+=' > "$DASH_PW_FILE"
  chmod 600 "$DASH_PW_FILE"
fi
DASH_PW="$(cat "$DASH_PW_FILE")"

cat > /etc/frp/frps.toml <<EOF
# Zelly relay — frps
# POS kompyuterlari shu serverga O'ZI ulanadi (kafeda oq IP kerak emas).

# Faqat localhost: tashqi ulanish nginx (443) orqali `wss` bilan keladi.
bindAddr = "127.0.0.1"
bindPort = $FRP_BIND_PORT

# HTTP vhost — FAQAT localhost. Tashqi trafik nginx orqali keladi (TLS u yerda).
vhostHTTPPort = $FRP_VHOST_PORT

# Har filial o'z subdomeni bilan: a1.$DOMAIN, a2.$DOMAIN ...
subdomainHost = "$DOMAIN"

# ⚠️ Bu kalitlar HAR QANDAY [bo'lim] dan OLDIN turishi shart.
# TOML da [log] dan keyin yozilsa "log.transport.*" bo'lib qoladi va
# frps "unknown field transport" deb yiqiladi.
transport.tcpMux = true
transport.maxPoolCount = 10

# Hech qaysi POS ulanmagan bo'lsa frps o'zining "404 page not found" matnini
# qaytaradi — mijoz uchun tushunarsiz. Buni JSON bilan almashtiramiz.
# Bu FAQAT frps ning o'z 404 iga tegishli; POS qaytargan haqiqiy 404
# javoblar o'zgarmasdan o'tadi.
custom404Page = "/etc/frp/404.json"

[auth]
method = "token"
token = "$TOKEN"

[webServer]
addr = "127.0.0.1"
port = $FRP_DASH_PORT
user = "admin"
password = "$DASH_PW"

[log]
to = "/var/log/frps.log"
level = "info"
maxDays = 14
EOF

cat > /etc/frp/404.json <<'EOF'
{"error":"Kafedagi POS bilan aloqa yo'q — kompyuter o'chiq yoki dastur ishlamayapti"}
EOF

# Konfiguratsiyani ishga tushirishdan OLDIN tekshirish
frps verify -c /etc/frp/frps.toml || die "frps.toml yaroqsiz (yuqoriga qarang)"
chmod 600 /etc/frp/frps.toml

cat > /etc/systemd/system/frps.service <<'EOF'
[Unit]
Description=Zelly relay (frp server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable frps >/dev/null
# `enable --now` allaqachon ishlab turgan xizmatni QAYTA ishga tushirmaydi —
# ya'ni skript ikkinchi marta chaqirilganda yangi konfiguratsiya qo'llanmasdi.
systemctl restart frps
sleep 2
systemctl is-active --quiet frps || { journalctl -u frps -n 30 --no-pager; die "frps ishga tushmadi"; }

# vhost porti tashqariga chiqmaganini tasdiqlash
if ss -tlnp 2>/dev/null | grep -q "0.0.0.0:$FRP_VHOST_PORT"; then
  warn "vhostHTTPPort tashqariga ochiq ko'rinadi — ufw uni yopadi"
fi

# ─────────────────────────────────────────────────────────────────────────
log "5/8 · nginx (YANGI fayl — mavjudlariga tegilmaydi)"
VHOST="/etc/nginx/sites-available/$DOMAIN"
[ -e "$VHOST" ] && cp -a "$VHOST" "$BACKUP_DIR/"

# ⚠️ Bu vhost ATAYLAB faqat 80-portda. `listen 443 ssl` ni sertifikatsiz
# yozib bo'lmaydi — `nginx -t` yiqiladi va butun nginx (4 ta sayt bilan)
# reload bo'lmay qoladi. 443 blokini certbot 6-bosqichda o'zi qo'shadi.
cat > "$VHOST" <<EOF
# Zelly POS relay — $DOMAIN
# TLS shu yerda tugaydi, keyin frps (localhost:$FRP_VHOST_PORT) orqali
# kafedagi POS kompyuteriga uzatiladi.
#
# Bu fayl FAQAT $DOMAIN uchun. Serverdagi boshqa saytlar
# (zelly.uz, barormebel.uz, selen-crm.uz, workers.uz) alohida
# konfiguratsiyalarda va ularga tegilmaydi.

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN *.$DOMAIN;

    location /.well-known/acme-challenge/ { root /var/www/html; }

    # ── frp boshqaruv kanali (WebSocket) ──────────────────────────────────
    # Kafe tarmoqlari (va bu serverning provayderi) 22/80/443 dan boshqa
    # portlarni bloklaydi — $FRP_BIND_PORT ga to'g'ridan-to'g'ri ulanib
    # bo'lmaydi. Shuning uchun POS 443 ga `wss` bilan ulanadi, nginx esa
    # uni frps ga uzatadi. "/~!frp" — frp ning o'z yo'li.
    location = /~!frp {
        proxy_pass http://127.0.0.1:$FRP_BIND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       \$host;
        proxy_set_header X-Real-IP  \$remote_addr;

        # Tunnel uzoq yashaydi — nginx uni yopib qo'ymasin.
        proxy_read_timeout  7d;
        proxy_send_timeout  7d;
        proxy_buffering off;
    }

    # Rasm yuklash (/upload/image) uchun
    client_max_body_size 12m;

    # POS uzoq javob qaytarishi mumkin (chop etish, hisobot)
    proxy_read_timeout  120s;
    proxy_send_timeout  120s;
    proxy_connect_timeout 15s;

    access_log /var/log/nginx/$DOMAIN.access.log;
    error_log  /var/log/nginx/$DOMAIN.error.log;

    location / {
        proxy_pass http://127.0.0.1:$FRP_VHOST_PORT;
        proxy_http_version 1.1;

        # frps qaysi filialga yuborishni Host sarlavhasidan biladi
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket (/ws) — busiz real-time kanal ishlamaydi
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # POS ulanmagan bo'lsa 502 o'rniga tushunarli javob
        proxy_intercept_errors on;
        error_page 502 503 504 = @offline;
    }

    location @offline {
        default_type application/json;
        return 503 '{"error":"Kafedagi POS bilan aloqa yo\\u2018q"}';
    }
}
EOF

ln -sfn "$VHOST" "/etc/nginx/sites-enabled/$DOMAIN"

if ! nginx -t; then
  warn "nginx konfiguratsiyasi xato — o'zgarish QAYTARILDI"
  rm -f "/etc/nginx/sites-enabled/$DOMAIN"
  nginx -t && systemctl reload nginx
  die "nginx -t yiqildi, tafsilot yuqorida"
fi
systemctl reload nginx

# ─────────────────────────────────────────────────────────────────────────
log "6/8 · TLS sertifikati (Let's Encrypt)"
# --nginx: faqat SHU domen uchun. zelly.uz sertifikati alohida qoladi.
# ⚠️ Shart AYNAN vhost ichidagi 443 blokiga qaraydi, sertifikat borligiga EMAS.
# Skript qayta ishga tushirilganda vhost fayli qaytadan yoziladi (HTTP-only),
# shuning uchun sertifikat mavjud bo'lsa ham 443 blokini qayta qo'shish kerak.
# `--keep-until-expiring` yangi sertifikat so'ramaydi — mavjudini qayta o'rnatadi.
if grep -q "listen 443" "$VHOST"; then
  echo "443 bloki allaqachon joyida — o'tkazib yuborildi"
else
  # --redirect: 443 blokini qo'shib, 80 dan HTTPS ga yo'naltiradi.
  # --cert-name: mavjud sertifikatlarga (zelly.uz va h.k.) qo'shilib ketmasin.
  certbot --nginx -d "$DOMAIN" --cert-name "$DOMAIN" --redirect \
          --non-interactive --agree-tos \
          --register-unsafely-without-email --keep-until-expiring || \
    warn "certbot yiqildi. Wildcard (*.$DOMAIN) uchun DNS-01 kerak:
          certbot certonly --manual --preferred-challenges dns -d '*.$DOMAIN' -d '$DOMAIN'"
fi
nginx -t && systemctl reload nginx

# ─────────────────────────────────────────────────────────────────────────
log "7/8 · Xavfsizlik devori (faqat 1 ta qoida qo'shiladi)"
# ufw allaqachon aktiv: 22, 80, 443 ochiq. Mavjud qoidalarga TEGILMAYDI —
# faqat POS ulanadigan port qo'shiladi.
#
# Eslatma: frps ning vhost porti (8081) 0.0.0.0 da tinglaydi — frp uni
# faqat localhost ga bog'lash imkonini bermaydi. Uni ufw ning standart
# "deny (incoming)" siyosati to'sadi (tekshirilgan). Panel (7500) esa
# konfiguratsiyada aniq 127.0.0.1 ga bog'langan.
#
# ⚠️ $FRP_BIND_PORT ni TASHQARIGA ochish SHART EMAS va ochilmaydi:
# provayder 22/80/443 dan boshqa portlarni bloklaydi (tekshirilgan —
# serverga SYN paketi ham yetib kelmaydi). POS 443 ga `wss` bilan ulanadi,
# nginx uni localhost:$FRP_BIND_PORT ga uzatadi.
if ufw status | grep -q "^$FRP_BIND_PORT/tcp"; then
  echo "Eski $FRP_BIND_PORT/tcp qoidasi olib tashlanmoqda (kerak emas)"
  ufw delete allow $FRP_BIND_PORT/tcp >/dev/null 2>&1 || true
fi
echo "Ochiq portlar o'zgarmadi: 22, 80, 443"
ufw status numbered

# ─────────────────────────────────────────────────────────────────────────
log "8/8 · Tayyor"
cat <<EOF

  Domen        : https://$DOMAIN
  frp port     : $FRP_BIND_PORT
  frp token    : $TOKEN
  Panel        : ssh -L $FRP_DASH_PORT:127.0.0.1:$FRP_DASH_PORT zelly
                 → http://127.0.0.1:$FRP_DASH_PORT  (admin / $DASH_PW)
  Zaxira       : $BACKUP_DIR

  Keyingi qadam — kafedagi POS kompyuterida:
    deploy/frpc.toml ni to'ldiring (token yuqorida) va frpc.exe ni ishga tushiring.

  Tekshirish (POS ulangandan keyin):
    curl https://$DOMAIN/health

  zelly.uz holati:
EOF
curl -s -o /dev/null -w "    https://zelly.uz → %{http_code}\n" https://zelly.uz/ || true
