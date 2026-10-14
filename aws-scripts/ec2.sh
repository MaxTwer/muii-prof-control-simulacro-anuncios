#!/bin/bash

# Crea la instancia EC2, su IP pública estática y su grupo de seguridad.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

if [ ! -f "$PROJECT_ROOT/params.txt" ]; then
    echo "Error: falta params.txt. Ejecuta antes: bash params.sh <tu id>" >&2
    exit 1
fi

SG_NAME="anuncios-sg"

KEY_NAME="vockey"
# Ubuntu Server 26.04 LTS (x86_64, HVM, SSD gp3).
AMI_ID="ami-0b6d9d3d33ba97d99"

# Perfil de instancia de AWS Academy para acceder a Secrets Manager.
INSTANCE_PROFILE="LabInstanceProfile"

# t2.micro: 1 vCPU y 1 GiB de RAM.
INSTANCE_TYPE="t2.micro"

echo -n "Creando el grupo de seguridad... "
SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Aplicacion de anuncios" \
    --query "GroupId" \
    --output text)
echo "listo."

echo -n "Creando regla de acceso (http)... "
# Abre al mundo únicamente el puerto 80 (HTTP).
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --output text >/dev/null
echo "listo."

echo -n "Creando regla de acceso (ssh)... "
# Permite SSH solo desde la IP pública de la máquina desde la que despliegas.
MY_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$MY_IP/32" \
    --output text >/dev/null
echo "listo."

echo -n "Creando la instancia (pendiente de aprovisionamiento)... "
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --iam-instance-profile Name="$INSTANCE_PROFILE" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=anuncios-ec2}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "listo."

echo -n "Esperando a que la instancia esté lista... "
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "listo."

echo -n "Asignando la IP pública a la instancia... "
ALLOCATION_ID=$(aws ec2 allocate-address \
    --query "AllocationId" \
    --output text)
echo "listo."

echo -n "Asociando la IP pública a la instancia... "
aws ec2 associate-address \
    --instance-id "$INSTANCE_ID" \
    --allocation-id "$ALLOCATION_ID" \
    --output text >/dev/null
echo "listo."

echo -n "Esperando a que la IP pública esté asignada... "
sleep 45
echo "listo."

echo "ec2.sh terminado."