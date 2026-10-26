SET SERVEROUTPUT ON;

------------------------------ BITACORA_TARIFA --------------------------------
-- Tabla donde se anotan los cambios de tarifas
-- (la primera vez los DROP dan error porque las tablas no existen)

DROP TABLE bitacora_tarifa;
DROP TABLE tarifa_foto;

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

-- Copia de las tarifas antes de cada cambio (la "foto" de antes)
CREATE TABLE tarifa_foto (
    id_tarifa NUMBER,
    id_habitacion NUMBER,
    id_temporada NUMBER,
    valor_noche NUMBER(10)
);

COMMENT ON TABLE bitacora_tarifa IS 'Auditoría de cambios en TARIFA: quién, cuándo, valor anterior y valor nuevo.';
COMMENT ON TABLE tarifa_foto IS 'Copia temporal de TARIFA que usa la auditoría para conocer el valor anterior.';

-------------------- DISPARADOR SENTENCIA: AUDITORIA DE TARIFA -----------------
-- BEFORE sentencia: guarda la foto de las tarifas antes del cambio.
-- AFTER sentencia: compara la foto con la tabla y anota quién, cuándo,
-- el valor anterior y el nuevo de cada tarifa que cambió.
-- Se auditan UPDATE y DELETE porque son los que cambian un precio existente.

CREATE OR REPLACE TRIGGER trg_tarifa_foto_sentencia
BEFORE UPDATE OR DELETE ON tarifa
BEGIN
    DELETE FROM tarifa_foto;

    INSERT INTO tarifa_foto (id_tarifa, id_habitacion, id_temporada, valor_noche)
    SELECT id_tarifa, id_habitacion, id_temporada, valor_noche
      FROM tarifa;
END;
/

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

---------------- DISPARADOR FILA: SOLAPE DE RESERVAS  --------------------------
-- Antes de guardar cada habitación se have la revisión que no se cruce con una reserva
-- CONFIRMADA o COMPLETADA de la misma habitación.

CREATE OR REPLACE TRIGGER trg_impedir_solape_reserva
BEFORE INSERT ON reserva_habitacion
FOR EACH ROW
DECLARE
    v_estado reserva.estado%TYPE;
    v_solapes NUMBER;
    v_reserva_cruce NUMBER;
BEGIN
    SELECT estado INTO v_estado
      FROM reserva
     WHERE id_reserva = :NEW.id_reserva;

    -- Una reserva cancelada no ocupa la habitación
    IF v_estado <> 'CANCELADA' THEN
        SELECT COUNT(*), MIN(rh.id_reserva)
          INTO v_solapes, v_reserva_cruce
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = :NEW.id_habitacion
           AND rh.id_reserva <> :NEW.id_reserva
           AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
           AND :NEW.fecha_in < rh.fecha_out
           AND :NEW.fecha_out > rh.fecha_in;

        IF v_solapes > 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'La habitación ' || :NEW.id_habitacion
                || ' ya está reservada en esas fechas (reserva ' || v_reserva_cruce || ').');
        END IF;
    END IF;
END;
/

------------------------------ VERIFICACIÓN -------------------------------------

-- Disparadores creados (ENABLED)

SELECT trigger_name, trigger_type, triggering_event, table_name, status
FROM user_triggers
ORDER BY table_name, trigger_name;

