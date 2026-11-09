#!/usr/bin/env bash
#
# (El mismo script que usan Kufac y Quinde 17 en este VPS.)
#
# Detecta cómo está configurado Traefik en ESTE servidor y escribe el archivo
# .env que consume docker-compose.yml (red, resolver de certificados y
# entrypoints). Así el despliegue funciona sin tener que adivinar nombres.
#
# Uso:  ./detectar-traefik.sh <IMAGEN> <DOMINIO>

set -euo pipefail

IMAGE="${1:?Falta la imagen. Uso: ./detectar-traefik.sh <IMAGEN> <DOMINIO>}"
DOMAIN="${2:?Falta el dominio. Uso: ./detectar-traefik.sh <IMAGEN> <DOMINIO>}"

# Red compartida que se usa/crea si Traefik no declara una explícitamente.
RED_COMPARTIDA="${RED_COMPARTIDA:-traefik-proxy}"

echo "==> Buscando el contenedor de Traefik"
CID="$(docker ps --format '{{.ID}}|{{.Image}}|{{.Names}}' \
  | awk -F'|' 'tolower($2) ~ /traefik/ || tolower($3) ~ /traefik/ { print $1; exit }')"

if [ -z "${CID}" ]; then
  echo "ERROR: no hay ningún contenedor de Traefik en marcha en este servidor."
  echo "       Revisa 'docker ps' y levanta Traefik antes de desplegar."
  exit 1
fi

NOMBRE_TRAEFIK="$(docker inspect -f '{{.Name}}' "${CID}" | sed 's|^/||')"
echo "    Traefik encontrado: ${NOMBRE_TRAEFIK}"

redes_de_traefik() {
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "${CID}"
}

# --- Configuración de Traefik (argumentos de arranque + fichero estático) ---
CONFIG="$(docker inspect -f '{{json .Args}} {{json .Config.Cmd}} {{json .Config.Entrypoint}}' "${CID}" 2>/dev/null || true)"
CONFIG="${CONFIG}
$(docker exec "${CID}" sh -c 'cat /etc/traefik/traefik.yml /etc/traefik/traefik.yaml /traefik.yml /traefik.yaml 2>/dev/null' 2>/dev/null || true)"

# --- Modo de red -----------------------------------------------------------
MODO_RED="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "${CID}")"

if [ "${MODO_RED}" = "host" ]; then
  cat <<'AYUDA'

ERROR: Traefik está corriendo con network_mode: host.

  En ese modo Docker no permite conectarlo a ninguna red, así que no puede
  enrutar de forma fiable hacia los contenedores de las aplicaciones.

  Hay que migrarlo a red bridge con una red externa compartida (una sola vez).
  Los pasos están en docs/DESPLIEGUE.md del proyecto Quinde 17, sección
  "Migrar Traefik a la red compartida". Resumen:

    1. docker network create traefik-proxy
    2. En el compose de Traefik: quitar 'network_mode: host', publicar los
       puertos 80 y 443, y añadir la red externa traefik-proxy.
    3. docker compose up -d

AYUDA
  exit 1
fi

# --- Red -------------------------------------------------------------------
# 1º preferencia: la red que Traefik declara en providers.docker.network
RED="$(printf '%s' "${CONFIG}" \
  | grep -oiE 'providers\.docker\.network=[A-Za-z0-9_.-]+' | head -1 | cut -d= -f2 || true)"

if [ -n "${RED}" ]; then
  echo "    Traefik declara providers.docker.network=${RED}"
  if ! redes_de_traefik | grep -Fxq "${RED}"; then
    echo "ERROR: Traefik dice usar la red '${RED}' pero no está conectado a ella."
    echo "       Añádela a su docker-compose.yml y ejecuta 'docker compose up -d'."
    exit 1
  fi
else
  # 2º preferencia: la primera red propia a la que esté conectado
  RED="$(redes_de_traefik | grep -vE '^(bridge|host|none)$' | grep -v '^$' | head -1 || true)"
fi

if [ -z "${RED}" ]; then
  # 3º: solo está en la red 'bridge' por defecto -> preparar red compartida
  echo "    Traefik solo está en la red 'bridge' por defecto, que no permite"
  echo "    enrutar a otros contenedores. Preparando una red compartida."

  if ! docker network inspect "${RED_COMPARTIDA}" >/dev/null 2>&1; then
    echo "    Creando la red '${RED_COMPARTIDA}'"
    docker network create "${RED_COMPARTIDA}" >/dev/null
  fi

  echo "    Conectando ${NOMBRE_TRAEFIK} a '${RED_COMPARTIDA}'"
  docker network connect "${RED_COMPARTIDA}" "${CID}" >/dev/null 2>&1 || true

  if ! redes_de_traefik | grep -Fxq "${RED_COMPARTIDA}"; then
    echo "ERROR: no se pudo conectar Traefik a la red '${RED_COMPARTIDA}'."
    echo "       Añádela al docker-compose.yml de Traefik (ver docs/DESPLIEGUE.md de Quinde 17)."
    exit 1
  fi

  RED="${RED_COMPARTIDA}"
  echo "    Hecho. Añade esa red al compose de Traefik para que sea permanente."
fi
echo "    Red: ${RED}"

# --- Resolver de certificados (Let's Encrypt) ------------------------------
CERT_RESOLVER="$(printf '%s' "${CONFIG}" \
  | grep -oiE 'certificatesresolvers\.[A-Za-z0-9_-]+' | head -1 | cut -d. -f2 || true)"

if [ -z "${CERT_RESOLVER}" ]; then
  # Formato de fichero YAML: certificatesResolvers:\n  <nombre>:
  CERT_RESOLVER="$(printf '%s' "${CONFIG}" \
    | grep -iA3 'certificatesResolvers:' \
    | grep -oE '^[[:space:]]+[A-Za-z0-9_-]+:' | head -1 | tr -d ' :' || true)"
fi

if [ -z "${CERT_RESOLVER}" ]; then
  echo ""
  echo "ERROR: Traefik no tiene configurado ningún resolver de certificados."
  echo "       Sin él no se puede emitir el certificado HTTPS de ${DOMAIN}."
  echo ""
  echo "--- Configuración con la que arrancó Traefik ---"
  printf '%s' "${CONFIG}" | tr ',' '\n' | sed 's/^/    /' | head -60
  exit 1
fi
echo "    Resolver de certificados: ${CERT_RESOLVER}"

# --- Entrypoints -----------------------------------------------------------
ENTRYPOINT_HTTPS="$(printf '%s' "${CONFIG}" \
  | grep -oiE 'entrypoints\.[A-Za-z0-9_-]+\.address=:443' | head -1 | cut -d. -f2 || true)"
ENTRYPOINT_HTTP="$(printf '%s' "${CONFIG}" \
  | grep -oiE 'entrypoints\.[A-Za-z0-9_-]+\.address=:80' | head -1 | cut -d. -f2 || true)"

ENTRYPOINT_HTTPS="${ENTRYPOINT_HTTPS:-websecure}"
ENTRYPOINT_HTTP="${ENTRYPOINT_HTTP:-web}"
echo "    Entrypoints: ${ENTRYPOINT_HTTP} (80) / ${ENTRYPOINT_HTTPS} (443)"

# --- Escribir .env ---------------------------------------------------------
cat > .env <<ENVEOF
# Generado automáticamente por detectar-traefik.sh — no editar a mano.
IMAGE=${IMAGE}
DOMAIN=${DOMAIN}
TRAEFIK_NETWORK=${RED}
CERT_RESOLVER=${CERT_RESOLVER}
ENTRYPOINT_HTTP=${ENTRYPOINT_HTTP}
ENTRYPOINT_HTTPS=${ENTRYPOINT_HTTPS}
ENVEOF

echo "==> .env generado:"
sed 's/^/    /' .env
