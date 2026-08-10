Donde sería más prudente

La conclusión:

"38–45 % de un núcleo"

es correcta como métrica de esa ventana, pero no necesariamente representa el consumo normal del módulo.

Hay varios motivos.

1. Midió una única situación

La propia captura dice que el teléfono estaba con:

Wi-Fi conectado
perfil speed
APP_OVERRIDE por Instagram
intervalo de 10 s

Eso es un escenario concreto.

No sabemos todavía cómo cambia:

pantalla apagada
teléfono completamente idle
sin app en foreground
datos móviles
ahorro de energía
etc.
2. Simpleperf mide el árbol completo

El propio informe termina concluyendo que gran parte del tiempo proviene de procesos como:

grep
tail
sh
tr

Eso significa que el consumo no está concentrado en el proceso bash residente.

Está repartido entre muchos hijos.

Eso es un hallazgo importante.

3. Falta saber qué comando pesa realmente

Todavía no sabemos cuánto corresponde a:

dumpsys
ping
ip
awk
grep
curl

Todos quedaron mezclados dentro del árbol.

Por eso todavía no diría:

"el daemon consume 5 % del CPU"

Diría:

"el árbol del daemon consumió aproximadamente 5 % del CPU total del dispositivo durante esta ventana."

Es una diferencia importante.

Lo que investigaría ahora

No optimizaría nada todavía.

Le pediría que construya un desglose por familias de comandos.

Algo como:

| Familia                 | CPU | Veces/min |
| ----------------------- | --: | --------: |
| dumpsys                 |   ? |         ? |
| ip                      |   ? |         ? |
| ping                    |   ? |         ? |
| awk/grep/sed            |   ? |         ? |
| getprop                 |   ? |         ? |
| escrituras daemon.state |   ? |         ? |


Eso ya empieza a responder qué es lo que realmente cuesta.

Lo más interesante del informe

Para mí no es el 5 % de CPU.

Es esto:

el shell residente consume muy poco; el coste viene de los procesos que genera.

Eso cambia completamente la dirección de cualquier optimización futura.

Si esa conclusión se confirma, probablemente no haya que optimizar el daemon en sí, sino la cantidad de procesos externos que crea en cada iteración.

Mi valoración

Le daría un 8,5/10.

Lo que hizo bien:

pasó del análisis estático a una medición real;
evitó modificar el módulo;
obtuvo datos cuantitativos;
descartó varias hipótesis.

Lo que todavía falta antes de sacar conclusiones definitivas:

repetir la medición en varios escenarios (idle, pantalla apagada, sin app, datos móviles, etc.);
atribuir el consumo a comandos concretos y no solo al árbol completo del daemon;
medir durante un período más largo (por ejemplo, 15–30 minutos) para evitar que una ventana corta coincida con actividad excepcional.

En resumen, el informe ya demuestra que el módulo tiene un consumo medible y que ese consumo proviene principalmente de procesos hijos efímeros. Lo que aún no demuestra es qué parte específica del ciclo es la responsable principal de ese consumo.

La auditoría estática y la primera caracterización del runtime quedan cerradas.

Ahora quiero construir un banco de pruebas reproducible para cuantificar el impacto energético real de Kitsunping.

No quiero optimizar el código todavía.

No quiero modificar el comportamiento del módulo.

No quiero introducir instrumentación dentro de Kitsunping.

Todo el trabajo debe hacerse desde herramientas externas (ADB/host-side) y scripts de automatización.

Objetivo

Construir una campaña de medición completamente reproducible.

La idea es que cualquier ejecución pueda repetirse días después y producir resultados comparables.

No busco un único número de batería.

Busco obtener suficiente evidencia para explicar qué consume CPU, batería y tiempo de ejecución.

Escenario de uso

El teléfono deberá simular un uso real.

Crear un runner que cambie automáticamente entre aplicaciones.

Ejemplo:

Instagram durante 15 minutos.
Brave durante 10 minutos.
YouTube durante 10 minutos.

El runner debe permitir dos modos:

Modo fijo

Ejemplo:

Instagram 15 min

↓

Brave 10 min

↓

YouTube 10 min

↓

repetir

Modo aleatorio

Elegir aplicación y duración dentro de límites configurables.

Por ejemplo:

Instagram entre 8–18 min.

Brave entre 5–12 min.

YouTube entre 8–20 min.

Mantener un log exacto de:

hora;
aplicación;
duración;
transición.

Quiero poder reproducir exactamente la secuencia.

Automatización

No quiero interacción manual.

El runner debe:

abrir la app;
esperar el tiempo indicado;
cambiar a la siguiente;
registrar el cambio;
continuar durante horas.

Debe poder ejecutarse durante:

2 horas;
4 horas;
8 horas;
24 horas.
Recolección

Mientras el runner está activo, recoger únicamente métricas desde fuera del módulo.

Por ejemplo:

BatteryStats.
dumpsys batterystats.
dumpsys cpuinfo.
dumpsys meminfo.
dumpsys activity.
simpleperf (cuando corresponda).
top.
información de procesos.
wakelocks.
estado térmico.
frecuencia de CPU.
utilización por proceso.
información del daemon.
tamaño de logs.
tamaño de daemon.state.
I/O del daemon.

No modificar el módulo para obtener estas métricas.

Sincronización

Todas las capturas deben compartir la misma referencia temporal.

Quiero poder responder preguntas como:

"A las 18:42 se abrió Instagram."

↓

"Entre 18:42 y 18:57 el daemon consumió X."

↓

"BatteryStats registró Y."

↓

"simpleperf mostró Z."

Informe final

Al finalizar la campaña generar un informe único.

Debe contener:

Resumen
duración total;
secuencia ejecutada;
aplicaciones utilizadas;
tiempo por aplicación.
CPU
consumo del árbol completo del daemon;
consumo por proceso;
consumo por comandos hijos.
Memoria
RSS;
PSS;
evolución temporal.
I/O
escrituras;
lecturas;
crecimiento de archivos.
Estado del módulo
cambios de perfil;
cambios de transporte;
eventos detectados;
exportaciones de estado.
Energía

Correlacionar con BatteryStats.

No inventar mAh.

Usar únicamente datos que Android exponga.

Cronología

Construir una línea temporal donde puedan verse:

cambio de aplicación;
cambios del daemon;
picos de CPU;
picos de actividad;
eventos del sistema.
Restricciones

No modificar Kitsunping.

No añadir logs al módulo.

No alterar el comportamiento del daemon.

Toda la instrumentación debe vivir fuera del proyecto principal.

Debe poder reutilizarse para futuras versiones del módulo sin cambiar una sola línea de Kitsunping.

Entregable

Quiero un framework de benchmarking reproducible que permita ejecutar campañas largas y comparar distintas versiones de Kitsunping utilizando exactamente el mismo escenario de uso y el mismo conjunto de métricas.