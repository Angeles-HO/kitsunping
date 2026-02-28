#!/system/bin/sh
# =============================================================================
# Script de desinstalación del módulo Kitsuneping
#
# Este script restaura archivos respaldados y elimina las carpetas y archivos
# asociados al módulo. Se incluyen controles de errores para informar de posibles
# problemas durante el proceso de desinstalación.
# =============================================================================

# =============================================================================
# Variables del módulo
# =============================================================================

# =============================================================================
# Verificar que las variables de entorno esenciales estén definidas.
# =============================================================================
if [[ -z "$MODPATH" || -z "$MODID" || -z "$NVBASE" ]]; then
  echo "Error: Environment variables (MODPATH, MODID, NVBASE) are not defined."
  exit 1
fi

# INFO contendrá la ruta del archivo de información que registra los cambios realizados.
INFO="$MODPATH/INFO"

# =============================================================================
# Procesar el archivo de información si existe.
# =============================================================================
if [[ -f "$INFO" ]]; then
  # Read INFO line by line.
  while read -r LINE; do
    # Si la línea termina con el carácter '~', se ignora.
    if [[ "${LINE: -1}" == "~" ]]; then
      echo "Skipping line ending with '~': $LINE"
      continue
    fi

    # Si existe un archivo de respaldo (archivo con sufijo '~'), restaurarlo.
    if [[ -f "${LINE}~" ]]; then
      mv -f "${LINE}~" "$LINE"
      if [[ $? -eq 0 ]]; then
        echo "Restored: ${LINE} from ${LINE}~"
      else
        echo "Error: could not restore ${LINE} from ${LINE}~"
      fi
      continue
    fi

    # Si la ruta especificada en la línea existe, eliminarla.
    if [[ -e "$LINE" ]]; then
      rm -rf "$LINE"
      if [[ $? -eq 0 ]]; then
        echo "Removed: $LINE"
      else
        echo "Error: could not remove: $LINE"
      fi

      # Recorrer hacia arriba en la jerarquía de directorios para eliminar directorios vacíos.
      while true; do 
        LINE="$(dirname "$LINE")"
        if [[ -z "$(ls -A "$LINE" 2>/dev/null)" ]]; then
          rm -rf "$LINE"
          if [[ $? -eq 0 ]]; then
             echo "Removed empty directory: $LINE"
          else
             echo "Error: could not remove empty directory: $LINE"
            break
          fi
        else
          break
        fi
      done
    fi
  done < "$INFO"

  # Eliminar el archivo de información después de procesarlo.
  rm -rf "$INFO"
  if [[ $? -eq 0 ]]; then
    echo "Info file removed: $INFO"
  else
    echo "Error: could not remove info file: $INFO"
  fi
fi

# =============================================================================
# Eliminar el directorio del módulo (MODPATH) si existe.
# =============================================================================
if [[ -d "$MODPATH" ]]; then
  rm -rf "$MODPATH"
  if [[ $? -eq 0 ]]; then
    echo "Module removed from $MODPATH"
  else
    echo "Error: could not remove module at $MODPATH"
  fi
fi

# =============================================================================
# Eliminar la carpeta del módulo en la ruta de actualizaciones.
# =============================================================================
if [[ -d "$NVBASE/modules_update/$MODID" ]]; then
  rm -rf "$NVBASE/modules_update/$MODID"
  if [[ $? -eq 0 ]]; then
    echo "Module folder removed from $NVBASE/modules_update"
  else
    echo "Error: could not remove module folder in $NVBASE/modules_update"
  fi
fi

# =============================================================================
# Eliminar la carpeta del módulo en la ruta de módulos.
# =============================================================================
if [[ -d "$NVBASE/modules/$MODID" ]]; then
  rm -rf "$NVBASE/modules/$MODID"
  if [[ $? -eq 0 ]]; then
    echo "Module folder removed from $NVBASE/modules"
  else
    echo "Error: could not remove module folder in $NVBASE/modules"
  fi
fi

# =============================================================================
# Eliminar los props del módulo si existen.
# =============================================================================

clear_module_prop() {
  local prop current
  prop="$1"
  current="$(getprop "$prop" 2>/dev/null | tr -d '\r\n')"

  if [[ -n "$current" ]]; then
    if command -v resetprop >/dev/null 2>&1; then
      resetprop -n "$prop" "" >/dev/null 2>&1 || setprop "$prop" ""
    else
      setprop "$prop" ""
    fi
    echo "Cleared prop: $prop"
  fi
}

MODULE_PROPS="
kitsunping.calibration.priority
kitsunping.daemon.interval
kitsunping.daemon.net_probe_interval
kitsunping.daemon.signal_poll_interval
kitsunping.event.debounce_sec
kitsunping.heavy_load
kitsunping.router.cache_ttl
kitsunping.router.debug
kitsunping.router.experimental
kitsunping.router.infer_width
kitsunping.router.openwrt_mode
kitsunping.sigmoid.alpha
kitsunping.sigmoid.beta
kitsunping.sigmoid.gamma
kitsunping.wifi.speed_threshold
kitsunrouter.debug
kitsunrouter.enable
persist.kitsunping.calibrate_cache_enable
persist.kitsunping.calibrate_cache_loss_pct
persist.kitsunping.calibrate_cache_max_age_sec
persist.kitsunping.calibrate_cache_rtt_ms
persist.kitsunping.calibrate_cache_transport_strict
persist.kitsunping.calibrate_dns_setprop_fallback
persist.kitsunping.debug
persist.kitsunping.dev_score_divisor
persist.kitsunping.dev_score_sim_enable
persist.kitsunping.direct_broadcast
persist.kitsunping.emit_events
persist.kitsunping.event_debounce_sec
persist.kitsunping.paired
persist.kitsunping.ping_timeout
persist.kitsunping.ram.class
persist.kitsunping.ram.size
persist.kitsunping.router.cache_ttl
persist.kitsunping.router.debug
persist.kitsunping.router.experimental
persist.kitsunping.router.infer_width
persist.kitsunping.router.openwrt_mode
persist.kitsunping.target_prop_enable
persist.kitsunping.target_request_cooldown_sec
persist.kitsunping.user_event
persist.kitsunping.user_event_data
persist.kitsunrouter.debug
persist.kitsunrouter.enable
persist.kitsunrouter.paired
"

for prop in $MODULE_PROPS; do
  clear_module_prop "$prop"
done

exit 0