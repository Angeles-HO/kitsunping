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
  echo "Error: Variables de entorno (MODPATH, MODID, NVBASE) no definidas."
  exit 1
fi

# INFO contendrá la ruta del archivo de información que registra los cambios realizados.
INFO="$MODPATH/INFO"

# =============================================================================
# Procesar el archivo de información si existe.
# =============================================================================
if [[ -f "$INFO" ]]; then
  # Leer línea por línea el archivo INFO.
  while read -r LINE; do
    # Si la línea termina con el carácter '~', se ignora.
    if [[ "${LINE: -1}" == "~" ]]; then
      echo "Ignorando la línea que termina con '~': $LINE"
      continue
    fi

    # Si existe un archivo de respaldo (archivo con sufijo '~'), restaurarlo.
    if [[ -f "${LINE}~" ]]; then
      mv -f "${LINE}~" "$LINE"
      if [[ $? -eq 0 ]]; then
        echo "Restaurado correctamente: ${LINE} desde ${LINE}~"
      else
        echo "Error: no se pudo restaurar ${LINE} desde ${LINE}~"
      fi
      continue
    fi

    # Si la ruta especificada en la línea existe, eliminarla.
    if [[ -e "$LINE" ]]; then
      rm -rf "$LINE"
      if [[ $? -eq 0 ]]; then
        echo "Eliminado: $LINE"
      else
        echo "Error: no se pudo eliminar: $LINE"
      fi

      # Recorrer hacia arriba en la jerarquía de directorios para eliminar directorios vacíos.
      while true; do 
        LINE="$(dirname "$LINE")"
        if [[ -z "$(ls -A "$LINE" 2>/dev/null)" ]]; then
          rm -rf "$LINE"
          if [[ $? -eq 0 ]]; then
            echo "Eliminado directorio vacío: $LINE"
          else
            echo "Error: no se pudo eliminar directorio vacío: $LINE"
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
    echo "Archivo de información eliminado: $INFO"
  else
    echo "Error: no se pudo eliminar el archivo de información: $INFO"
  fi
fi

# =============================================================================
# Eliminar el directorio del módulo (MODPATH) si existe.
# =============================================================================
if [[ -d "$MODPATH" ]]; then
  rm -rf "$MODPATH"
  if [[ $? -eq 0 ]]; then
    echo "El módulo ha sido completamente eliminado de $MODPATH"
  else
    echo "Error: No se pudo eliminar el módulo en $MODPATH"
  fi
fi

# =============================================================================
# Eliminar la carpeta del módulo en la ruta de actualizaciones.
# =============================================================================
if [[ -d "$NVBASE/modules_update/$MODID" ]]; then
  rm -rf "$NVBASE/modules_update/$MODID"
  if [[ $? -eq 0 ]]; then
    echo "Carpeta del módulo eliminada de $NVBASE/modules_update"
  else
    echo "Error: no se pudo eliminar la carpeta del módulo en $NVBASE/modules_update"
  fi
fi

# =============================================================================
# Eliminar la carpeta del módulo en la ruta de módulos.
# =============================================================================
if [[ -d "$NVBASE/modules/$MODID" ]]; then
  rm -rf "$NVBASE/modules/$MODID"
  if [[ $? -eq 0 ]]; then
    echo "Carpeta del módulo eliminada de $NVBASE/modules"
  else
    echo "Error: no se pudo eliminar la carpeta del módulo en $NVBASE/modules"
  fi
fi

exit 0