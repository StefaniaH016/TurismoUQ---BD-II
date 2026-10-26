SET SERVEROUTPUT ON;

-- ========================== PRUEBAS - ENTREGA 2 ===============================

VARIABLE v_hab NUMBER
VARIABLE v_aloj NUMBER
VARIABLE v_res NUMBER
VARIABLE v_mes VARCHAR2(7)

PROMPT =========================================================================
PROMPT                  PRUEBA 1: Función fn_valor_estadia
PROMPT =========================================================================

-- Habitación 1 del 28/11/2025 al 03/12/2025 (Cruza temporada media y alta)
SELECT pkg_turismo_uq.fn_valor_estadia(1, DATE '2025-11-28', DATE '2025-12-03') AS valor_estadia
  FROM dual;

-- Validación de excepción en la función (Fechas invertidas)
BEGIN
    DBMS_OUTPUT.PUT_LINE(pkg_turismo_uq.fn_valor_estadia(1, DATE '2025-12-10', DATE '2025-12-05'));
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Excepción fn_valor_estadia (Fechas invertidas) -> ' || SQLERRM);
END;
/

PROMPT =========================================================================
PROMPT             PRUEBA 2: Procedimiento sp_crear_reserva y exepciones
PROMPT =========================================================================

-- 2a. Creación de una reserva exitosa
DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
    v_id_hab NUMBER;
    v_id_aloj NUMBER;
    v_id_res NUMBER;
BEGIN
    SELECT h.id_habitacion, h.id_alojamiento
      INTO v_id_hab, v_id_aloj
      FROM habitacion h
     WHERE h.capacidad_max >= 2
       AND NOT EXISTS (SELECT 1 FROM reserva_habitacion rh
                         JOIN reserva r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion AND r.estado <> 'CANCELADA'
                          AND v_in < rh.fecha_out AND v_out > rh.fecha_in)
     ORDER BY h.id_habitacion
     FETCH FIRST 1 ROWS ONLY;

    pkg_turismo_uq.sp_crear_reserva(1, v_id_aloj, v_id_hab, v_in, v_out, 2, v_id_res);
    :v_hab := v_id_hab; :v_aloj := v_id_aloj; :v_res := v_id_res;
    DBMS_OUTPUT.PUT_LINE('Reserva creada: ' || v_id_res || ' - valor estadía: '
        || pkg_turismo_uq.fn_valor_estadia(v_id_hab, v_in, v_out));
END;
/
ROLLBACK;

-- 2b. Intento con Checkout anterior a Checkin 
BEGIN
    pkg_turismo_uq.sp_crear_reserva(1, :v_aloj, :v_hab,
        ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8, ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5, 2, :v_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Excepción sp_crear_reserva (Fechas erróneas) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2c. Intento con más huéspedes que la capacidad 
DECLARE
    v_cap NUMBER;
BEGIN
    SELECT capacidad_max INTO v_cap FROM habitacion WHERE id_habitacion = :v_hab;
    pkg_turismo_uq.sp_crear_reserva(1, :v_aloj, :v_hab,
        ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5, ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8, v_cap + 1, :v_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Excepción sp_crear_reserva (Sobrecupo) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2d. Habitación ya reservada en esas fechas 
DECLARE
    v_id_hab NUMBER; v_id_aloj NUMBER; v_in DATE; v_out DATE;
BEGIN
    SELECT rh.id_habitacion, rh.id_alojamiento, rh.fecha_in, rh.fecha_out
      INTO v_id_hab, v_id_aloj, v_in, v_out
      FROM reserva_habitacion rh JOIN reserva r ON r.id_reserva = rh.id_reserva
     WHERE r.estado = 'CONFIRMADA' AND rh.fecha_in > TRUNC(SYSDATE)
     ORDER BY rh.fecha_in FETCH FIRST 1 ROWS ONLY;

    pkg_turismo_uq.sp_crear_reserva(1, v_id_aloj, v_id_hab, v_in, v_out, 1, :v_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Excepción sp_crear_reserva (No disponible) -> ' || SQLERRM);
        ROLLBACK;
END;
/

PROMPT =========================================================================
PROMPT     PRUEBA 3: Disparador trg_impedir_solape_reserva (DISPARADOR FILA)
PROMPT =========================================================================
-- Intento de inserción directa que viola disponibilidad 
DECLARE
    v_id_hab NUMBER; v_id_aloj NUMBER; v_in DATE; v_out DATE; v_nueva NUMBER;
BEGIN
    SELECT rh.id_habitacion, rh.id_alojamiento, rh.fecha_in, rh.fecha_out
      INTO v_id_hab, v_id_aloj, v_in, v_out
      FROM reserva_habitacion rh JOIN reserva r ON r.id_reserva = rh.id_reserva
     WHERE r.estado = 'CONFIRMADA' AND rh.fecha_in >= TRUNC(SYSDATE)
     ORDER BY rh.fecha_in FETCH FIRST 1 ROWS ONLY;

    INSERT INTO reserva (id_cliente, id_alojamiento, fecha_creacion, fecha_checkin, fecha_checkout, estado)
    VALUES (2, v_id_aloj, TRUNC(SYSDATE), v_in, v_out, 'CONFIRMADA') RETURNING id_reserva INTO v_nueva;

    INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_in, fecha_out, num_huespedes)
    VALUES (v_nueva, v_id_aloj, v_id_hab, v_in, v_out, 1);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba de solape -> ' || SQLERRM);
        ROLLBACK;
END;
/

PROMPT =========================================================================
PROMPT                  PRUEBA 4: Cursor sp_liquidacion_mensual
PROMPT =========================================================================
EXEC pkg_turismo_uq.sp_liquidacion_mensual(2025, 12);

SELECT a.nombre AS alojamiento, l.num_reservas, l.noches_vendidas, l.valor_total
  FROM liquidacion_mensual l
  JOIN alojamiento a ON a.id_alojamiento = l.id_alojamiento
 WHERE l.anio = 2025 AND l.mes = 12
 ORDER BY l.valor_total DESC FETCH FIRST 5 ROWS ONLY;
 

PROMPT =========================================================================
PROMPT         PRUEBA 5: Auditoría en TARIFA (DISPARADOR SENTENCIA)
PROMPT =========================================================================
UPDATE tarifa
   SET valor_noche = valor_noche + 10000
 WHERE id_habitacion = 1
   AND id_temporada IN (SELECT id_temporada FROM temporada WHERE nombre LIKE 'Alta%');

-- Verificación de la bitácora de auditoría
SELECT id_bitacora, fecha_cambio, usuario, operacion, id_tarifa, valor_anterior, valor_nuevo, detalle
  FROM bitacora_tarifa
 ORDER BY id_bitacora DESC;

ROLLBACK;


PROMPT =========================================================================
PROMPT          PRUEBA 6: Refresco y vista Materializada
PROMPT =========================================================================
-- Estado antes del refresco (fecha del último refresco)
SELECT mview_name, refresh_mode, refresh_method, staleness, last_refresh_date
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

-- Refresco bajo demanda de la vista materializada
EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');

-- Estado después del refresco (FRESH y fecha actualizada)
SELECT mview_name, refresh_mode, refresh_method, staleness, last_refresh_date
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';
 
SELECT (SELECT COUNT(*) FROM reserva) AS total_reservas,
       (SELECT COUNT(*) FROM bitacora_tarifa) AS registros_bitacora
FROM dual;
 
PROMPT =========================================================================
PROMPT          PRUEBA 7: Tablespace Histórico y Tabla de Reserva Histórico
PROMPT =========================================================================
-- verificación del tablespace asignado a la tabla de histórico
SELECT table_name, tablespace_name
  FROM user_tables
 WHERE table_name IN ('RESERVA', 'RESERVA_HISTORICO');

-- Reservas del histórico por año y estado
SELECT EXTRACT(YEAR FROM fecha_checkout) AS anio, estado, COUNT(*) AS reservas
  FROM reserva_historico
 GROUP BY EXTRACT(YEAR FROM fecha_checkout), estado
 ORDER BY anio, estado;

-- Espacio usado en el tablespace
SELECT tablespace_name, ROUND(bytes / 1024) AS kb_usados, max_bytes
  FROM user_ts_quotas
 WHERE tablespace_name = 'TS_HISTORICO_TURISMO';
 

PROMPT =========================================================================
PROMPT        VERIFICACIÓN FINAL: Estado limpio de la base de datos
PROMPT =========================================================================
SELECT (SELECT COUNT(*) FROM reserva) AS total_reservas,
       (SELECT COUNT(*) FROM bitacora_tarifa) AS registros_bitacora
  FROM dual;
  
  