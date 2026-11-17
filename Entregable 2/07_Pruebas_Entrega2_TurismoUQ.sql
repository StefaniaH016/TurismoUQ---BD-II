SET SERVEROUTPUT ON;

-- ========================== PRUEBAS - ENTREGA 2 ===============================

VARIABLE v_hab NUMBER
VARIABLE v_aloj NUMBER
VARIABLE v_res NUMBER
VARIABLE v_mes VARCHAR2(7)
VARIABLE v_fhab NUMBER
VARIABLE v_faloj NUMBER
VARIABLE v_fcap NUMBER
VARIABLE v_fotro NUMBER

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

-- 1c. fn_valor_estadia sin tarifa (fechas fuera de todas las temporadas) -> ORA-20021
BEGIN
    DBMS_OUTPUT.PUT_LINE('1c valor -> ' || pkg_turismo_uq.fn_valor_estadia(1, DATE '2040-01-10', DATE '2040-01-12'));
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('1c Excepción fn_valor_estadia (sin tarifa) -> ' || SQLERRM);
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

-- Datos base para 2e a 2j y 3d: habitación libre del 10 al 12 de enero de 2030 y otro alojamiento
BEGIN
    SELECT h.id_habitacion, h.id_alojamiento, h.capacidad_max
      INTO :v_fhab, :v_faloj, :v_fcap
      FROM habitacion h
     WHERE NOT EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN reserva r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion
                          AND r.estado <> 'CANCELADA'
                          AND DATE '2030-01-10' < rh.fecha_out
                          AND DATE '2030-01-12' > rh.fecha_in)
     ORDER BY h.id_habitacion
     FETCH FIRST 1 ROWS ONLY;

    SELECT MIN(id_alojamiento) INTO :v_fotro FROM alojamiento WHERE id_alojamiento <> :v_faloj;
END;
/

-- 2e. Habitación que no pertenece al alojamiento indicado -> ORA-20002
BEGIN
    pkg_turismo_uq.sp_crear_reserva(1, :v_fotro, :v_fhab, DATE '2030-01-10', DATE '2030-01-12', 1, :v_res);
    DBMS_OUTPUT.PUT_LINE('2e NO dio error (revisar)');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('2e Excepción sp_crear_reserva (habitación de otro alojamiento) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2f. Check-in anterior a hoy -> ORA-20005
BEGIN
    pkg_turismo_uq.sp_crear_reserva(1, :v_faloj, :v_fhab, TRUNC(SYSDATE) - 1, TRUNC(SYSDATE) + 1, 1, :v_res);
    DBMS_OUTPUT.PUT_LINE('2f NO dio error (revisar)');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('2f Excepción sp_crear_reserva (check-in pasado) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2g. Cliente inexistente -> ORA-20006
BEGIN
    pkg_turismo_uq.sp_crear_reserva(999999, :v_faloj, :v_fhab, DATE '2030-01-10', DATE '2030-01-12', 1, :v_res);
    DBMS_OUTPUT.PUT_LINE('2g NO dio error (revisar)');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('2g Excepción sp_crear_reserva (cliente inexistente) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2h. Cero huéspedes -> ORA-20007
BEGIN
    pkg_turismo_uq.sp_crear_reserva(1, :v_faloj, :v_fhab, DATE '2030-01-10', DATE '2030-01-12', 0, :v_res);
    DBMS_OUTPUT.PUT_LINE('2h NO dio error (revisar)');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('2h Excepción sp_crear_reserva (sin huéspedes) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2i. Más de 60 noches (64) -> ORA-20008
BEGIN
    pkg_turismo_uq.sp_crear_reserva(1, :v_faloj, :v_fhab, DATE '2030-01-10', DATE '2030-03-15', 1, :v_res);
    DBMS_OUTPUT.PUT_LINE('2i NO dio error (revisar)');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('2i Excepción sp_crear_reserva (más de 60 noches) -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2j. Caso positivo: reserva en fechas libres -> debe crearse
BEGIN
    pkg_turismo_uq.sp_crear_reserva(1, :v_faloj, :v_fhab, DATE '2030-01-10', DATE '2030-01-12', 1, :v_res);
    DBMS_OUTPUT.PUT_LINE('2j OK: reserva ' || :v_res || ' creada, valor ' ||
        pkg_turismo_uq.fn_valor_estadia(:v_fhab, DATE '2030-01-10', DATE '2030-01-12'));
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('2j ERROR inesperado -> ' || SQLERRM);
        ROLLBACK;
END;
/


PROMPT =========================================================================
PROMPT     PRUEBA 3: Disparador trg_impedir_solape_reserva (compound trigger)
PROMPT =========================================================================
-- Intento de inserción directa que viola disponibilidad -> Excepción ORA-20010
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

-- 3b. INSERT ... SELECT que cruza una reserva existente -> Excepción ORA-20010 (sin ORA-04091)
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
    SELECT v_nueva, v_id_aloj, h.id_habitacion, v_in, v_out, 1
      FROM habitacion h
     WHERE h.id_habitacion = v_id_hab;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba INSERT ... SELECT -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 3c. UPDATE que intenta mover una reserva a fechas ya ocupadas -> Excepción ORA-20010
DECLARE
    v_id_rh NUMBER;
    v_in    DATE;
    v_out   DATE;
BEGIN
    SELECT rh1.id_reserva_habitacion, rh2.fecha_in, rh2.fecha_out
      INTO v_id_rh, v_in, v_out
      FROM reserva_habitacion rh1
      JOIN reserva_habitacion rh2 ON rh2.id_habitacion = rh1.id_habitacion
                                 AND rh2.id_reserva <> rh1.id_reserva
      JOIN reserva r1 ON r1.id_reserva = rh1.id_reserva AND r1.estado = 'CONFIRMADA'
      JOIN reserva r2 ON r2.id_reserva = rh2.id_reserva AND r2.estado = 'CONFIRMADA'
     WHERE ROWNUM = 1;

    UPDATE reserva_habitacion
       SET fecha_in  = v_in,
           fecha_out = v_out
     WHERE id_reserva_habitacion = v_id_rh;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba solape UPDATE -> ' || SQLERRM);
        ROLLBACK;
END;
/

-- 3d. INSERT directo en fechas libres -> debe entrar (caso positivo del disparador)
DECLARE
    v_nueva NUMBER;
BEGIN
    INSERT INTO reserva (id_cliente, id_alojamiento, fecha_creacion, fecha_checkin, fecha_checkout, estado)
    VALUES (2, :v_faloj, TRUNC(SYSDATE), DATE '2030-02-01', DATE '2030-02-03', 'CONFIRMADA')
    RETURNING id_reserva INTO v_nueva;

    INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_in, fecha_out, num_huespedes)
    VALUES (v_nueva, :v_faloj, :v_fhab, DATE '2030-02-01', DATE '2030-02-03', 1);

    DBMS_OUTPUT.PUT_LINE('3d OK: reserva ' || v_nueva || ' insertada sin cruce.');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('3d ERROR inesperado -> ' || SQLERRM);
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
 

-- 4b. Liquidación con mes inválido -> ORA-20030
BEGIN
    pkg_turismo_uq.sp_liquidacion_mensual(2025, 13);
    DBMS_OUTPUT.PUT_LINE('4b NO dio error (revisar)');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('4b Excepción sp_liquidacion_mensual (mes 13) -> ' || SQLERRM);
END;
/


PROMPT =========================================================================
PROMPT         PRUEBA 5: Auditoría en TARIFA (disparadores de fila y de sentencia)
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
 
-- Datos de la vista: meses con reservas y meses en 0 %
SELECT alojamiento, mes, noches_vendidas, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE mes = '2025-12'
 ORDER BY pct_ocupacion DESC
 FETCH FIRST 5 ROWS ONLY;

SELECT municipio, alojamiento, mes, noches_vendidas, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE noches_vendidas = 0
 ORDER BY mes, alojamiento
 FETCH FIRST 5 ROWS ONLY;

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