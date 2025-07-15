#!/bin/bash

# 💜 One-Click Pterodactyl Installer with Permanent Cloudflare Tunnel
# Made by Advik

# ✅ Termius-safe detection
if [ "$SSH_TTY" ]; then
    echo -e "\e[1;36m✅ Termius session detected — safe install running...\e[0m"
else
    echo -e "\e[1;33m⚠️ Not in Termius. Continuing anyway...\e[0m"
fi

# 📦 Update & install dependencies
apt update -y && apt upgrade -y
apt install -y curl wget sudo gnupg software-properties-common \
  ca-certificates apt-transport-https unzip tar lsb-release

# 🧬 PHP 8.1
add-apt-repository ppa:ondrej/php -y
apt update -y
apt install -y php8.1 php8.1-{cli,common,mbstring,gd,curl,mysql,bcmath,xml,fpm,zip}

# 🐘 MariaDB
apt install -y mariadb-server
systemctl enable --now mariadb

# 🔐 MySQL Setup
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'ptero'@'127.0.0.1' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 🧪 Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 📦 Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# 🌍 NGINX
apt install -y nginx

# 📂 Panel Installation
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
composer install --no-dev --optimize-autoloader

cp .env.example .env
php artisan key:generate --force

# ⚙️ Configure .env DB
sed -i "s/DB_DATABASE=.*/DB_DATABASE=panel/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=ptero/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=StrongPassword123!/" .env

php artisan migrate --seed --force
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 storage bootstrap/cache

# 🌐 NGINX Config
cat > /etc/nginx/sites-available/pterodactyl <<EOF
server {
    listen 80;
    server_name _;

    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx php8.1-fpm

# 🧬 Wings Install
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

# 📥 Ask for config URL
echo -e "\n📥 Paste your Wings config URL (from panel node setup):"
read -p "🔗 URL: " config_url
curl -Lo config.yml "$config_url"

# 🛠️ Wings systemd
cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/etc/pterodactyl/wings
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable --now wings

# 🌩️ Permanent Cloudflare Tunnel Setup
read -p "🌐 Enter your Cloudflare Tunnel NAME (e.g. auranodes-panel): " tunnel_name
read -p "🔗 Enter your full domain (e.g. panel.yourdomain.com): " tunnel_domain

echo -e "\n📦 Installing Cloudflare Tunnel (cloudflared)..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

echo -e "\n🌐 Logging into Cloudflare (browser will open)..."
cloudflared tunnel login

echo -e "\n📁 Creating named tunnel: $tunnel_name"
cloudflared tunnel create "$tunnel_name"

echo -e "\n🌍 Routing domain to tunnel..."
cloudflared tunnel route dns "$tunnel_name" "$tunnel_domain"

mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $tunnel_name
credentials-file: /root/.cloudflared/$(ls /root/.cloudflared | grep json)

ingress:
  - hostname: $tunnel_domain
    service: http://localhost:80
  - service: http_status:404
EOF

cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable --now cloudflared

# ✅ Final Output
echo -e "\n✅ All done!"
echo "🌐 Panel is live at: https://$tunnel_domain"
echo "🧠 MySQL: user=ptero / pass=StrongPassword123!"
echo "🚀 Wings installed and running"
echo "🛡️ Cloudflare Tunnel active and permanent"
echo "🛠️ Script by Advik 💜"
