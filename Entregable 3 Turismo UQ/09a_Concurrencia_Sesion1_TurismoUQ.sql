-- EXPERIMENTO DE CONCURRENCIA - SESIÓN A (hoja normal de SQL Developer)
-- Cada paso se ejecuta con Ctrl+Enter, una instrucción a la vez

SET SERVEROUTPUT ON
SET VERIFY OFF

-- Fechas del experimento 
DEFINE f_in = 2026-12-14
DEFINE f_out = 2026-12-17

VARIABLE v_res NUMBER

-------------------- PASO 0 - ELEGIR LA HABITACIÓN -----------------------------
-- Busca una habitación libre en esas fechas
-- Los dos números que salgan van en los DEFINE de abajo
-- Resultado esperado: una fila con la habitación libre

SELECT h.id_alojamiento, h.id_habitacion, h.numero, h.capacidad_max
  FROM habitacion h
 WHERE h.capacidad_max >= 2
   AND NOT EXISTS (SELECT 1
                     FROM reserva_habitacion rh
                     JOIN reserva r ON r.id_reserva = rh.id_reserva
                    WHERE rh.id_habitacion = h.id_habitacion
                      AND r.estado <> 'CANCELADA'
                      AND DATE '&f_in' < rh.fecha_out
                      AND DATE '&f_out' > rh.fecha_in)
 ORDER BY h.id_habitacion
 FETCH FIRST 1 ROWS ONLY;

--cambiar con los números que salgan en la consulta (son los mismos para la sesión B)
DEFINE aloj = 0
DEFINE hab = 0

-- ============================ PARTE A: SIN FOR UPDATE ========================
-- Las dos sesiones reservan la misma habitación con sp_crear_reserva

------------------------------ PASO A1 -----------------------------------------
-- El cliente 1 reserva la habitación, todavía sin COMMIT
-- Resultado esperado: PL/SQL procedure successfully completed

EXEC pkg_turismo_uq.sp_crear_reserva(1, &aloj, &hab, DATE '&f_in', DATE '&f_out', 1, :v_res);

------------------------------ PASO A3 ------------------------------------------
-- Después de que la sesión B hace el paso A2, guarda la reserva
-- Resultado esperado: Commit complete

COMMIT;

------------------------------ PASO A5 ------------------------------------------
-- Tras el COMMIT de la sesión B, se listan las reservas de la habitación en esas fechas
-- Resultado esperado: 2 reservas con fechas que se cruzan (la habitación se vendió dos veces)

SELECT rh.id_reserva, r.id_cliente, r.estado, rh.id_habitacion, rh.fecha_in, rh.fecha_out
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = &hab
   AND rh.fecha_in < DATE '&f_out'
   AND rh.fecha_out > DATE '&f_in'
 ORDER BY rh.id_reserva;

------------------------------ PASO A6 -----------------------------------------
-- Se borran las dos reservas de la parte A para repetir la prueba con FOR UPDATE
-- Resultado esperado: Commit complete

DELETE FROM reserva_habitacion
 WHERE id_reserva IN (SELECT id_reserva
                        FROM reserva
                       WHERE id_cliente IN (1, 2)
                         AND id_alojamiento = &aloj
                         AND fecha_checkin = DATE '&f_in'
                         AND fecha_creacion = TRUNC(SYSDATE));

DELETE FROM reserva
 WHERE id_cliente IN (1, 2)
   AND id_alojamiento = &aloj
   AND fecha_checkin = DATE '&f_in'
   AND fecha_creacion = TRUNC(SYSDATE);

COMMIT;

-- ============================ PARTE B: CON FOR UPDATE ========================
-- Antes de reservar, cada sesión bloquea la fila de la habitación
-- La sesión B tiene que esperar a que la sesión A termine

------------------------------ PASO B1 ------------------------------------------
-- Bloquea la habitación y reserva, todavía sin COMMIT
-- Resultado esperado: la habitación queda bloqueada hasta el COMMIT del paso B3

SELECT id_habitacion, numero
  FROM habitacion
 WHERE id_habitacion = &hab
   FOR UPDATE;

EXEC pkg_turismo_uq.sp_crear_reserva(1, &aloj, &hab, DATE '&f_in', DATE '&f_out', 1, :v_res);

------------------------------ PASO B3 ------------------------------------------
-- Mientras la sesión B espera en el paso B2, se guarda y se libera el bloqueo
-- Resultado esperado: Commit complete, y la sesión B sale de la espera

COMMIT;

------------------------------ PASO B5 ------------------------------------------
-- Después del paso B4 de la sesión B, solo queda 1 reserva en esas fechas
-- Resultado esperado: 1 fila

SELECT rh.id_reserva, r.id_cliente, r.estado, rh.id_habitacion, rh.fecha_in, rh.fecha_out
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = &hab
   AND rh.fecha_in < DATE '&f_out'
   AND rh.fecha_out > DATE '&f_in'
 ORDER BY rh.id_reserva;

-- ============================ PARTE C: NOWAIT Y WAIT ==========================
-- Formas de no quedarse esperando indefinidamente.

------------------------------ PASO C1 ------------------------------------------
-- Bloquea la habitación y conserva el bloqueo
-- Resultado esperado: la habitación queda bloqueada hasta el ROLLBACK del paso C4

SELECT id_habitacion, numero
  FROM habitacion
 WHERE id_habitacion = &hab
   FOR UPDATE;

------------------------------ PASO C4 -----------------------------------------
-- Después de los pasos C2 y C3 de la sesión B, libera el bloqueo
-- Resultado esperado: Rollback complete

ROLLBACK;

------------------------------ LIMPIEZA FINAL ----------------------------------
-- Se borra la reserva de la parte B
-- Resultado esperado: Commit complete

DELETE FROM reserva_habitacion
 WHERE id_reserva IN (SELECT id_reserva
                        FROM reserva
                       WHERE id_cliente IN (1, 2)
                         AND id_alojamiento = &aloj
                         AND fecha_checkin = DATE '&f_in'
                         AND fecha_creacion = TRUNC(SYSDATE));

DELETE FROM reserva
 WHERE id_cliente IN (1, 2)
   AND id_alojamiento = &aloj
   AND fecha_checkin = DATE '&f_in'
   AND fecha_creacion = TRUNC(SYSDATE);

COMMIT;
