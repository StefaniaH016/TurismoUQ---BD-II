-------------------------------------------------------------------------------
-- PROYECTO INTEGRADOR TurismoUQ - BASES DE DATOS II 2026-2
-- ENTREGA 1: 7 CONSULTAS DE ANÁLISIS
--
-- Criterio de "ingreso": suma del valor de las noches ocupadas.
-- Se obtiene de la vista v_noche_ocupada, que tiene una fila por cada noche
-- de cada habitación reservada (solo reservas CONFIRMADA o COMPLETADA) y
-- trae la tarifa que aplicaba ese día.
-------------------------------------------------------------------------------

--------------- PEQUEÑA VERIFICACIÓN DE DATOS PARA CONSULTAS 1 - 6 ---------------
SELECT SUM(valor_noche) AS total_ingresos, COUNT(*) AS total_noches
FROM v_noche_ocupada;

SELECT m.nombre,
       COUNT(DISTINCT a.id_alojamiento) AS alojamientos,
       COUNT(h.id_habitacion) AS habitaciones
FROM municipio m
LEFT JOIN alojamiento a ON a.id_municipio = m.id_municipio
LEFT JOIN habitacion h ON h.id_alojamiento = a.id_alojamiento
GROUP BY m.nombre
ORDER BY m.nombre;

--------------------------- CONSULTA 1 ----------------------------------------
-- Ocupación por municipio y mes (PIVOT).
-- Cuenta las noches ocupadas de cada municipio y muestra cada mes de 2024, 2025 y
-- 2026 como una columna.

SELECT *
FROM (
    SELECT m.nombre AS municipio,
           TO_CHAR(vno.fecha_noche, 'YYYY-MM') AS mes
    FROM v_noche_ocupada vno
    JOIN alojamiento a ON vno.id_alojamiento = a.id_alojamiento
    JOIN municipio m ON a.id_municipio = m.id_municipio
)
PIVOT (
    COUNT(*) FOR mes IN (
        -- Meses del 2024
        '2024-01' AS "2024-01", '2024-02' AS "2024-02", '2024-03' AS "2024-03",
        '2024-04' AS "2024-04", '2024-05' AS "2024-05", '2024-06' AS "2024-06",
        '2024-07' AS "2024-07", '2024-08' AS "2024-08", '2024-09' AS "2024-09",
        '2024-10' AS "2024-10", '2024-11' AS "2024-11", '2024-12' AS "2024-12",
        -- Meses del 2025
        '2025-01' AS "2025-01", '2025-02' AS "2025-02", '2025-03' AS "2025-03",
        '2025-04' AS "2025-04", '2025-05' AS "2025-05", '2025-06' AS "2025-06",
        '2025-07' AS "2025-07", '2025-08' AS "2025-08", '2025-09' AS "2025-09",
        '2025-10' AS "2025-10", '2025-11' AS "2025-11", '2025-12' AS "2025-12",
        -- Meses del 2026
        '2026-01' AS "2026-01", '2026-02' AS "2026-02", '2026-03' AS "2026-03",
        '2026-04' AS "2026-04", '2026-05' AS "2026-05", '2026-06' AS "2026-06",
        '2026-07' AS "2026-07", '2026-08' AS "2026-08", '2026-09' AS "2026-09",
        '2026-10' AS "2026-10", '2026-11' AS "2026-11", '2026-12' AS "2026-12"
    )
)
ORDER BY municipio;

--------------------------- CONSULTA 2 ----------------------------------------
-- Ingresos por municipio, tipo de alojamiento y temporada (ROLLUP + GROUPING).
-- Muestra los ingresos con subtotales por municipio, por tipo y un total
-- general. GROUPING distingue los subtotales de un NULL real y permite
-- rotular cada fila.

SELECT
    CASE
        WHEN GROUPING(m.nombre) = 1 THEN '--- TOTAL GENERAL ---'
        ELSE m.nombre
    END AS municipio,

    CASE
        WHEN GROUPING(m.nombre) = 1 THEN '---'
        WHEN GROUPING(ta.nombre) = 1 THEN '--- SUBTOTAL MUNICIPIO ---'
        ELSE ta.nombre
    END AS tipo_alojamiento,

    CASE
        WHEN GROUPING(ta.nombre) = 1 THEN '---'
        WHEN GROUPING(vno.nivel) = 1 THEN '--- SUBTOTAL TIPO ALOJAMIENTO ---'
        ELSE vno.nivel
    END AS temporada,

    SUM(vno.valor_noche) AS total_ingresos_noches
FROM v_noche_ocupada vno
JOIN alojamiento a ON vno.id_alojamiento = a.id_alojamiento
JOIN municipio m ON a.id_municipio = m.id_municipio
JOIN tipo_alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
GROUP BY ROLLUP(m.nombre, ta.nombre, vno.nivel)
ORDER BY m.nombre NULLS LAST, ta.nombre NULLS LAST, vno.nivel NULLS LAST;

--------------------------- CONSULTA 3 ----------------------------------------
-- Top 3 alojamientos con mayor ingreso dentro de cada municipio
-- (RANK con PARTITION BY).
-- El ranking se reinicia en cada municipio; si hay empate, comparten posición.

SELECT municipio, alojamiento, ingresos_totales, ranking_municipio
FROM (
    SELECT
        m.nombre AS municipio,
        a.nombre AS alojamiento,
        SUM(vno.valor_noche) AS ingresos_totales,
        RANK() OVER (
            PARTITION BY m.id_municipio
            ORDER BY SUM(vno.valor_noche) DESC
        ) AS ranking_municipio
    FROM v_noche_ocupada vno
    JOIN alojamiento a ON vno.id_alojamiento = a.id_alojamiento
    JOIN municipio m ON a.id_municipio = m.id_municipio
    GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
)
WHERE ranking_municipio <= 3
ORDER BY municipio, ranking_municipio;

--------------------------- CONSULTA 4 ----------------------------------------
-- Variación de ingresos mes contra mes (LAG).
-- Compara el total de cada mes con el del mes anterior, en pesos y en
-- porcentaje. El primer mes no tiene mes anterior, por eso sale vacío.
-- De octubre a diciembre de 2026 solo están las reservas futuras, por eso bajan.

SELECT mes,
       total_mes,
       LAG(total_mes) OVER (ORDER BY mes) AS mes_anterior,
       total_mes - LAG(total_mes) OVER (ORDER BY mes) AS variacion,
       ROUND(100 * (total_mes - LAG(total_mes) OVER (ORDER BY mes))
                 / NULLIF(LAG(total_mes) OVER (ORDER BY mes), 0), 2) AS variacion_pct
FROM (
    SELECT TO_CHAR(v.fecha_noche, 'YYYY-MM') AS mes,
           SUM(v.valor_noche) AS total_mes
    FROM v_noche_ocupada v
    GROUP BY TO_CHAR(v.fecha_noche, 'YYYY-MM')
)
ORDER BY mes;

--------------------------- CONSULTA 5 ----------------------------------------
-- Ingresos por municipio y tipo de alojamiento en un rango de fechas
-- (consulta PARAMETRIZADA con variables de enlace).
-- Declaración explícita de variables mediante VARIABLE e inicialización con EXEC.
-- Se ejecuta con F5 y para otro rango se cambian las fechas del EXEC.

VARIABLE fecha_inicio VARCHAR2(10)
VARIABLE fecha_fin VARCHAR2(10)

EXEC :fecha_inicio := '2025-12-15';
EXEC :fecha_fin := '2026-01-15';

SELECT m.nombre AS municipio,
       ta.nombre AS tipo_alojamiento,
       COUNT(DISTINCT v.id_reserva) AS reservas,
       COUNT(*) AS noches_ocupadas,
       SUM(v.valor_noche) AS ingresos
FROM v_noche_ocupada v
JOIN alojamiento a ON a.id_alojamiento = v.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
WHERE v.fecha_noche BETWEEN TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
                         AND TO_DATE(:fecha_fin, 'YYYY-MM-DD')
GROUP BY m.nombre, ta.nombre
ORDER BY ingresos DESC;

--------------------------- CONSULTA 6 ----------------------------------------
-- Movimiento de reservas por mes (UNPIVOT).
-- La tabla RESERVA ya tiene sus fechas en columnas (creación, check-in,
-- check-out y cancelación). El UNPIVOT las pasa a filas para contar cuántos
-- eventos de cada tipo hay por mes. Las cancelaciones nulas no se cuentan.

SELECT TO_CHAR(fecha, 'YYYY-MM') AS mes,
       evento,
       COUNT(*) AS cantidad
FROM reserva
UNPIVOT (
    fecha FOR evento IN (
        fecha_creacion AS 'CREACION',
        fecha_checkin AS 'LLEGADA',
        fecha_checkout AS 'SALIDA',
        fecha_cancelacion AS 'CANCELACION'
    )
)
GROUP BY TO_CHAR(fecha, 'YYYY-MM'), evento
ORDER BY mes, evento;

--------------------------- CONSULTA 7 ----------------------------------------
-- Consulta libre: ¿en qué municipios se cancelan más reservas?
-- Calcula el porcentaje de reservas canceladas por municipio, de mayor a menor.

SELECT m.nombre AS municipio,
       COUNT(*) AS total_reservas,
       SUM(CASE WHEN r.estado = 'CANCELADA' THEN 1 ELSE 0 END) AS canceladas,
       ROUND(100 * SUM(CASE WHEN r.estado = 'CANCELADA' THEN 1 ELSE 0 END)
                 / COUNT(*), 2) AS pct_cancelacion
FROM reserva r
JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
GROUP BY m.nombre
ORDER BY pct_cancelacion DESC;

------------------------------------ FIN --------------------------------------
