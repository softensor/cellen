#!/bin/bash
# Cellen deployment script
# Run once on the VPS when you have a domain.
# Usage: bash deploy.sh your-domain.com
#
# Prerequisites on VPS:
#   - Python 3.11+
#   - PostgreSQL running
#   - nginx installed
#   - certbot installed

set -e

DOMAIN=${1:?"Usage: bash deploy.sh your-domain.com"}
APP_DIR=/var/www/cellen
DB_NAME=cellen
DB_USER=cellen

echo "==> Deploying Cellen to $DOMAIN"

# 1. Copy files
echo "==> Creating app directory..."
sudo mkdir -p $APP_DIR
sudo rsync -a --exclude='.git' --exclude='.venv' --exclude='mobile' --exclude='deploy' \
    ./ $APP_DIR/
sudo mkdir -p $APP_DIR/media

# 2. Python venv + deps
echo "==> Installing dependencies..."
cd $APP_DIR
sudo python3 -m venv .venv
sudo .venv/bin/pip install --prefer-binary -r requirements.txt -q

# 3. Database
echo "==> Creating database..."
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD 'CHANGE_ME';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true

# 4. .env file
if [ ! -f $APP_DIR/.env ]; then
    echo "==> Creating .env (edit SECRET_KEY and passwords!)"
    cat > $APP_DIR/.env <<EOF
DATABASE_URL=postgresql+asyncpg://$DB_USER:CHANGE_ME@localhost:5432/$DB_NAME
SECRET_KEY=$(openssl rand -hex 32)
PLATFORM_ADMIN_EMAIL=admin@$DOMAIN
PLATFORM_ADMIN_PASSWORD=CHANGE_ME
MEDIA_DIR=$APP_DIR/media
EOF
fi

# 5. Run migrations
echo "==> Running migrations..."
cd $APP_DIR && sudo .venv/bin/alembic upgrade head

# 6. Systemd service
echo "==> Installing systemd service..."
sudo cp deploy/cellen-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cellen-api
sudo systemctl restart cellen-api

# 7. Nginx
echo "==> Configuring nginx..."
sudo sed "s/YOUR_DOMAIN_HERE/$DOMAIN/g" deploy/nginx.conf \
    > /etc/nginx/sites-available/cellen
sudo ln -sf /etc/nginx/sites-available/cellen /etc/nginx/sites-enabled/cellen
sudo nginx -t && sudo systemctl reload nginx

# 8. SSL
echo "==> Obtaining SSL certificate..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

# 9. Permissions
sudo chown -R www-data:www-data $APP_DIR

echo ""
echo "✓ Cellen deployed at https://$DOMAIN"
echo ""
echo "IMPORTANT: Edit $APP_DIR/.env and set real passwords, then:"
echo "  sudo systemctl restart cellen-api"
