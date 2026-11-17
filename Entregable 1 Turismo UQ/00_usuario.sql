-- =====================================================================
--  TurismoUQ
--  Crea el esquema (usuario) TURISMOUQ donde vivira todo el proyecto.
--
--  EJECUTAR COMO: SYSTEM (o SYS) conectado al servicio XEPDB1 de Oracle XE 21c.
--  - Si ya existe el usuario, se elimina y se recrea (base limpia).
-- =====================================================================
SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM dual;

ALTER SESSION SET CONTAINER = XEPDB1;

-- 1. Eliminar el usuario si ya existe (ORA-01918 = no existe, se ignora)
BEGIN
    EXECUTE IMMEDIATE 'DROP USER turismouq CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -1918 THEN
            RAISE;
        END IF;
END;
/

-- 2. Crear el usuario con cuota en el tablespace USERS
CREATE USER turismouq IDENTIFIED BY turismouq2026;
-- 3. Privilegios necesarios 
GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE SEQUENCE,
      CREATE PROCEDURE,
      CREATE TRIGGER,
      CREATE MATERIALIZED VIEW,
      CREATE SYNONYM,
      CREATE TYPE
   TO turismouq;
   
ALTER USER turismouq QUOTA UNLIMITED ON USERS;