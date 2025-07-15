#!/bin/bash

# 💜 Advik's Full Pterodactyl Installer
echo -e "\e[1;35m"
echo "=============================================="
echo "     Advik's Pterodactyl Setup"
echo "     Panel + Daemon + Everything Done 🚀"
echo "=============================================="
echo -e "\e[0m"

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

# 🧬 Setup Wings (Daemon)
echo -e "\n\e[1;34m[+] Now setting up Wings Daemon...\e[0m"
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

# 📥 Ask for config URL
echo -e "\n📥 Please paste your Wings config URL (from the panel node setup):"
read -p "🔗 URL: " config_url
curl -Lo config.yml "$config_url"

# 🛠️ Create systemd service
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

# 🔁 Enable Wings
systemctl daemon-reexec
systemctl enable --now wings

# ✅ ALL DONE
echo -e "\n\n\e[1;32m🎉 ALL DONE!"
echo -e "🌐 Panel: http://<YOUR-SERVER-IP>"
echo -e "🧬 MySQL DB: panel / ptero / StrongPassword123!"
echo -e "⚙️ Wings is running & waiting for connection to panel"
echo -e "🔁 Restart: systemctl restart wings"
echo -e "✅ Enjoy hosting with AuraNodes! 💜"
echo -e "\e[0m"
