#!/usr/bin/env bash
#
# Despliega la app web de Wasi en ESTE servidor. Lo ejecuta GitHub Actions por
# SSH dentro de ~/kubocode/wasi-web, pero también sirve para relanzar a mano.
#
# Variables de entorno necesarias:
#   IMAGE    imagen a desplegar (ghcr.io/<org>/<repo>-web:<sha>)
#   DOMAIN   subdominio público (wasi.kubocode.com)
#
# No hay claves ni datos: la app web es estática y habla con el API de
# producción, cuya dirección va compilada dentro del build.

set -euo pipefail
cd "$(dirname "$0")"

: "${IMAGE:?Falta la variable IMAGE}"
: "${DOMAIN:?Falta la variable DOMAIN (ej. wasi.kubocode.com)}"

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: falta el plugin 'docker compose' en el servidor."
  exit 1
fi

# El certificado se pide por HTTP-01: si el dominio todavía no apunta aquí,
# Let's Encrypt falla y Traefik se queda sirviendo un certificado falso que
# después cuesta destrabar. Mejor detenerse antes.
echo "==> Comprobando que ${DOMAIN} apunte a este servidor"
if ! command -v getent >/dev/null 2>&1; then
  echo "    (sin getent en el servidor: me salto la comprobación)"
else
  IP_DOMINIO="$(getent hosts "${DOMAIN}" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [ -z "${IP_DOMINIO}" ]; then
    echo "ERROR: ${DOMAIN} todavía no resuelve. Creá el registro A y esperá unos minutos."
    exit 1
  fi
  IP_SERVIDOR="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  if [ -n "${IP_SERVIDOR}" ] && [ "${IP_DOMINIO}" != "${IP_SERVIDOR}" ]; then
    # No se aborta: puede haber un proxy o CDN delante y seguir siendo correcto.
    # Y esto corre sin terminal desde Actions, así que nunca se pregunta nada.
    echo "AVISO: ${DOMAIN} resuelve a ${IP_DOMINIO} y este servidor se ve como ${IP_SERVIDOR}."
    echo "       Si no hay un proxy delante, el certificado va a fallar."
  else
    echo "    ${DOMAIN} -> ${IP_DOMINIO}"
  fi
fi

echo "==> Detectando la configuración de Traefik"
./detectar-traefik.sh "${IMAGE}" "${DOMAIN}"

echo "==> Descargando la imagen"
docker compose pull --quiet

echo "==> Levantando la nueva versión"
docker compose up -d --remove-orphans

echo "==> Esperando a que el contenedor quede sano"
ESTADO="desconocido"
for _ in $(seq 1 45); do
  ESTADO="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}' wasi-web 2>/dev/null || echo ausente)"
  [ "${ESTADO}" = "healthy" ] && break
  sleep 2
done

if [ "${ESTADO}" != "healthy" ]; then
  echo "ERROR: el contenedor no quedó sano (estado: ${ESTADO})."
  echo "--- Últimas líneas del log ---"
  docker compose logs --tail 40 web
  exit 1
fi
echo "    Contenedor: healthy"

docker image prune -f >/dev/null
echo "App web desplegada $(date '+%Y-%m-%d %H:%M:%S') · ${IMAGE##*:}" >> deploy.log
docker compose ps
