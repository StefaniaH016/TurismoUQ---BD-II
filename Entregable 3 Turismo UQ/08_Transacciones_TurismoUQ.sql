
SET SERVEROUTPUT ON;

------------------------------ 1 - SP_RESERVA_CON_PAGO --------------------------

CREATE OR REPLACE PROCEDURE sp_reserva_con_pago (
    p_id_cliente IN cliente.id_cliente%TYPE,
    p_id_alojamiento IN alojamiento.id_alojamiento%TYPE,
    p_id_habitacion IN habitacion.id_habitacion%TYPE,
    p_fecha_in IN DATE,
    p_fecha_out IN DATE,
    p_num_huespedes IN NUMBER,
    p_id_servicio1 IN servicio.id_servicio%TYPE,
    p_cantidad1 IN NUMBER,
    p_id_servicio2 IN servicio.id_servicio%TYPE,
    p_cantidad2 IN NUMBER,
    p_monto IN pago.monto%TYPE,
    p_metodo IN pago.metodo%TYPE,
    p_id_reserva OUT reserva.id_reserva%TYPE
) IS
    v_bloqueo habitacion.id_habitacion%TYPE;
    v_precio servicio.precio%TYPE;
    v_estadia NUMBER;
    v_servicios NUMBER;
    v_total NUMBER;
BEGIN
    SAVEPOINT sp_inicio;

    -- PASO 1: bloquear la habitación para que nadie más la reserve al mismo tiempo
    BEGIN
        SELECT id_habitacion
          INTO v_bloqueo
          FROM habitacion
         WHERE id_habitacion = p_id_habitacion
           AND id_alojamiento = p_id_alojamiento
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'La habitación ' || p_id_habitacion
                || ' no pertenece al alojamiento ' || p_id_alojamiento || '.');
    END;

    -- PASO 2: reserva y habitación (fechas, cliente, capacidad, disponibilidad y tarifas)
    pkg_turismo_uq.sp_crear_reserva(p_id_cliente, p_id_alojamiento, p_id_habitacion,
                                    p_fecha_in, p_fecha_out, p_num_huespedes, p_id_reserva);

    SAVEPOINT sp_reserva_creada;

    -- PASO 3: servicios. Cada servicio tiene su propio punto de control
    -- si uno falla, solo se deshace ese servicio y se conservan la reserva y los demás servicios válidos
    IF p_id_servicio1 IS NOT NULL THEN
        SAVEPOINT sp_antes_serv1;
        BEGIN
            SELECT precio INTO v_precio FROM servicio WHERE id_servicio = p_id_servicio1;

            INSERT INTO reserva_servicio (id_reserva, id_alojamiento, id_servicio, cantidad, precio_unitario)
            VALUES (p_id_reserva, p_id_alojamiento, p_id_servicio1, p_cantidad1, v_precio);

            DBMS_OUTPUT.PUT_LINE('Servicio 1 (' || p_id_servicio1 || ') agregado.');
        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK TO sp_antes_serv1;
                DBMS_OUTPUT.PUT_LINE('ROLLBACK PARCIAL servicio 1: se descartó solo el servicio '
                    || p_id_servicio1 || ' -> ' || SQLERRM);
        END;
    END IF;

    IF p_id_servicio2 IS NOT NULL THEN
        SAVEPOINT sp_antes_serv2;
        BEGIN
            SELECT precio INTO v_precio FROM servicio WHERE id_servicio = p_id_servicio2;

            INSERT INTO reserva_servicio (id_reserva, id_alojamiento, id_servicio, cantidad, precio_unitario)
            VALUES (p_id_reserva, p_id_alojamiento, p_id_servicio2, p_cantidad2, v_precio);

            DBMS_OUTPUT.PUT_LINE('Servicio 2 (' || p_id_servicio2 || ') agregado.');
        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK TO sp_antes_serv2;
                DBMS_OUTPUT.PUT_LINE('ROLLBACK PARCIAL servicio 2: se descartó solo el servicio '
                    || p_id_servicio2 || ' -> ' || SQLERRM);
        END;
    END IF;

    -- PASO 4: Pago
    v_estadia := pkg_turismo_uq.fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);

    SELECT NVL(SUM(cantidad * precio_unitario), 0)
      INTO v_servicios
      FROM reserva_servicio
     WHERE id_reserva = p_id_reserva;

    v_total := v_estadia + v_servicios;

    IF p_monto IS NULL OR p_monto <= 0 OR p_monto > v_total THEN
        RAISE_APPLICATION_ERROR(-20041, 'El pago debe ser mayor a 0 y no puede pasar el total de la reserva ($'
            || v_total || ').');
    END IF;

    INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado)
    VALUES (p_id_reserva, SYSDATE, p_monto, p_metodo, 'EXITOSO');

    -- PASO 5: todo salió bien, se guarda junto
    DBMS_OUTPUT.PUT_LINE('COMMIT: reserva ' || p_id_reserva || ' guardada. Total $' || v_total
        || ', pagado $' || p_monto || ' con ' || p_metodo || '.');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Cualquier error en la reserva o en el pago deshace todo lo del procedimiento
        ROLLBACK TO sp_inicio;
        DBMS_OUTPUT.PUT_LINE('ROLLBACK TOTAL: no se guardó la reserva ni el pago -> ' || SQLERRM);
        p_id_reserva := NULL;
        RAISE;
END sp_reserva_con_pago;
/

------------------------------ 2 - DATOS PARA LAS PRUEBAS ----------------------
-- Busca habitaciones libres el próximo mes (día 6 al 9) en un alojamiento con
-- al menos 2 servicios, y un servicio de otro alojamiento para provocar el error.
-- Resultado esperado: fechas, alojamiento, 3 habitaciones libres y 2 servicios.

VARIABLE v_aloj NUMBER
VARIABLE v_hab1 NUMBER
VARIABLE v_hab2 NUMBER
VARIABLE v_hab3 NUMBER
VARIABLE v_serv1 NUMBER
VARIABLE v_serv2 NUMBER
VARIABLE v_serv_otro NUMBER
VARIABLE v_res1 NUMBER
VARIABLE v_res2 NUMBER

DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
BEGIN
    -- Alojamiento con 3 habitaciones libres en esas fechas y al menos 2 servicios
    SELECT h.id_alojamiento
      INTO :v_aloj
      FROM habitacion h
     WHERE h.capacidad_max >= 2
       AND NOT EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN reserva r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion
                          AND r.estado <> 'CANCELADA'
                          AND v_in < rh.fecha_out
                          AND v_out > rh.fecha_in)
       AND (SELECT COUNT(*) FROM servicio s WHERE s.id_alojamiento = h.id_alojamiento) >= 2
     GROUP BY h.id_alojamiento
    HAVING COUNT(*) >= 3
     ORDER BY h.id_alojamiento
     FETCH FIRST 1 ROWS ONLY;

    -- Las 3 primeras habitaciones libres de ese alojamiento
    SELECT MIN(id_habitacion) INTO :v_hab1
      FROM habitacion h
     WHERE h.id_alojamiento = :v_aloj
       AND h.capacidad_max >= 2
       AND NOT EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN reserva r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion
                          AND r.estado <> 'CANCELADA'
                          AND v_in < rh.fecha_out
                          AND v_out > rh.fecha_in);

    SELECT MIN(id_habitacion) INTO :v_hab2
      FROM habitacion h
     WHERE h.id_alojamiento = :v_aloj
       AND h.id_habitacion > :v_hab1
       AND h.capacidad_max >= 2
       AND NOT EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN reserva r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion
                          AND r.estado <> 'CANCELADA'
                          AND v_in < rh.fecha_out
                          AND v_out > rh.fecha_in);

    SELECT MIN(id_habitacion) INTO :v_hab3
      FROM habitacion h
     WHERE h.id_alojamiento = :v_aloj
       AND h.id_habitacion > :v_hab2
       AND h.capacidad_max >= 2
       AND NOT EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN reserva r ON r.id_reserva = rh.id_reserva
                        WHERE rh.id_habitacion = h.id_habitacion
                          AND r.estado <> 'CANCELADA'
                          AND v_in < rh.fecha_out
                          AND v_out > rh.fecha_in);

    -- Dos servicios del alojamiento y uno de otro alojamiento
    SELECT MIN(id_servicio), MAX(id_servicio)
      INTO :v_serv1, :v_serv2
      FROM servicio
     WHERE id_alojamiento = :v_aloj;

    SELECT MIN(id_servicio)
      INTO :v_serv_otro
      FROM servicio
     WHERE id_alojamiento <> :v_aloj;

    DBMS_OUTPUT.PUT_LINE('Fechas: ' || TO_CHAR(v_in, 'DD/MM/YYYY') || ' a ' || TO_CHAR(v_out, 'DD/MM/YYYY'));
    DBMS_OUTPUT.PUT_LINE('Alojamiento: ' || :v_aloj || ' | Habitaciones libres: ' || :v_hab1
        || ', ' || :v_hab2 || ', ' || :v_hab3);
    DBMS_OUTPUT.PUT_LINE('Servicios del alojamiento: ' || :v_serv1 || ' y ' || :v_serv2
        || ' | Servicio de otro alojamiento: ' || :v_serv_otro);
END;
/

------------------------------ 3 - PRUEBA 1: TODO CORRECTO ---------------------
-- Reserva + 2 servicios + pago del total
-- Resultado esperado: 'COMMIT: reserva N guardada' con el total pagado

DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
    v_total NUMBER;
    v_id NUMBER;
BEGIN
    -- Total = estadía + 1 unidad del servicio 1 + 2 unidades del servicio 2
    SELECT pkg_turismo_uq.fn_valor_estadia(:v_hab1, v_in, v_out)
           + (SELECT precio FROM servicio WHERE id_servicio = :v_serv1)
           + 2 * (SELECT precio FROM servicio WHERE id_servicio = :v_serv2)
      INTO v_total
      FROM dual;

    sp_reserva_con_pago(1, :v_aloj, :v_hab1, v_in, v_out, 2,
                        :v_serv1, 1, :v_serv2, 2,
                        v_total, 'PSE', v_id);
    :v_res1 := v_id;
END;
/

------------------------------ 4 - PRUEBA 2: ROLLBACK PARCIAL ------------------
-- El servicio 1 es del alojamiento y se inserta, el 2 es de otro y falla con ORA-02291
-- ROLLBACK TO sp_antes_serv2 deshace solo el servicio 2
-- Resultado esperado: 'ROLLBACK PARCIAL servicio 2' y la reserva con su pago y 1 servicio
DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
    v_total_parcial NUMBER;
    v_id NUMBER;
BEGIN
    SELECT pkg_turismo_uq.fn_valor_estadia(:v_hab2, v_in, v_out)
           + (SELECT precio FROM servicio WHERE id_servicio = :v_serv1)
      INTO v_total_parcial
      FROM dual;

    sp_reserva_con_pago(2, :v_aloj, :v_hab2, v_in, v_out, 2,
                        :v_serv1, 1, :v_serv_otro, 1,
                        v_total_parcial, 'TARJETA_CREDITO', v_id);
    :v_res2 := v_id;
END;
/

-- Prueba 1: reserva 1 con 1 habitación, 2 servicios y pagado igual al total
-- Prueba 2: reserva 2 con 1 habitación, 1 servicio y pagado igual a estadía + servicio 1

SELECT r.id_reserva,
       r.id_cliente,
       r.estado,
       (SELECT COUNT(*) FROM reserva_habitacion rh WHERE rh.id_reserva = r.id_reserva) AS habitaciones,
       (SELECT COUNT(*) FROM reserva_servicio rs WHERE rs.id_reserva = r.id_reserva) AS servicios,
       (SELECT SUM(p.monto) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagado
  FROM reserva r
 WHERE r.id_reserva IN (:v_res1, :v_res2);

------------------------------ 5 - PRUEBA 3: ROLLBACK TOTAL (MÉTODO) -----------
-- El método BITCOIN no existe y falla el INSERT del pago con ORA-02290
-- ROLLBACK TO sp_inicio deshace la reserva creada
-- Resultado esperado: 'Prueba 3 -> ORA-02290' y ninguna reserva nueva

DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
    v_id NUMBER;
BEGIN
    sp_reserva_con_pago(3, :v_aloj, :v_hab3, v_in, v_out, 1,
                        NULL, NULL, NULL, NULL,
                        100000, 'BITCOIN', v_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 3 -> ' || SQLERRM);
END;
/

----------------------- 6 - PRUEBA 4: ROLLBACK TOTAL (MONTO) -------------------
-- El pago supera el total de la reserva (-20041)
-- No se guarda nada
-- Resultado esperado: 'Prueba 4 -> ORA-20041'

DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
    v_id NUMBER;
BEGIN
    sp_reserva_con_pago(3, :v_aloj, :v_hab3, v_in, v_out, 1,
                        NULL, NULL, NULL, NULL,
                        999999999, 'EFECTIVO', v_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 4 -> ' || SQLERRM);
END;
/

-- Prueba 3: la habitación 3 no queda con reservas
-- Prueba 4: la habitación 3 no queda con reservas
-- Resultado esperado: 0 reservas en la habitación 3

SELECT COUNT(*) AS reservas_hab3
  FROM reserva_habitacion
 WHERE id_habitacion = :v_hab3
   AND fecha_in = ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;

------------------- 7 - PRUEBA 5: ROLLBACK TOTAL (OCUPADA) ---------------------
-- La habitación 1 ya está reservada (prueba 1)
-- sp_crear_reserva lanza ORA-20004 y no se guarda nada
-- Resultado esperado: 'Prueba 5 -> ORA-20004' y ninguna reserva nueva

DECLARE
    v_in DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 5;
    v_out DATE := ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1) + 8;
    v_id NUMBER;
BEGIN
    sp_reserva_con_pago(4, :v_aloj, :v_hab1, v_in, v_out, 1,
                        NULL, NULL, NULL, NULL,
                        100000, 'EFECTIVO', v_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Prueba 5 -> ' || SQLERRM);
END;
/

------------------------------ 8 - LIMPIEZA ------------------------------------
-- Borra las reservas de prueba para dejar la base como estaba
-- Resultado esperado: total_reservas igual al número que había antes de las pruebas

DELETE FROM pago WHERE id_reserva IN (:v_res1, :v_res2);
DELETE FROM reserva_servicio WHERE id_reserva IN (:v_res1, :v_res2);
DELETE FROM reserva_habitacion WHERE id_reserva IN (:v_res1, :v_res2);
DELETE FROM reserva WHERE id_reserva IN (:v_res1, :v_res2);
COMMIT;

SELECT COUNT(*) AS total_reservas FROM reserva;
