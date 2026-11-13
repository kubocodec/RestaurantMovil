#!/usr/bin/env bash
#
# Revisa un .xlsx armado por lib/core/exportar/xlsx_minimo.dart sin tener
# Excel instalado: zip íntegro, cada parte XML bien formada, y una vista
# previa con Quick Look (macOS) para mirarla.
#
#   flutter test test/exportar          # escribe build/ejemplo_exportacion.xlsx
#   tool/validar_xlsx.sh build/ejemplo_exportacion.xlsx
#
# No reemplaza abrirlo en Excel: Excel es más estricto con el orden de los
# elementos y con los estilos, y eso solo se ve abriéndolo ahí.
set -euo pipefail

ARCHIVO="${1:-build/ejemplo_exportacion.xlsx}"
[ -f "$ARCHIVO" ] || { echo "No existe $ARCHIVO"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Zip"
unzip -tq "$ARCHIVO"

echo "==> XML de cada parte"
unzip -q -o "$ARCHIVO" -d "$TMP/partes"
MAL=0
while IFS= read -r -d '' f; do
  if ! xmllint --noout "$f" 2>"$TMP/err"; then
    echo "MAL  ${f#"$TMP/partes/"}: $(head -2 "$TMP/err")"
    MAL=1
  fi
done < <(find "$TMP/partes" -type f -print0)
[ "$MAL" = 0 ] && echo "    todas bien formadas ($(find "$TMP/partes" -type f | wc -l | tr -d ' ') partes)"

echo "==> Hojas"
grep -o '<sheet name="[^"]*"' "$TMP/partes/xl/workbook.xml" | sed 's/<sheet name=/    /'

if command -v qlmanage >/dev/null 2>&1; then
  SALIDA="$(dirname "$ARCHIVO")"
  qlmanage -t -s 1400 -o "$SALIDA" "$ARCHIVO" >/dev/null 2>&1 \
    && echo "==> Vista previa: $SALIDA/$(basename "$ARCHIVO").png"
fi
exit "$MAL"
