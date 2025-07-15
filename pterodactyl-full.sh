#!/bin/bash

# 💜 Advik's One-Click Pterodactyl Installer (100% Termius Ready)

# 🧠 Optional Termius detection
if [ "$SSH_TTY" ]; then
    echo -e "\e[1;36m✅ Termius session detected — running safe install...\e[0m"
else
    echo -e "\e[1;33m⚠️  Not running in Termius. Proceeding anyway...\e[0m"
fi

echo -e "\e[1;35m
==============================================
   Advik's One-Click Pterodactyl Setup
   Panel + Wings for VPS (Termius Edition) 🚀
==============================================
\e[0m"

# ✅ Update system
apt update -y && apt upgrade -y

# 📦 Base packages
apt install -y curl wget sudo lsb-release gnupg software-properties-common \
    ca-certificates apt-transport-https unzip tar

# 🧬 PHP setup
add-apt-repository ppa:ondrej/php -y
apt update -y
apt install -y php8.1 php8.1-{cli,common,mbstring,gd,curl,mysql,bcmath,xml,fpm,zip}

# 🐘 MariaDB
apt install -y mariadb-server
systemctl enable --now mariadb

# 🔐 MySQL setup
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'ptero'@'127.0.0.1' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 🧬 Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 📦 Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# 🌐 NGINX
apt install -y nginx

# 📂 Panel setup
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate --force

# ⚙️ DB Config
sed -i "s/DB_DATABASE=.*/DB_DATABASE=panel/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=ptero/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=StrongPassword123!/" .env

php artisan migrate --seed --force
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

# 🌍 NGINX config
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

# 🧬 Wings install
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

echo -e "\n📥 Paste your Wings config URL (from panel node setup):"
read -p "🔗 URL: " config_url
curl -Lo config.yml "$config_url"

# 🛠️ Wings service
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

# ✅ DONE
IP=$(hostname -I | awk '{print $1}')
echo -e "\n\e[1;32m✅ INSTALL COMPLETE!"
echo -e "🌐 Panel: http://$IP"
echo "🧠 MySQL: user=ptero / pass=StrongPassword123!"
echo "🚀 Wings: installed + running"
echo -e "\e[0m"
