#!/bin/bash

# 💜 Advik Panel + Wings Installer
echo -e "\e[1;35m"
echo "=============================================="
echo "   Advik's One-Click Pterodactyl Setup"
echo "   Panel + Daemon 🚀"
echo "=============================================="
echo -e "\e[0m"

# 🔍 Detect tmux
if [ -z "$TMUX" ]; then
    echo -e "\e[1;33m⚠️  You are NOT inside tmux."
    echo "To prevent crashes on disconnect, we'll auto-start tmux session."
    echo -e "Press [Enter] to continue...\e[0m"
    read
    sudo apt install -y tmux
    tmux new-session -s ptero-install "bash <(curl -s https://raw.githubusercontent.com/advikdev/ptero-installer/main/pterodactyl-full.sh)"
    exit 0
fi

# ✅ Update system
apt update -y && apt upgrade -y

# 📦 Install dependencies
apt install -y curl wget sudo unzip tar nginx mariadb-server php8.1 php8.1-{cli,common,mbstring,gd,curl,mysql,bcmath,xml,fpm,zip} \
redis-server git software-properties-common gnupg apt-transport-https lsb-release ca-certificates

# 🧬 Node.js + Composer
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# 🐳 Docker
curl -sSL https://get.docker.com | sh
systemctl enable --now docker

# 🐘 Setup MariaDB
echo "[+] Configuring MariaDB..."
systemctl enable --now mariadb
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'ptero'@'127.0.0.1' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 📂 Panel setup
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate --force
sed -i "s/DB_DATABASE=.*/DB_DATABASE=panel/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=ptero/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=StrongPassword123!/" .env
php artisan migrate --seed --force
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

# 🌐 NGINX config
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

ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
rm /etc/nginx/sites-enabled/default
systemctl restart nginx php8.1-fpm

# 🧬 Wings setup
echo -e "\n\e[1;34m[+] Now setting up Wings Daemon...\e[0m"
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

# 📥 Ask for config URL
echo -e "\n📥 Paste your Wings config URL (from panel):"
read -p "🔗 URL: " config_url
curl -Lo config.yml "$config_url"

# 🛠️ systemd for Wings
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

# ✅ DONE!
echo -e "\n\e[1;32m✅ Install Complete!"
echo "🌐 Panel: http://<your-server-ip>"
echo "🛠  MySQL: user=ptero, pass=StrongPassword123!"
echo "🧠 Wings: running & linked to panel"
echo "🛑 If you got disconnected, just run: tmux attach"
echo -e "\e[0m"
