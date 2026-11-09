# La app Flutter YA COMPILADA, servida por nginx.
#
# Acá no se compila nada: `flutter build web` corre en el runner de GitHub,
# donde hay máquina de sobra, y la imagen solo empaqueta el resultado. Meter
# el SDK de Flutter (1,4 GB) y dart2js dentro del Dockerfile deja la imagen
# en varios GB y llena el disco del VPS, que además comparte con Kufac,
# Quinde 17 y la carta.
#
# El contexto de build NO es la raíz del repositorio: el workflow arma una
# carpeta con solo lo necesario (ver .github/workflows/desplegar-web.yml):
#
#   contexto/
#     web/          <- build/web
#     nginx.conf    <- deploy/nginx.conf
#     Dockerfile    <- este archivo
#
# Para construirla a mano desde el Mac:
#   flutter build web --release --no-web-resources-cdn
#   mkdir -p /tmp/wasi-web && cp -r build/web /tmp/wasi-web/web
#   cp deploy/nginx.conf deploy/Dockerfile /tmp/wasi-web/
#   docker build -t wasi-web /tmp/wasi-web
FROM nginx:alpine

COPY web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# 127.0.0.1 y no localhost: éste resuelve a ::1 dentro del contenedor.
# Traefik descarta los contenedores unhealthy, así que un healthcheck mal
# apuntado no "avisa" de un problema: directamente deja el sitio fuera.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/salud || exit 1
