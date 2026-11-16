
SET SERVEROUTPUT ON;

-- Limpieza inicial para permitir re-ejecutar el script desde cero
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_rh_hab_fechas';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1418 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_reserva_cliente';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1418 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX fx_cliente_nombre_upper';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1418 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_reserva_estado';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1418 THEN RAISE; END IF;
END;
/

-------------------------------- ESTADÍSTICAS -----------------------------------
-- Se actualiza el conteo de filas de las tablas para que Oracle sepa cuántos
-- datos reales tienen antes de decidir si usa o no los índices.

EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA');
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION');
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE');

-- Tamaño de las tablas que se van a consultar
SELECT table_name, num_rows, blocks
  FROM user_tables
 WHERE table_name IN ('RESERVA', 'RESERVA_HABITACION', 'CLIENTE')
 ORDER BY table_name;

-- Índices que ya existen (creados por Oracle para PK y UNIQUE)
SELECT i.table_name, i.index_name, c.column_name, c.column_position
  FROM user_indexes i
  JOIN user_ind_columns c ON c.index_name = i.index_name
 WHERE i.table_name IN ('RESERVA', 'RESERVA_HABITACION', 'CLIENTE')
 ORDER BY i.table_name, i.index_name, c.column_position;

-- ==================== CONSULTA 1: DISPONIBILIDAD DE UNA HABITACIÓN ===========
-- Es la validación de sp_crear_reserva y del disparador de solape, y se ejecuta
-- en cada reserva, asi que sin índice Oracle recorre toda RESERVA_HABITACION
-- (TABLE ACCESS FULL) para encontrar las líneas de una sola habitación.

-- Se usará indice COMPUESTO con id_habitacion primero porque es el filtro
-- de igualdad, y luego las fechas para filtrar el cruce dentro del índice.

------------------------------ 1.1 - ANTES --------------------------------------

EXPLAIN PLAN FOR
SELECT COUNT(*)
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = 150
   AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND rh.fecha_in < DATE '2025-12-23'
   AND rh.fecha_out > DATE '2025-12-20';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: TABLE ACCESS FULL sobre RESERVA_HABITACION (antes del índice).

-- Tiempo: la consulta 2.000 veces, cada vez con una habitación distinta
DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 2000 LOOP
        SELECT COUNT(*)
          INTO v_cuenta
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = MOD(i, 600) + 1
           AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
           AND rh.fecha_in < DATE '2025-12-23'
           AND rh.fecha_out > DATE '2025-12-20';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Consulta 1 SIN índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

------------------------------ 1.2 - ÍNDICE -------------------------------------

CREATE INDEX idx_rh_hab_fechas ON reserva_habitacion (id_habitacion, fecha_in, fecha_out);

------------------------------ 1.3 - DESPUÉS ------------------------------------

EXPLAIN PLAN FOR
SELECT COUNT(*)
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = 150
   AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND rh.fecha_in < DATE '2025-12-23'
   AND rh.fecha_out > DATE '2025-12-20';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: INDEX RANGE SCAN sobre IDX_RH_HAB_FECHAS, con Cost menor que el de arriba.

DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 2000 LOOP
        SELECT COUNT(*)
          INTO v_cuenta
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = MOD(i, 600) + 1
           AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
           AND rh.fecha_in < DATE '2025-12-23'
           AND rh.fecha_out > DATE '2025-12-20';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Consulta 1 CON índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

-- ==================== CONSULTA 2: HISTORIAL DE UN CLIENTE ====================
-- Recepción consulta el historial de reservas de un cliente, como id_cliente es llave foránea, 
-- Oracle no le crea índice automático y sin él recorre las 25.000 filas de RESERVA con TABLE ACCESS FULL 
-- para extraer las pocas reservas de un cliente. 

-- Se usará un índice SIMPLE (B-Tree) sobre id_cliente porque es una búsqueda 
-- de alta selectividad que nos ayuda ubicar directamente sus filas.

------------------------------ 2.1 - ANTES --------------------------------------

EXPLAIN PLAN FOR
SELECT r.id_reserva, a.nombre AS alojamiento, r.fecha_checkin, r.fecha_checkout, r.estado
  FROM reserva r
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
 WHERE r.id_cliente = 1500
 ORDER BY r.fecha_checkin DESC;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: TABLE ACCESS FULL sobre RESERVA (antes del índice).

DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 2000 LOOP
        SELECT COUNT(r.fecha_checkout)
          INTO v_cuenta
          FROM reserva r
         WHERE r.id_cliente = MOD(i, 3000) + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Consulta 2 SIN índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

------------------------------ 2.2 - ÍNDICE -------------------------------------

CREATE INDEX idx_reserva_cliente ON reserva (id_cliente);

------------------------------ 2.3 - DESPUÉS ------------------------------------

EXPLAIN PLAN FOR
SELECT r.id_reserva, a.nombre AS alojamiento, r.fecha_checkin, r.fecha_checkout, r.estado
  FROM reserva r
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
 WHERE r.id_cliente = 1500
 ORDER BY r.fecha_checkin DESC;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: INDEX RANGE SCAN sobre IDX_RESERVA_CLIENTE, con Cost menor.

DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 2000 LOOP
        SELECT COUNT(r.fecha_checkout)
          INTO v_cuenta
          FROM reserva r
         WHERE r.id_cliente = MOD(i, 3000) + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Consulta 2 CON índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

-- ==================== CONSULTA 3: BUSCAR CLIENTE POR NOMBRE ==================
-- La Recepción busca al cliente por nombre sin importar mayúsculas o minúsculas,
-- por eso la consulta compara UPPER(nombre). Y un índice normal sobre nombre no
-- sirve, porque guarda el nombre tal cual y la consulta pregunta por UPPER(nombre).

-- Se usará índice basado en FUNCIÓN, porque guarda ya calculado UPPER(nombre).

VARIABLE v_nombre VARCHAR2(80)

-- Nombre de un cliente escrito en minúsculas
EXEC SELECT LOWER(nombre) INTO :v_nombre FROM cliente WHERE id_cliente = 1500;

PRINT v_nombre

------------------------------ 3.1 - ANTES --------------------------------------

EXPLAIN PLAN FOR
SELECT id_cliente, nombre, documento, correo, telefono
  FROM cliente
 WHERE UPPER(nombre) = UPPER(:v_nombre);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: TABLE ACCESS FULL sobre CLIENTE (antes del índice).

DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 2000 LOOP
        SELECT COUNT(documento)
          INTO v_cuenta
          FROM cliente
         WHERE UPPER(nombre) = UPPER(:v_nombre);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Consulta 3 SIN índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

------------------------------ 3.2 - ÍNDICE -------------------------------------

CREATE INDEX fx_cliente_nombre_upper ON cliente (UPPER(nombre));

-- Se actualizan las estadísticas de la tabla para que el optimizador reconozca el nuevo índice
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE');

------------------------------ 3.3 - DESPUÉS ------------------------------------

EXPLAIN PLAN FOR
SELECT id_cliente, nombre, documento, correo, telefono
  FROM cliente
 WHERE UPPER(nombre) = UPPER(:v_nombre);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: INDEX RANGE SCAN sobre FX_CLIENTE_NOMBRE_UPPER.

DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 2000 LOOP
        SELECT COUNT(documento)
          INTO v_cuenta
          FROM cliente
         WHERE UPPER(nombre) = UPPER(:v_nombre);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Consulta 3 CON índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

-- La misma búsqueda sin UPPER no usa el índice basado en función
EXPLAIN PLAN FOR
SELECT id_cliente, nombre, documento, correo, telefono
  FROM cliente
 WHERE nombre = :v_nombre;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: TABLE ACCESS FULL sobre CLIENTE: sin UPPER el índice basado en función no se usa.

-- ==================== CASO 4: UN ÍNDICE QUE NO AYUDA =========================
-- Crear un índice sobre la columna ESTADO de RESERVA.
-- Como solo existen 4 estados posibles y la mayoría de las reservas están en estado 'COMPLETADA', 
-- la consulta trae casi toda la tabla; y en un caso así, usar un índice es más lento que leer la tabla completa.

-- Cuántas reservas hay de cada estado
SELECT estado, COUNT(*) AS reservas,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS porcentaje
  FROM reserva
 GROUP BY estado
 ORDER BY reservas DESC;

------------------------------ 4.1 - ANTES --------------------------------------

EXPLAIN PLAN FOR
SELECT id_reserva, id_cliente, fecha_checkin, fecha_checkout
  FROM reserva
 WHERE estado = 'COMPLETADA';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Resultado esperado: TABLE ACCESS FULL sobre RESERVA (antes del índice).

DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 200 LOOP
        SELECT COUNT(fecha_checkout)
          INTO v_cuenta
          FROM reserva
         WHERE estado = 'COMPLETADA';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Caso 4 SIN índice: ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

------------------------------ 4.2 - ÍNDICE -------------------------------------

CREATE INDEX idx_reserva_estado ON reserva (estado);

------------------------------ 4.3 - DESPUÉS ------------------------------------
-- Aunque el índice ya existe, Oracle decide no usarlo y mantiene TABLE ACCESS FULL
-- porque la consulta recupera la mayoría de la tabla.

EXPLAIN PLAN FOR
SELECT id_reserva, id_cliente, fecha_checkin, fecha_checkout
  FROM reserva
 WHERE estado = 'COMPLETADA';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- Esperado: Mismo plan (TABLE ACCESS FULL) y mismo Cost que antes de crear el índice.

-- El tiempo no mejora porque el índice no se usa
DECLARE
    v_inicio NUMBER;
    v_cuenta NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR i IN 1 .. 200 LOOP
        SELECT COUNT(fecha_checkout)
          INTO v_cuenta
          FROM reserva
         WHERE estado = 'COMPLETADA';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Caso 4 CON índice creado (ignorado por Oracle): ' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10 || ' ms');
END;
/

-- ¿POR QUÉ NO AYUDA?
-- Un índice sirve cuando hay alta selectividad, es decir, cuando existe ese problema
-- de encontrar una "aguja en un pajar". En este caso, hay baja selectividad, porque se pide 
-- la mayoría de la tabla. Usar el índice obligaría a saltar bloque por bloque entre el índice y la tabla,
-- mientras que TABLE ACCESS FULL lee todos los bloques de corrido en menos lecturas, por eso es
-- que al final Oracle lo ignora y por eso conviene mejor eliminarlo porque no solo estorbaría
-- sino que también es costoso.

DROP INDEX idx_reserva_estado;
-------------------------------- ÍNDICES CREADOS ----------------------------------

SELECT i.table_name, i.index_name, i.index_type, c.column_name, c.column_position
  FROM user_indexes i
  JOIN user_ind_columns c ON c.index_name = i.index_name
 WHERE i.index_name IN ('IDX_RH_HAB_FECHAS', 'IDX_RESERVA_CLIENTE', 'FX_CLIENTE_NOMBRE_UPPER')
 ORDER BY i.table_name, i.index_name, c.column_position;

-- Expresión guardada por el índice basado en función
SELECT index_name, column_expression
  FROM user_ind_expressions
 WHERE index_name = 'FX_CLIENTE_NOMBRE_UPPER';
