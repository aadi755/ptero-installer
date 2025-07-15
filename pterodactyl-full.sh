#!/bin/bash

# 💜 Advik Installer Banner
echo -e "\e[1;35m"
echo "=============================================="
echo "   Advik's One-Click Pterodactyl Setup"
echo "   Panel + Daemon + Safe for Termius 🚀"
echo "=============================================="
echo -e "\e[0m"

# 🔍 Auto tmux safety
if [ -z "$TMUX" ]; then
    echo -e "\e[1;33m⚠️  You're not in tmux. Auto-starting safe session...\e[0m"
    sudo apt install -y tmux
    tmux new-session -s ptero-install "bash <(curl -s https://raw.githubusercontent.com/aadi755/ptero-installer/main/pterodactyl-full.sh)"
    exit 0
fi

# ✅ Update system
apt update -y && apt upgrade -y

# 📦 Required base packages
apt install -y curl wget sudo lsb-release gnupg software-properties-common ca-certificates apt-transport-https unzip tar

# 🧬 PHP & Dependencies
add-apt-repository ppa:ondrej/php -y
apt update -y
apt install -y php8.1 php8.1-{cli,common,mbstring,gd,curl,mysql,bcmath,xml,fpm,zip}

# 🐳 Docker
curl -sSL https://get.docker.com | sh
systemctl enable --now docker

# 🧬 Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 📦 Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# 🐘 MariaDB Setup
systemctl enable --now mariadb
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'ptero'@'127.0.0.1' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 📂 Panel Install
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

# 🌐 NGINX setup
apt install -y nginx
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

# 🧬 Wings setup
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

echo -e "\n📥 Paste your Wings config URL (from panel):"
read -p "🔗 URL: " config_url
if curl --output /dev/null --silent --head --fail "$config_url"; then
    curl -Lo config.yml "$config_url"
else
    echo "❌ Invalid URL. Wings config download failed."
    exit 1
fi

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

# ✅ Done
echo -e "\n\e[1;32m✅ ADVIK SETUP COMPLETE!"
echo "🌐 Panel: http://<your-server-ip>"
echo "🛠 MySQL: user=ptero / pass=StrongPassword123!"
echo "🧬 Wings: running and linked"
echo -e "🛑 To resume install if disconnected: \e[4mtmux attach\e[0m"
echo -e "\e[0m"
