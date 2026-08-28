#!/usr/bin/env bash
# Verifica que nexus_bridge/server/security.lua (el canonico) no haya cambiado
# desde que se vendorizo en nexus_contracts/server/security_fallback.lua.
# No prueba equivalencia de comportamiento -- eso lo hace
# verify_security_fallback.lua. Este script solo detecta que el canonico se
# movio y toca re-vendorizar (y re-correr la prueba de equivalencia).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL="$SCRIPT_DIR/../../nexus_bridge/server/security.lua"
VENDORED="$SCRIPT_DIR/../server/security_fallback.lua"

if [ ! -f "$CANONICAL" ]; then
    echo "ERROR: no se encontro el canonico en $CANONICAL"
    exit 2
fi
if [ ! -f "$VENDORED" ]; then
    echo "ERROR: no se encontro el vendorizado en $VENDORED"
    exit 2
fi

HEADER_HASH=$(grep -oE 'source_sha256:[[:space:]]*[0-9a-f]{64}' "$VENDORED" | grep -oE '[0-9a-f]{64}' || true)
if [ -z "$HEADER_HASH" ]; then
    echo "ERROR: no se encontro source_sha256 en el encabezado de $VENDORED"
    exit 2
fi

CURRENT_HASH=$(sha256sum "$CANONICAL" | cut -d' ' -f1)

if [ "$HEADER_HASH" != "$CURRENT_HASH" ]; then
    echo "DERIVA: nexus_bridge/server/security.lua cambio desde que se vendorizo."
    echo "  hash en el encabezado del vendorizado: $HEADER_HASH"
    echo "  hash actual del canonico:              $CURRENT_HASH"
    echo "  Accion: revisar el diff del canonico, re-vendorizar security_fallback.lua,"
    echo "  actualizar source_sha256 en su encabezado, y re-correr verify_security_fallback.lua."
    exit 1
fi

echo "OK: sin deriva de hash entre el canonico y el vendorizado."
exit 0
