# Next Generation: candidatos de red y descubrimiento

Este documento es una cola de investigacion para Kitsunping v7.0-beta, no una lista de valores que deban escribirse en todos los dispositivos. Un ajuste entra a produccion solo si tiene propietario conocido, puerta de compatibilidad por OEM/version, respaldo, restauracion y medicion que demuestre una mejora.

## Principios de filtrado

- `settings put` solo es valido cuando la clave pertenece realmente a la tabla `system`, `secure` o `global` y su efecto se puede observar. Que el comando no falle no demuestra que Android la consuma.
- `persist.*`, `vendor.*`, `ril.*`, `net.*` y `ro.*` no son ajustes globales intercambiables: suelen ser propiedades de framework, modem o proveedor. No deben escribirse mediante `settings put`.
- No modificar pais, dominio regulatorio, canales Wi-Fi, banda SoftAP, IMS/VoWiFi, tethering ni configuracion de radio. Son superficies dependientes de hardware, operador y regulacion; no son optimizaciones generales de Kitsunping.
- No tratar los buffers `tcp.buffersize.*` como `settings global`. Antes de considerarlos hay que comprobar el propietario real, el mecanismo de aplicacion y la restauracion exacta.
- Cada experimento cambia una sola variable, conserva una linea base y termina con una restauracion comprobada. Los resultados locales y datos de red no se empaquetan en el modulo.

## Candidatos priorizados

### A. Controles ya soportados por Kitsunping

Estos controles ya tienen una ruta de ejecucion en `policy/executor/profile_runner.sh`. La prioridad es completar medicion y preflight, no inventar otra capa de propiedades.

| Control | Perfiles actuales | Condicion | Restauracion | Evidencia requerida |
| --- | --- | --- | --- | --- |
| `wifi_scan_throttle_enabled=0` | gaming, benchmark, benchmark_speed | Binario `settings` disponible | Kitsunping guarda el valor previo y lo restaura o elimina la clave si estaba ausente | Comparar latencia, perdida, roaming y consumo con linea base |
| `cmd wifi force-low-latency-mode enabled` | gaming, benchmark | `cache/preflight.state` confirma `cmd_wifi_low_latency=1` | Desactivar al salir del perfil | Verificar el estado de Wi-Fi y estabilidad sostenida |
| `cmd wifi force-hi-perf-mode enabled` | benchmark, benchmark_speed | `cache/preflight.state` confirma `cmd_wifi_hi_perf=1` | Desactivar al salir del perfil | Medir caudal, RTT y consumo termico/bateria |
| `cmd wifi set-connected-score` | gaming=60, benchmark=80, benchmark_speed=100 | El servicio `cmd wifi` acepta el comando | `cmd wifi reset-connected-score` al salir | Confirmar que no degrada handover ni desconecta redes buenas |

Accion propuesta: centralizar estos cuatro controles en una declaracion por perfil que indique preflight, valor, archivo de respaldo, rollback y metricas. No ampliar perfiles hasta que esta ruta sea medible de extremo a extremo.

### B. Ajustes Android que pueden investigarse por dispositivo

Estos son candidatos de laboratorio, no valores predeterminados. Solo se pueden promover si el dispositivo devuelve una clave existente o documentada y se puede restaurar su valor previo.

| Candidato | Hipotesis | Riesgo principal | Puerta de admision |
| --- | --- | --- | --- |
| `global wifi_scan_always_enabled` | Reducir escaneos en segundo plano puede ahorrar energia cuando no se necesita ubicacion Wi-Fi. | Puede afectar ubicacion, escaneo solicitado por apps y descubrimiento. | Existe en `settings list global`; el usuario acepta el impacto; hay rollback probado. |
| `global wifi_wakeup_enabled` | Evitar activacion automatica de Wi-Fi puede dar un comportamiento mas predecible. | Cambia una preferencia de usuario, no la calidad del enlace. | Solo como preferencia explicita, nunca activada por un perfil automatico. |
| `global mobile_data_always_on` | Ajustar el coste de mantener datos moviles durante Wi-Fi. | Afecta handover, bateria y expectativas de conectividad. | Medir handover Wi-Fi/datos y restaurar el valor previo. |
| `global adaptive_connectivity_enabled` | Delegar decisiones de radio al framework cuando el OEM la soporta. | Semantica y soporte cambian por OEM. | Clave presente, comportamiento observable y prueba por modelo/version. |
| `global captive_portal_mode` | Configurar la comprobacion de portal cautivo segun una politica explicita. | Puede ocultar redes que requieren inicio de sesion. | Solo politica de usuario; pruebas en red cautiva y abierta. |

No incluir por defecto: `wifi_power_save`, `wifi.supplicant_scan_interval`, `wifi_assistant`, `network_avoid_bad_wifi`, `network_prediction_enabled`, `network_recommendations_enabled`, `network_scoring_ui_enabled`, `wifi_dynamic_bw_switch`, `wifi_safe_mode` y `wifi_coverage_extend_feature_enabled`. No existe aun una semantica estable, una puerta de soporte ni un rollback de Kitsunping para esos nombres.

### C. TCP, DNS y kernel: investigar por la interfaz correcta

Antes de cambiar cualquier buffer o parametro de transporte, identificar la superficie que realmente usa el dispositivo:

```bash
adb shell 'cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null'
adb shell 'cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null'
adb shell 'cat /proc/sys/net/ipv4/tcp_rmem 2>/dev/null; cat /proc/sys/net/ipv4/tcp_wmem 2>/dev/null'
adb shell 'settings get global tcp.buffersize.wifi 2>/dev/null'
adb shell 'getprop | grep -E "\[(net\.tcp\.buffersize|persist\.vendor\.(data|wifi)|ril\.)"'
```

Una mejora de TCP solo es candidata si se cumple todo lo siguiente:

1. El kernel expone el parametro y el valor se puede leer antes y despues.
2. La interfaz de escritura es la que consume el sistema objetivo, no un nombre copiado de otro ROM.
3. Kitsunping respalda el valor exacto, limita el cambio a dispositivos compatibles y lo restaura en salida de perfil, desactivacion y desinstalacion.
4. La prueba mejora una metrica definida frente a linea base, sin aumentar perdida, reconexiones o consumo fuera de un limite declarado.

## Candidatos descartados o bloqueados

| Grupo | Decision | Motivo |
| --- | --- | --- |
| `settings put global persist.*`, `vendor.*`, `ril.*`, `net.*` | Descartado | Mezcla bases de datos Settings con propiedades; no demuestra aplicacion por framework/vendor. |
| `set-default-network-active`, `set-multipath-preference`, `set-ipreach-disconnect` | Descartado | Parecen nombres de API/comando, no claves estables de Settings. |
| `cmd netpolicy set restrict-background true` | No es tuning de enlace | Modifica la politica global de datos en segundo plano y puede romper aplicaciones. |
| `force-softap-band`, `wfc_ims_mode` | Fuera de alcance | Son comportamiento de hotspot/telefonia, no optimizacion general de red. |
| `persist.data_netmgrd_mtu`, `net.tethering.noprovisioning` | Bloqueado | Son propiedad de proveedor o bypass de aprovisionamiento; no usar desde un perfil. |
| Country code, region, canales 12-14 y 6 GHz | Prohibido para perfiles | Riesgo regulatorio y de compatibilidad; solo diagnostico pasivo de capacidades. |
| Buffers UMTS/EVDO/GPRS/HSPA heredados | Diferido | No aportan valor sin un dispositivo y framework que los consuma. |

## Protocolo de validacion por OEM y version

1. Registrar modelo, fabricante, Android/API, kernel, ROM, chipset Wi-Fi y modem. No guardar IMEI, IMSI, BSSID ni credenciales.
2. Capturar linea base: RSSI, enlace, red activa, RTT, perdida, jitter, caudal, consumo y eventos de roaming durante una ventana fija.
3. Descubrir la clave o comando sin escribirlo: `settings get <namespace> <key>`, `settings list <namespace>`, `cmd wifi help` y lectura de `getprop` o `/proc` cuando corresponda.
4. Respaldar solo el valor concreto que se va a cambiar, incluyendo el caso de clave ausente.
5. Aplicar un solo cambio con un identificador de ejecucion, volver a leerlo y registrar la salida.
6. Repetir la misma carga de red; comparar contra linea base y registrar tambien fallos, handover y consumo.
7. Restaurar el valor previo, volver a leerlo y repetir una comprobacion corta de conectividad.
8. Promoverlo solo si hay mejora reproducible y rollback probado en la misma familia OEM/API. En otro modelo comienza nuevamente como experimental.

## Ingenieria inversa orientada a evidencia

La investigacion es util para encontrar propietarios, condiciones y mecanismos de aplicacion, no para recolectar listas de propiedades. Trabajar sobre una copia obtenida legalmente del dispositivo propio o sobre fuentes publicas del OEM/AOSP.

### Fuentes prioritarias

1. Fuentes publicas del kernel, device tree, vendor configuration y framework del modelo/OEM.
2. Archivos init de texto: `/system/etc/init/*.rc`, `/vendor/etc/init/*.rc` y `/odm/etc/init/*.rc`.
3. Contextos de propiedad: `property_contexts`, `vendor_property_contexts` y archivos SELinux asociados.
4. Ayuda y servicios expuestos: `cmd wifi help`, `cmd connectivity help`, `cmd netpolicy help`, `dumpsys wifi`, `dumpsys connectivity`.
5. Bibliotecas y servicios de radio solo para identificar cadenas, permisos, servicios y callbacks. No inferir que una cadena es escribible ni cambiar radio/operador por ese hallazgo.

Excluir rutas irrelevantes como binarios de Termux, archivos de reconocimiento de texto, nodos efimeros de `/dev/__properties__` y espejos internos de Magisk. No describen una interfaz de configuracion estable.

### Flujo de investigacion

1. Buscar en `.rc` acciones `on property:` y `setprop`; registrar propiedad, valor, servicio receptor y condicion de arranque.
2. Consultar los contextos SELinux para clasificar la propiedad como framework, vendor, radio o servicio de control.
3. En las fuentes publicas, seguir el consumidor: quien lee la propiedad, en que fase y con que validacion.
4. En el dispositivo, comprobar presencia con `getprop`, permiso y efecto observable sin modificarlo.
5. Crear una ficha de candidato con: propietario, lector, escritor permitido, tipo, rango, API/OEM, reinicio requerido, riesgo, rollback, metrica y evidencia.
6. Solo entonces crear una prueba aislada. Las propiedades `ro.*`, `persist.vendor.*`, `persist.radio.*`, `ctl.*` y relacionadas con IMS/regulacion requieren una revision especifica y no entran a perfiles automaticos.

## Criterio de incorporacion en Kitsunping

Para implementar un candidato se requiere una declaracion versionada que especifique: perfil, selector OEM/API, preflight, valor previo, accion, relectura, rollback, momento de restauracion, metrica y prueba de host. Las pruebas de dispositivo deben cubrir aplicacion, retorno a perfil normal, desactivacion del modulo y desinstalacion.

Las propiedades externas permanecen fuera de snapshots y configuracion persistente de Kitsunping. El modulo solo guarda su configuracion canonica `persist.kitsunping.*`; Android, vendor y carrier conservan la propiedad de sus propias superficies.