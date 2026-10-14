#!/bin/bash

# Compila el back, lo sube a la instancia y lo arranca como servicio systemd.
# Termina en el primer comando que falle y muestra el error de ese comando.
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

# TODO: Copia aquí, a mano, la IP pública de la instancia y, desde params.txt, el nombre del secreto y el EXAM_ID.
PUBLIC_IP=34.235.245.48
SECRET_NAME=prod/anuncios/110371
EXAM_ID=110371

BACKEND_PATH="$PROJECT_ROOT/back"

echo -n "Compilando el back... "
(cd "$BACKEND_PATH" && mvn -q clean package -DskipTests)
echo "listo."
BACKEND_JAR=$(find "$BACKEND_PATH/target" -maxdepth 1 -type f -name '*.jar' ! -name '*.original' -print -quit)
if [ -z "$BACKEND_JAR" ]; then
    echo "Error: No se encontró el JAR ejecutable del back."
    exit 1
fi

echo -n "Subiendo el back a $PUBLIC_IP... "
scp -q -o StrictHostKeyChecking=no -i "$KEY_PATH" "$BACKEND_JAR" ubuntu@"$PUBLIC_IP":/tmp/anuncios.jar
echo "listo."

echo "Configurando el servicio en la instancia EC2..."

# SECRET_NAME y EXAM_ID viajan como variables de entorno del servicio: no van en el JAR.
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" \
    "SECRET_NAME='$SECRET_NAME' EXAM_ID='$EXAM_ID' bash -s" << 'END_BACKEND'
set -e
sudo apt-get update -y
# El JAR está compilado para Java 21. Si 21 no está en los repositorios, vale cualquier JRE más nuevo.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre-headless \
    || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y default-jre-headless

sudo systemctl stop anuncios 2>/dev/null || true
sudo rm -rf /opt/anuncios
sudo mkdir -p /opt/anuncios
sudo mv /tmp/anuncios.jar /opt/anuncios/anuncios.jar
sudo chown -R ubuntu:ubuntu /opt/anuncios
# Datos de la base de datos: fuera de /opt/anuncios para que sobrevivan a los redespliegues.
sudo mkdir -p /var/lib/anuncios
sudo chown -R ubuntu:ubuntu /var/lib/anuncios

sudo tee /etc/systemd/system/anuncios.service > /dev/null << SERVICE
[Unit]
Description=Aplicación de anuncios (Spring Boot)
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/anuncios
Environment=SECRET_NAME=$SECRET_NAME
Environment=EXAM_ID=$EXAM_ID
Environment=DB_DIR=/var/lib/anuncios
ExecStart=/usr/bin/java -jar /opt/anuncios/anuncios.jar
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable anuncios
sudo systemctl restart anuncios
END_BACKEND

echo "Despliegue del back finalizado. Tarda unos segundos en arrancar. Comprobación:"
echo "  http://$PUBLIC_IP/api/whoami"
