#!/bin/bash

# Instala Nginx en la instancia (Ubuntu). Sirve el front en / y reenvía /api/ al back en el
# puerto 8080. Termina en el primer comando que falle y muestra el error de ese comando.
set -e

PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

if [ ! -f "$PROJECT_ROOT/params.txt" ]; then
    echo "Error: falta params.txt. Ejecuta antes: bash params.sh <tu id>" >&2
    exit 1
fi

KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"
if [ ! -f "$KEY_PATH" ]; then
    echo "Error: No se encontró la clave SSH en: $KEY_PATH" >&2
    exit 1
fi

# TODO: Copia aquí, a mano, la IP pública de la instancia.
PUBLIC_IP=34.235.245.48

echo "Configurando Nginx en $PUBLIC_IP..."

# -T: sin pseudo-terminal, para que no avise al leer el script por stdin
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" bash -s << 'END_NGINX'
set -e
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

sudo tee /etc/nginx/sites-available/default > /dev/null << 'NGINX_CONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX_CONF

sudo rm -rf /var/www/html/*
echo '<h1>Aplicación de anuncios</h1><p>Desplegando...</p>' | sudo tee /var/www/html/index.html > /dev/null
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
END_NGINX

echo "Configuración de Nginx finalizada."
