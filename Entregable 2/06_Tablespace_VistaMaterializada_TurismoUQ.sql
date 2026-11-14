-- PARTE 1: ejecutar como SYSTEM
-- PARTE 2: ejecutar con el usuario del proyecto

-- =============================== PARTE 1 =====================================

------------------------------- TABLESPACE HISTORICO --------------------------
-- Tablespace propio para el histórico de reservas

-- Comando para cambiar de contenedor 
ALTER SESSION SET CONTAINER = XEPDB1;

-- Privilegios para la vista materializada
GRANT CREATE MATERIALIZED VIEW, CREATE JOB TO turismouq;

BEGIN
    EXECUTE IMMEDIATE 'CREATE SMALLFILE TABLESPACE ts_historico_turismo
        DATAFILE ''ts_historico_turismo01.dbf'' SIZE 20M
        AUTOEXTEND ON NEXT 5M MAXSIZE 200M';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1543 THEN RAISE; END IF;
END;
/

-- Dar permiso al usuario para usar espacio en el tablespace
ALTER USER turismouq QUOTA UNLIMITED ON ts_historico_turismo;

-- Comprobar que el datafile existe
SELECT tablespace_name, file_name, ROUND(bytes / 1024 / 1024) AS mb, autoextensible
FROM dba_data_files
WHERE tablespace_name = 'TS_HISTORICO_TURISMO';

-- JUSTIFICACIÓN: Las reservas finalizadas casi no se consultan,
-- mientras que las activas se usan todo el tiempo, entonces al mandarlas 
-- a un tablespace propio, evitamos que el histórico le quite espacio a los datos
-- del día a día, podemos hacer respaldos aparte sin saturar, y logramos que las
-- tablas activas sean mucho más ligeras y rápidas de consultar.

-- =============================== PARTE 2 ======================================

SET SERVEROUTPUT ON;

------------------------------ RESERVA_HISTORICO -------------------------------
-- Copia en el tablespace histórico de las reservas cerradas antes de 2026
-- (en una base nueva no hay nada que borrar)

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE reserva_historico';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

CREATE TABLE reserva_historico TABLESPACE ts_historico_turismo AS
SELECT *
  FROM reserva
 WHERE estado IN ('COMPLETADA', 'CANCELADA')
   AND fecha_checkout < DATE '2026-01-01';

ALTER TABLE reserva_historico ADD CONSTRAINT pk_reserva_historico PRIMARY KEY (id_reserva);

COMMENT ON TABLE reserva_historico IS 'Histórico de reservas completadas o canceladas antes de 2026.';


------------------------------ VISTA MATERIALIZADA -----------------------------
-- Ocupación mensual de cada alojamiento:
-- noches vendidas, noches disponibles (habitaciones x días del mes) y porcentaje

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -12003 THEN RAISE; END IF;
END;
/

CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE
START WITH SYSDATE
NEXT TRUNC(SYSDATE) + 1 + 2/24
AS
SELECT m.nombre AS municipio,
       a.id_alojamiento,
       a.nombre AS alojamiento,
       TO_CHAR(c.mes, 'YYYY-MM') AS mes,
       h.habitaciones,
       NVL(o.noches_vendidas, 0) AS noches_vendidas,
       h.habitaciones * EXTRACT(DAY FROM LAST_DAY(c.mes)) AS noches_disponibles,
       ROUND(100 * NVL(o.noches_vendidas, 0)
                 / (h.habitaciones * EXTRACT(DAY FROM LAST_DAY(c.mes))), 2) AS pct_ocupacion,
       NVL(o.ingresos_estadia, 0) AS ingresos_estadia
  FROM (SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS mes
          FROM dual
        CONNECT BY LEVEL <= 36) c
  CROSS JOIN alojamiento a
  JOIN municipio m ON m.id_municipio = a.id_municipio
  JOIN (SELECT id_alojamiento, COUNT(*) AS habitaciones
          FROM habitacion
         GROUP BY id_alojamiento) h ON h.id_alojamiento = a.id_alojamiento
  LEFT JOIN (SELECT v.id_alojamiento,
                    TRUNC(v.fecha_noche, 'MM') AS mes,
                    COUNT(*) AS noches_vendidas,
                    SUM(v.valor_noche) AS ingresos_estadia
               FROM v_noche_ocupada v
              GROUP BY v.id_alojamiento, TRUNC(v.fecha_noche, 'MM')) o
         ON o.id_alojamiento = a.id_alojamiento
        AND o.mes = c.mes;

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS 'Ocupación mensual por alojamiento. Se refresca todos los días a las 2:00 a.m.';

-- JUSTIFICACIÓN del refresco:
-- Se usa COMPLETE porque el CONNECT BY de la vista v_noche_ocupada no soporta FAST.
-- Se programó a las 2:00 a.m. para actualizar en el horario donde casi nadie reserva.
-- No se puso ON COMMIT para no relentizar las reservas activas, ni ON DEMAND para
-- evitar tener que realizar un refresco manual, así la gerencia consulta el consolidado del
-- día anterior cuántas veces quiera


-- Cómo quedó configurada
SELECT mview_name, refresh_mode, refresh_method, staleness, last_refresh_date
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

-- Los 10 alojamientos con mayor ocupación en diciembre de 2025
SELECT municipio, alojamiento, habitaciones, noches_vendidas, noches_disponibles, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE mes = '2025-12'
 ORDER BY pct_ocupacion DESC
 FETCH FIRST 10 ROWS ONLY;

-- Meses sin reservas: aparecen con 0 %
SELECT municipio, alojamiento, mes, noches_vendidas, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE noches_vendidas = 0
 ORDER BY mes, alojamiento
 FETCH FIRST 5 ROWS ONLY;

-- Ocupación por mes, revisando la estacionalidad
SELECT mes, ROUND(100 * SUM(noches_vendidas) / SUM(noches_disponibles), 2) AS pct_ocupacion
  FROM mv_ocupacion_mensual
 GROUP BY mes
 ORDER BY mes;
