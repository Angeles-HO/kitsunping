#!/system/bin/sh
get_cpu_arch() {
    local cpu_abi

    # Obtener la propiedad del sistema
    cpu_abi=$(getprop ro.product.cpu.abi 2>/dev/null)

    # Validar que se obtuvo el valor
    if [ -z "$cpu_abi" ]; then
        echo "Error: No se pudo obtener ro.product.cpu.abi" >&2
        return 1
    fi

    # Determinar arquitectura sin usar case
    if [[ "$cpu_abi" == *arm* || "$cpu_abi" == *aarch* ]]; then
        echo "arm"
        return 0
    elif [[ "$cpu_abi" == *x86* || "$cpu_abi" == *amd64* ]]; then
        echo "x86"
        return 0
    else
        echo "Error: Arquitectura no soportada: $cpu_abi" >&2
        return 2
    fi
}

chooseport_legacy() {
    # Keycheck binary by someone755 @Github, idea para el código de Zappo @xda-developers
    [ "$1" ] && local delay=$1 || local delay=60
    local error=false
    local ARCH32=$(get_cpu_arch)

    while true; do
        timeout 0 "$MODPATH/addon/Volume-Key-Selector/tools/$ARCH32/keycheck"
        timeout $delay "$MODPATH/addon/Volume-Key-Selector/tools/$ARCH32/keycheck"
        local sel=$?

        if [ "$sel" -eq 42 ]; then
            return 0
        elif [ "$sel" -eq 41 ]; then
            return 1
        else
            if $error; then
                abort "Error crítico en keycheck legacy!"
            else
                error=true
                echo "Try again!" >&2
            fi
        fi
    done
}

chooseport() {
    [ "$1" ] && local delay=$1 || local delay=60
    local error=false 
    local count=0

    while true; do
        count=0
        # Intentar detectar eventos con getevent
        while true; do
            timeout $delay /system/bin/getevent -lqc 1 2>&1 > "$TMPDIR/events" &
            sleep 0.5
            count=$((count + 1))
            if grep -q 'KEY_VOLUMEUP *DOWN' "$TMPDIR/events"; then
                return 0
            elif grep -q 'KEY_VOLUMEDOWN *DOWN' "$TMPDIR/events"; then
                return 1
            fi
            [ $count -gt 60 ] && break
        done
        # Si llegamos aquí, no se detectó ninguna tecla
        if $error; then
            echo "Trying keycheck method..." >&2
            export chooseport=chooseport_legacy
            export VKSEL=chooseport_legacy
            chooseport_legacy $delay
            return $?
        else
            error=true
            echo "Volume key not detected, try again!" >&2
        fi
    done
}

VKSEL=chooseport