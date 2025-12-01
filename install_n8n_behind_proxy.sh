#!/bin/bash

# Check if the script is run with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges" 
   exit 1
fi

# Function to check domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)
    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain is correctly pointed
    else
        return 1  # Domain is not correctly pointed
    fi
}
echo "Welcome to MeCode - N8N Install Script"
# Get domain input from user
read -p "Enter your domain or subdomain: " DOMAIN

# Check domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation."
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Use /home directory directly
N8N_DIR="/home/n8n"

# Install Docker and Docker Compose
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Create directory for n8n
mkdir -p $N8N_DIR

# Create docker-compose.yml file
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_DIAGNOSTICS_ENABLED=false
    volumes:
      - $N8N_DIR:/home/node/.n8n
    networks:
      - n8n_network
    dns:
      - 8.8.8.8
      - 1.1.1.1

networks:
  n8n_network:
    driver: bridge
EOF

# Set permissions for n8n directory
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Start the container
cd $N8N_DIR
docker-compose up -d

echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                             ║"
echo "║  ✅ N8n đã được cài đặt thành công!                        ║"
echo "║                                                             ║"
echo "║  🌐 Truy cập: http://${DOMAIN}:5678                        ║"
echo "║                                                             ║"
echo "║  📚 Học n8n cơ bản: https://n8n-basic.mecode.pro           ║"
echo "║                                                             ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo ""
echo "Để hoàn tất cài đặt, bạn cần cấu hình proxy. Dưới đây là ví dụ cho Nginx:"
echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                             ║"
echo "║  🔧 Cấu hình Nginx:                                        ║"
echo "║                                                             ║"
cat << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
echo "║                                                             ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo ""
echo "Sau khi tạo file cấu hình:"
echo "1. Lưu vào /etc/nginx/sites-available/${DOMAIN}"
echo "2. Tạo symbolic link: sudo ln -s /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/"
echo "3. Kiểm tra cấu hình Nginx: sudo nginx -t"
echo "4. Nếu không có lỗi, khởi động lại Nginx: sudo systemctl restart nginx"
echo ""
echo "Để sử dụng HTTPS, hãy xem xét sử dụng Certbot để cài đặt SSL tự động."
