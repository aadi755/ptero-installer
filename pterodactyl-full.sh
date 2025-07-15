#!/bin/bash

# 💜 Advik's Full Pterodactyl Installer 

# ⛓️ Tmux check (only once)
if [ -z "$TMUX" ] && [ -z "$INSIDE_TMUX" ]; then
    echo -e "\e[1;33m⚠️ Not in tmux — starting safe install session...\e[0m"
    sudo apt install -y tmux
    export INSIDE_TMUX=1
    tmux new-session -s ptero-install "bash <(curl -s https://raw.githubusercontent.com/aadi755/ptero-installer/main/pterodactyl-full.sh)"
    exit 0
fi

echo -e "\e[1;35m
==============================================
   Advik's One-Click Pterodactyl Setup
   Panel + Wings + Safe for Termius 🚀
==============================================
\e[0m"

# ✅ Update system
apt update -y && apt upgrade -y

# 📦 Install base packages
apt install -y curl wget sudo lsb-release gnupg software-properties-common \
    ca-certificates apt-transport-https unzip tar

# 🧬 Add PHP 8.1 repo
add-apt-repository ppa:ondrej/php -y
apt update -y

# 🧬 Install PHP 8.1 + dependencies
apt install -y php8.1 php8.1-{cli,common,mbstring,gd,curl,mysql,bcmath,xml,fpm,zip}

# 🐘 Install MariaDB
apt install -y mariadb-server
systemctl enable --now mariadb

# 🔐 Setup database
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'ptero'@'127.0.0.1' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 🧬 Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 📦 Install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# 🌐 Install NGINX
apt install -y nginx

# 📂 Panel setup
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
composer install --no-dev --optimize-autoloader || { echo "❌ Composer failed."; exit 1; }
cp .env.example .env
php artisan key:generate --force

# ⚙️ Configure .env DB values
sed -i "s/DB_DATABASE=.*/DB_DATABASE=panel/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=ptero/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=StrongPassword123!/" .env

php artisan migrate --seed --force
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

# 🌍 Setup NGINX virtual host
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

# 🧬 Wings Setup
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

# 🔗 Ask for Wings config URL
echo -e "\n📥 Paste your Wings config URL (from panel node setup):"
read -p "🔗 URL: " config_url

if curl --output /dev/null --silent --head --fail "$config_url"; then
    curl -Lo config.yml "$config_url"
else
    echo "❌ Invalid URL. Wings config download failed."
    exit 1
fi

# 🛠️ Wings systemd service
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
IP=$(hostname -I | awk '{print $1}')
echo -e "\n\e[1;32m✅ INSTALL COMPLETE!"
echo -e "🌐 Panel: http://$IP"
echo "🧠 MySQL: user=ptero  pass=StrongPassword123!"
echo "🚀 Wings: installed + running"
echo "🛑 If disconnected, run: tmux attach"
echo -e "\e[0m"
