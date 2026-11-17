SET SERVEROUTPUT ON;

------------------------------ BITACORA_TARIFA --------------------------------
-- Tabla donde se anotan los cambios de tarifas
-- (en una base nueva no hay nada que borrar)

BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER trg_tarifa_foto_sentencia';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -4080 THEN RAISE; END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE bitacora_tarifa';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE tarifa_foto';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

CREATE TABLE bitacora_tarifa (
    id_bitacora NUMBER GENERATED ALWAYS AS IDENTITY,
    fecha_cambio DATE DEFAULT SYSDATE NOT NULL,
    usuario VARCHAR2(30) DEFAULT USER NOT NULL,
    operacion VARCHAR2(10) NOT NULL,
    id_tarifa NUMBER,
    id_habitacion NUMBER,
    id_temporada NUMBER,
    valor_anterior NUMBER(10),
    valor_nuevo NUMBER(10),
    detalle VARCHAR2(200),
    CONSTRAINT pk_bitacora_tarifa PRIMARY KEY (id_bitacora)
);

-- Tabla temporal: guarda solo las tarifas que cambia o borra cada instrucción
CREATE GLOBAL TEMPORARY TABLE tarifa_foto (
    id_tarifa NUMBER,
    id_habitacion NUMBER,
    id_temporada NUMBER,
    valor_noche NUMBER(10)
) ON COMMIT DELETE ROWS;

COMMENT ON TABLE bitacora_tarifa IS 'Auditoría de cambios en TARIFA: quién, cuándo, valor anterior y valor nuevo.';
COMMENT ON TABLE tarifa_foto IS 'Copia temporal de TARIFA que usa la auditoría para conocer el valor anterior.';

-------------------- DISPARADOR FILA: GUARDA EL VALOR ANTERIOR -----------------
-- Antes de cada UPDATE o DELETE guarda el valor anterior de la tarifa (solo esa fila).

CREATE OR REPLACE TRIGGER trg_tarifa_foto_fila
BEFORE UPDATE OR DELETE ON tarifa
FOR EACH ROW
BEGIN
    INSERT INTO tarifa_foto (id_tarifa, id_habitacion, id_temporada, valor_noche)
    VALUES (:OLD.id_tarifa, :OLD.id_habitacion, :OLD.id_temporada, :OLD.valor_noche);
END;
/

-------------------- DISPARADOR SENTENCIA: AUDITORIA DE TARIFA -----------------
-- Al terminar la instrucción compara lo guardado con TARIFA y anota quién, cuándo,
-- el valor anterior y el nuevo de cada tarifa que cambió o se borró.

CREATE OR REPLACE TRIGGER trg_auditoria_tarifa_sentencia
AFTER UPDATE OR DELETE ON tarifa
DECLARE
    v_operacion VARCHAR2(10);
    v_filas NUMBER;
BEGIN
    IF UPDATING THEN
        v_operacion := 'UPDATE';

        -- Tarifas cuyo valor cambió
        INSERT INTO bitacora_tarifa (operacion, id_tarifa, id_habitacion, id_temporada,
                                     valor_anterior, valor_nuevo, detalle)
        SELECT 'UPDATE', f.id_tarifa, f.id_habitacion, f.id_temporada,
               f.valor_noche, t.valor_noche, 'Cambio de precio'
          FROM tarifa_foto f
          JOIN tarifa t ON t.id_tarifa = f.id_tarifa
         WHERE t.valor_noche <> f.valor_noche;
    ELSE
        v_operacion := 'DELETE';

        -- Tarifas que ya no están en la tabla
        INSERT INTO bitacora_tarifa (operacion, id_tarifa, id_habitacion, id_temporada,
                                     valor_anterior, valor_nuevo, detalle)
        SELECT 'DELETE', f.id_tarifa, f.id_habitacion, f.id_temporada,
               f.valor_noche, NULL, 'Tarifa eliminada'
          FROM tarifa_foto f
         WHERE NOT EXISTS (SELECT 1 FROM tarifa t WHERE t.id_tarifa = f.id_tarifa);
    END IF;

    v_filas := SQL%ROWCOUNT;

    -- Una instrucción que no cambió ningún precio de la tarifa,
    -- tambien queda anotada
    IF v_filas = 0 THEN
        INSERT INTO bitacora_tarifa (operacion, detalle)
        VALUES (v_operacion, 'La instrucción no cambió ningún valor de tarifa');
    END IF;

    DELETE FROM tarifa_foto;
END;
/

------------------------------ 3 - SOLAPE DE RESERVAS ---------------------------
-- Al terminar la instrucción revisa las habitaciones insertadas o cambiadas.
-- Así sirve también para UPDATE y para INSERT ... SELECT (sin ORA-04091).

CREATE OR REPLACE TRIGGER trg_impedir_solape_reserva
FOR INSERT OR UPDATE OF id_reserva, id_habitacion, fecha_in, fecha_out ON reserva_habitacion
COMPOUND TRIGGER

    TYPE t_fila IS RECORD (
        id_reserva NUMBER,
        id_habitacion NUMBER,
        fecha_in DATE,
        fecha_out DATE
    );
    TYPE t_filas IS TABLE OF t_fila;
    v_filas t_filas := t_filas();

    BEFORE STATEMENT IS
    BEGIN
        v_filas := t_filas();
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        v_filas.EXTEND;
        v_filas(v_filas.LAST).id_reserva := :NEW.id_reserva;
        v_filas(v_filas.LAST).id_habitacion := :NEW.id_habitacion;
        v_filas(v_filas.LAST).fecha_in := :NEW.fecha_in;
        v_filas(v_filas.LAST).fecha_out := :NEW.fecha_out;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_estado reserva.estado%TYPE;
        v_hab NUMBER;
        v_res NUMBER;
        v_in DATE;
        v_out DATE;
        v_solapes NUMBER;
        v_reserva_cruce NUMBER;
    BEGIN
        FOR i IN 1 .. v_filas.COUNT LOOP
            v_hab := v_filas(i).id_habitacion;
            v_res := v_filas(i).id_reserva;
            v_in := v_filas(i).fecha_in;
            v_out := v_filas(i).fecha_out;

            SELECT estado INTO v_estado
              FROM reserva
             WHERE id_reserva = v_res;

            -- Una reserva cancelada no ocupa la habitación
            IF v_estado <> 'CANCELADA' THEN
                SELECT COUNT(*), MIN(rh.id_reserva)
                  INTO v_solapes, v_reserva_cruce
                  FROM reserva_habitacion rh
                  JOIN reserva r ON r.id_reserva = rh.id_reserva
                 WHERE rh.id_habitacion = v_hab
                   AND rh.id_reserva <> v_res
                   AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
                   AND v_in < rh.fecha_out
                   AND v_out > rh.fecha_in;

                IF v_solapes > 0 THEN
                    RAISE_APPLICATION_ERROR(-20010, 'La habitación ' || v_hab
                        || ' ya está reservada en esas fechas (reserva ' || v_reserva_cruce || ').');
                END IF;
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END trg_impedir_solape_reserva;
/

------------------------------------------------------ 4 - VALIDACIÓN DE RESEÑAS -------------------------
-- Solo se reseña una reserva COMPLETADA con check-out anterior a hoy

CREATE OR REPLACE TRIGGER trg_valida_resena
BEFORE INSERT ON resena
FOR EACH ROW
DECLARE
    v_estado reserva.estado%TYPE;
    v_checkout reserva.fecha_checkout%TYPE;
BEGIN
    SELECT estado, fecha_checkout
      INTO v_estado, v_checkout
      FROM reserva
     WHERE id_reserva = :NEW.id_reserva;

    IF v_estado <> 'COMPLETADA' OR v_checkout >= SYSDATE THEN
        RAISE_APPLICATION_ERROR(-20050, 'Solo se puede reseñar una reserva COMPLETADA con check-out anterior a hoy.');
    END IF;
END trg_valida_resena;
/

------------------------------ 5 - VALIDACIÓN DE CAPACIDAD -----------------------
-- Los huéspedes de cada habitación no superan su capacidad máxima

CREATE OR REPLACE TRIGGER trg_valida_capacidad
BEFORE INSERT OR UPDATE OF num_huespedes, id_habitacion ON reserva_habitacion
FOR EACH ROW
DECLARE
    v_capacidad habitacion.capacidad_max%TYPE;
BEGIN
    SELECT capacidad_max
      INTO v_capacidad
      FROM habitacion
     WHERE id_habitacion = :NEW.id_habitacion;

    IF :NEW.num_huespedes > v_capacidad THEN
        RAISE_APPLICATION_ERROR(-20051, 'La habitación ' || :NEW.id_habitacion
            || ' tiene capacidad para ' || v_capacidad || ' huésped(es).');
    END IF;
END trg_valida_capacidad;
/

------------------------------ 6 - VALIDACIÓN DE TEMPORADAS ----------------------
-- Dos temporadas no pueden cruzarse en fechas

CREATE OR REPLACE TRIGGER trg_valida_temporada
FOR INSERT OR UPDATE OF fecha_inicio, fecha_fin ON temporada
COMPOUND TRIGGER

    TYPE t_fila IS RECORD (
        id_temporada NUMBER,
        fecha_inicio DATE,
        fecha_fin DATE
    );
    TYPE t_filas IS TABLE OF t_fila;
    v_filas t_filas := t_filas();

    BEFORE STATEMENT IS
    BEGIN
        v_filas := t_filas();
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        v_filas.EXTEND;
        v_filas(v_filas.LAST).id_temporada := :NEW.id_temporada;
        v_filas(v_filas.LAST).fecha_inicio := :NEW.fecha_inicio;
        v_filas(v_filas.LAST).fecha_fin := :NEW.fecha_fin;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_choques NUMBER;
    BEGIN
        FOR i IN 1 .. v_filas.COUNT LOOP
            SELECT COUNT(*)
              INTO v_choques
              FROM temporada t
             WHERE t.id_temporada <> v_filas(i).id_temporada
               AND t.fecha_inicio <= v_filas(i).fecha_fin
               AND t.fecha_fin >= v_filas(i).fecha_inicio;

            IF v_choques > 0 THEN
                RAISE_APPLICATION_ERROR(-20040, 'La temporada ' || v_filas(i).id_temporada
                    || ' se cruza con otra temporada.');
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END trg_valida_temporada;
/

------ VERIFICACIÓN -------------------------------------

-- Disparadores creados (ENABLED)

SELECT trigger_name, trigger_type, triggering_event, table_name, status
FROM user_triggers
ORDER BY table_name, trigger_name;