-- EXPERIMENTO DE CONCURRENCIA - SESIÓN B (hoja "no compartida")
-- Cada paso se ejecuta con Ctrl+Enter, una instrucción a la vez

SET SERVEROUTPUT ON
SET VERIFY OFF

-- Las mismas fechas y la misma habitación de la sesión A (paso 0)
DEFINE f_in = 2026-12-14
DEFINE f_out = 2026-12-17
DEFINE aloj = 0
DEFINE hab = 0

VARIABLE v_res NUMBER

-- ============================ PARTE A: SIN FOR UPDATE ========================

------------------------------ PASO A2 ------------------------------------------
-- Después del paso A1 de la sesión A, se reserva la misma habitación para el cliente 2
-- No espera ni da error porque la sesión A todavía no hace COMMIT
-- Esta sesión no ve la reserva de A, así que la validación dice que está libre
-- Resultado esperado: sin error, la reserva se registra sin esperar

EXEC pkg_turismo_uq.sp_crear_reserva(2, &aloj, &hab, DATE '&f_in', DATE '&f_out', 1, :v_res);

------------------------------ PASO A4 ------------------------------------------
-- Después del COMMIT de la sesión A, guarda la segunda reserva
-- Resultado esperado: Commit complete

COMMIT;

-- ============================ PARTE B: CON FOR UPDATE ========================

------------------------------ PASO B2 -----------------------------------------
-- Después del paso B1 de la sesión A, intenta bloquear la misma habitación
-- Se queda esperando porque la sesión A tiene la fila bloqueada
-- Resultado esperado: la sesión espera hasta el COMMIT de la sesión A (paso B3)

SELECT id_habitacion, numero
  FROM habitacion
 WHERE id_habitacion = &hab
   FOR UPDATE;

------------------------------ PASO B4 ------------------------------------------
-- Cuando el paso B2 termina, después del COMMIT de la sesión A
-- Ahora sí ve la reserva de A
-- Resultado esperado: ORA-20004 (habitación no disponible)

EXEC pkg_turismo_uq.sp_crear_reserva(2, &aloj, &hab, DATE '&f_in', DATE '&f_out', 1, :v_res);

-- Suelta el bloqueo que tomó en el paso B2
-- Resultado esperado: Rollback complete.
ROLLBACK;

-- ============================ PARTE C: NOWAIT Y WAIT ==========================
-- Ejecutar cuando la sesión A ya tiene la fila bloqueada (paso C1)

------------------------------ PASO C2 ------------------------------------------
-- Después del paso C1 de la sesión A, NOWAIT no espera y falla al instante
-- Resultado esperado: ORA-00054 (recurso ocupado)

SELECT id_habitacion, numero
  FROM habitacion
 WHERE id_habitacion = &hab
   FOR UPDATE NOWAIT;

------------------------------ PASO C3 ------------------------------------------
-- WAIT 5 espera como máximo 5 segundos y luego falla
-- Resultado esperado: ORA-30006 después de 5 segundos

SELECT id_habitacion, numero
  FROM habitacion
 WHERE id_habitacion = &hab
   FOR UPDATE WAIT 5;
