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

exit 0