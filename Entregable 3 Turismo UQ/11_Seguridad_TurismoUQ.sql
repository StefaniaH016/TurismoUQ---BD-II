-- PARTE A se ejecuta como SYSTEM
-- PARTE B con el usuario del proyecto
-- PARTE C con cada usuario nuevo
-- El dueño de los objetos es turismouq 

-- ============================ PARTE A (ADMIN/SYSTEM) ============================

ALTER SESSION SET CONTAINER = XEPDB1;

BEGIN
    EXECUTE IMMEDIATE 'DROP USER u_recepcion CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1918 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER u_admin_aloj CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1918 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER u_gerente CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1918 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP USER u_auditor CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1918 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP ROLE rol_recepcion';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1919 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP ROLE rol_admin_alojamiento';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1919 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP ROLE rol_gerente';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1919 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP ROLE rol_auditor';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1919 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP PROFILE perfil_turismo CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -2380 THEN RAISE; END IF;
END;
/

------------------------------ 1 - PERFIL ---------------------------------------
-- Máximo de sesiones abiertas al mismo tiempo: 2
-- Minutos máximos de una sesión: 480 
-- Minutos sin actividad antes de cerrar la sesión: 15
-- Intentos fallidos y tiempo de bloqueo: 1/24 = 1H
-- Días que dura la contraseña: 90

CREATE PROFILE perfil_turismo LIMIT
    SESSIONS_PER_USER 2
    CONNECT_TIME 480
    IDLE_TIME 15
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME 1/24
    PASSWORD_LIFE_TIME 90;

------------------------------ 2 - ROLES ----------------------------------------

CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

GRANT CREATE SESSION TO rol_recepcion, rol_admin_alojamiento, rol_gerente, rol_auditor;

------------------------------ 3 - USUARIOS -------------------------------------
-- Se crean sin cuota en tablespaces ya que ninguno crea objetos propios.

CREATE USER u_recepcion IDENTIFIED BY Recepcion2026 PROFILE perfil_turismo;
CREATE USER u_admin_aloj IDENTIFIED BY AdminAloj2026 PROFILE perfil_turismo;
CREATE USER u_gerente IDENTIFIED BY Gerente2026 PROFILE perfil_turismo;
CREATE USER u_auditor IDENTIFIED BY Auditor2026 PROFILE perfil_turismo;

GRANT rol_recepcion TO u_recepcion;
GRANT rol_admin_alojamiento TO u_admin_aloj;
GRANT rol_gerente TO u_gerente;
GRANT rol_auditor TO u_auditor;

-- Verificación de usuarios, roles y perfil en el diccionario
SELECT username, account_status, profile
  FROM dba_users
 WHERE username LIKE 'U\_%' ESCAPE '\'
 ORDER BY username;

SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE grantee LIKE 'U\_%' ESCAPE '\'
 ORDER BY grantee;

SELECT resource_name, limit
  FROM dba_profiles
 WHERE profile = 'PERFIL_TURISMO'
   AND resource_name IN ('SESSIONS_PER_USER', 'CONNECT_TIME', 'IDLE_TIME',
                         'FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LOCK_TIME', 'PASSWORD_LIFE_TIME')
 ORDER BY resource_name;

-- ============================ PARTE B (USUARIO) ===============================

------------------------------ 4 - VISTAS DE RECEPCIÓN --------------------------
-- Recepción opera exclusivamente sobre vistas (sin acceso directo a tablas).

-- Vista simple de una sola tabla, se puede hacer INSERT y UPDATE a través de ella.
CREATE OR REPLACE VIEW v_rec_cliente AS
SELECT id_cliente, nombre, documento, correo, telefono, ciudad_origen
  FROM cliente;

-- Habitaciones con su precio por temporada
CREATE OR REPLACE VIEW v_rec_tarifa AS
SELECT a.id_alojamiento,
       a.nombre AS alojamiento,
       m.nombre AS municipio,
       h.id_habitacion,
       h.numero,
       h.tipo,
       h.capacidad_max,
       t.nombre AS temporada,
       t.fecha_inicio,
       t.fecha_fin,
       tf.valor_noche
  FROM tarifa tf
  JOIN habitacion h ON h.id_habitacion = tf.id_habitacion
  JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
  JOIN municipio m ON m.id_municipio = a.id_municipio
  JOIN temporada t ON t.id_temporada = tf.id_temporada
WITH READ ONLY;

-- Reservas con cliente, habitación y lo pagado, para consultar disponibilidad y estado
CREATE OR REPLACE VIEW v_rec_reserva AS
SELECT r.id_reserva,
       c.nombre AS cliente,
       c.documento,
       a.nombre AS alojamiento,
       rh.id_habitacion,
       h.numero AS habitacion,
       rh.fecha_in,
       rh.fecha_out,
       rh.num_huespedes,
       r.estado,
       (SELECT NVL(SUM(p.monto), 0)
          FROM pago p
         WHERE p.id_reserva = r.id_reserva
           AND p.estado = 'EXITOSO') AS pagado
  FROM reserva r
  JOIN cliente c ON c.id_cliente = r.id_cliente
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
WITH READ ONLY;

-- Servicios adicionales por alojamiento, para ofrecerlos al reservar
CREATE OR REPLACE VIEW v_rec_servicio AS
SELECT s.id_servicio,
       s.id_alojamiento,
       a.nombre AS alojamiento,
       s.nombre AS servicio,
       s.descripcion,
       s.precio
  FROM servicio s
  JOIN alojamiento a ON a.id_alojamiento = s.id_alojamiento
WITH READ ONLY;

COMMENT ON TABLE v_rec_cliente IS 'Vista de recepción: datos de contacto de los clientes.';
COMMENT ON TABLE v_rec_tarifa IS 'Vista de recepción: habitaciones y precio por temporada.';
COMMENT ON TABLE v_rec_reserva IS 'Vista de recepción: reservas con cliente, habitación y valor pagado.';
COMMENT ON TABLE v_rec_servicio IS 'Vista de recepción: catálogo de servicios adicionales por alojamiento.';

------------------------------ 5 - PRIVILEGIOS POR ROL --------------------------

-- RECEPCIÓN: consulta las vistas, registra y corrige clientes, y crea reservas
-- con pago a través del procedimiento (el procedimiento usa los permisos del
-- dueño, así que recepción no necesita permisos sobre las tablas)
GRANT SELECT, INSERT ON v_rec_cliente TO rol_recepcion;
GRANT UPDATE (nombre, correo, telefono, ciudad_origen) ON v_rec_cliente TO rol_recepcion;
GRANT SELECT ON v_rec_tarifa TO rol_recepcion;
GRANT SELECT ON v_rec_reserva TO rol_recepcion;
GRANT SELECT ON v_rec_servicio TO rol_recepcion;
GRANT EXECUTE ON sp_reserva_con_pago TO rol_recepcion;

-- ADMINISTRADOR DE ALOJAMIENTO: mantiene habitaciones, tarifas y servicios
-- (crear y modificar, no borrar) y consulta las reservas. No ve clientes ni pagos.
GRANT SELECT, INSERT ON habitacion TO rol_admin_alojamiento;
GRANT UPDATE (capacidad_max, tipo, descripcion) ON habitacion TO rol_admin_alojamiento;
GRANT SELECT, INSERT ON tarifa TO rol_admin_alojamiento;
GRANT UPDATE (valor_noche) ON tarifa TO rol_admin_alojamiento;
GRANT SELECT, INSERT ON servicio TO rol_admin_alojamiento;
GRANT UPDATE (nombre, descripcion, precio) ON servicio TO rol_admin_alojamiento;
GRANT SELECT ON alojamiento TO rol_admin_alojamiento;
GRANT SELECT ON temporada TO rol_admin_alojamiento;
GRANT SELECT ON reserva TO rol_admin_alojamiento;
GRANT SELECT ON reserva_habitacion TO rol_admin_alojamiento;
GRANT SELECT ON reserva_servicio TO rol_admin_alojamiento;

-- GERENTE: solo lectura de la información del negocio para sus análisis.
-- No modifica nada y no ve los datos personales de los clientes.
GRANT SELECT ON municipio TO rol_gerente;
GRANT SELECT ON tipo_alojamiento TO rol_gerente;
GRANT SELECT ON alojamiento TO rol_gerente;
GRANT SELECT ON habitacion TO rol_gerente;
GRANT SELECT ON temporada TO rol_gerente;
GRANT SELECT ON tarifa TO rol_gerente;
GRANT SELECT ON reserva TO rol_gerente;
GRANT SELECT ON reserva_habitacion TO rol_gerente;
GRANT SELECT ON reserva_servicio TO rol_gerente;
GRANT SELECT ON servicio TO rol_gerente;
GRANT SELECT ON pago TO rol_gerente;
GRANT SELECT ON resena TO rol_gerente;
GRANT SELECT ON v_noche_ocupada TO rol_gerente;
GRANT SELECT ON mv_ocupacion_mensual TO rol_gerente;
GRANT SELECT ON liquidacion_mensual TO rol_gerente;

-- AUDITOR: solo lectura de lo que se revisa en una auditoría, como cambios de
-- tarifas, pagos, reservas y usuarios del sistema. No modifica nada.
GRANT SELECT ON bitacora_tarifa TO rol_auditor;
GRANT SELECT ON tarifa TO rol_auditor;
GRANT SELECT ON pago TO rol_auditor;
GRANT SELECT ON reserva TO rol_auditor;
GRANT SELECT ON usuario_sistema TO rol_auditor;
GRANT SELECT ON liquidacion_mensual TO rol_auditor;

-- Verificación de privilegios asignados por rol
SELECT grantee, table_name, privilege
  FROM user_tab_privs_made
 WHERE grantee LIKE 'ROL\_%' ESCAPE '\'
 ORDER BY grantee, table_name, privilege;

-- ============================ PARTE C (PRUEBAS) ===============================
-- Ejecutar bloque por bloque (autocommit apagado para revertir datos de prueba).

SET SERVEROUTPUT ON;

------------------------------ 6 - PRUEBAS RECEPCIÓN ------------------------------------

CONNECT u_recepcion/Recepcion2026@//localhost:1521/XEPDB1

SET SERVEROUTPUT ON;

-- Roles y privilegios de la sesión
SELECT * FROM session_roles;
SELECT table_name, privilege FROM role_tab_privs ORDER BY table_name, privilege;
-- Resultado esperado: ROL_RECEPCION y sus privilegios sobre las vistas.

-- SÍ puede: consultar las vistas
-- Resultado esperado: una fila por cada consulta, sin error.
SELECT * FROM turismouq.v_rec_cliente WHERE id_cliente = 9;
SELECT * FROM turismouq.v_rec_reserva WHERE id_reserva = 100;
SELECT alojamiento, numero, temporada, valor_noche FROM turismouq.v_rec_tarifa WHERE id_habitacion = 1;
SELECT alojamiento, servicio, precio FROM turismouq.v_rec_servicio WHERE id_alojamiento = 1;

-- SÍ puede: registrar un cliente a través de la vista
-- Resultado esperado: 1 fila insertada y consultada; el ROLLBACK la quita.
INSERT INTO turismouq.v_rec_cliente (nombre, documento, correo, telefono, ciudad_origen)
VALUES ('Cliente Prueba Recepcion', '9999999999', 'prueba.recepcion@correo.com', '3009999999', 'Armenia');

SELECT * FROM turismouq.v_rec_cliente WHERE documento = '9999999999';

ROLLBACK;

-- SÍ puede: usar el procedimiento (con un método de pago inválido para que
-- haga ROLLBACK total y no deje datos)
-- Resultado esperado: 'Recepción ejecutó el procedimiento -> ORA-02290: restricción de control (TURISMOUQ.CK_PAGO_METODO) violada.
DECLARE
    v_id NUMBER;
BEGIN
    turismouq.sp_reserva_con_pago(1, 1, 1, TRUNC(SYSDATE) + 30, TRUNC(SYSDATE) + 32, 1,
                                   NULL, NULL, NULL, NULL, 100000, 'BITCOIN', v_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Recepción ejecutó el procedimiento -> ' || SQLERRM);
END;
/

-- NO puede: leer las tablas (ORA-00942)
-- Resultado esperado: ORA-00942 en cada SELECT.
SELECT * FROM turismouq.cliente WHERE id_cliente = 9;
SELECT * FROM turismouq.reserva WHERE id_reserva = 100;
SELECT * FROM turismouq.servicio WHERE id_alojamiento = 1;

-- NO puede: borrar clientes ni modificar las vistas de solo lectura (ORA-01031)
DELETE FROM turismouq.v_rec_cliente WHERE id_cliente = 9;
UPDATE turismouq.v_rec_reserva SET estado = 'CANCELADA' WHERE id_reserva = 100;



------------------------------ 7 - PRUEBAS ADMINISTRADOR DE ALOJAMIENTO -----------------

CONNECT u_admin_aloj/AdminAloj2026@//localhost:1521/XEPDB1

SELECT * FROM session_roles;

-- SÍ puede: consultar y cambiar una tarifa (queda en la bitácora de auditoría)
-- Resultado esperado: 1 fila actualizada; el ROLLBACK la deshace.
SELECT id_tarifa, id_habitacion, id_temporada, valor_noche FROM turismouq.tarifa WHERE id_tarifa = 1;
UPDATE turismouq.tarifa SET valor_noche = valor_noche + 1000 WHERE id_tarifa = 1;
ROLLBACK;

-- SÍ puede: consultar reservas
-- Resultado esperado: 1 fila.
SELECT id_reserva, id_alojamiento, fecha_checkin, estado FROM turismouq.reserva WHERE id_reserva = 100;

-- NO puede: borrar habitaciones ni modificar reservas (ORA-01031)
DELETE FROM turismouq.habitacion WHERE id_habitacion = 1;
UPDATE turismouq.reserva SET estado = 'CANCELADA' WHERE id_reserva = 100;

-- NO puede: ver clientes ni pagos (ORA-00942)
SELECT * FROM turismouq.cliente WHERE id_cliente = 9;
SELECT * FROM turismouq.pago WHERE id_reserva = 100;

------------------------------ 8 - PRUEBAS GERENTE --------------------------------------

CONNECT u_gerente/Gerente2026@//localhost:1521/XEPDB1

SELECT * FROM session_roles;

-- SÍ puede: consultar la ocupación y los ingresos
-- Resultado esperado: 5 filas de ocupación y una fila por año con lo recaudado.
SELECT municipio, alojamiento, mes, pct_ocupacion
  FROM turismouq.mv_ocupacion_mensual
 WHERE mes = '2025-12'
 ORDER BY pct_ocupacion DESC
 FETCH FIRST 5 ROWS ONLY;

SELECT EXTRACT(YEAR FROM fecha_pago) AS anio, SUM(monto) AS recaudado
  FROM turismouq.pago
 WHERE estado = 'EXITOSO'
 GROUP BY EXTRACT(YEAR FROM fecha_pago)
 ORDER BY anio;

-- NO puede: modificar datos (ORA-01031)
UPDATE turismouq.tarifa SET valor_noche = 1 WHERE id_tarifa = 1;

-- NO puede: ver los datos personales de los clientes (ORA-00942)
SELECT * FROM turismouq.cliente WHERE id_cliente = 9;

------------------------------ 9 - PRUEBAS AUDITOR --------------------------------------

CONNECT u_auditor/Auditor2026@//localhost:1521/XEPDB1

SELECT * FROM session_roles;

-- SÍ puede: revisar la bitácora de tarifas y los pagos
-- Resultado esperado: filas de la bitácora y un resumen de pagos por estado.
SELECT * FROM turismouq.bitacora_tarifa ORDER BY id_bitacora DESC FETCH FIRST 10 ROWS ONLY;

SELECT estado, COUNT(*) AS pagos, SUM(monto) AS valor
  FROM turismouq.pago
 GROUP BY estado;

-- NO puede: modificar pagos ni la bitácora (ORA-01031)
UPDATE turismouq.pago SET monto = 1 WHERE id_pago = 1;
DELETE FROM turismouq.bitacora_tarifa;

-- NO puede: ver clientes (ORA-00942)
SELECT * FROM turismouq.cliente WHERE id_cliente = 9;
