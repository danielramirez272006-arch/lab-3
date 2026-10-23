-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 03_readonly_role.sql
--  Propósito: Crear el rol de SOLO LECTURA que usará el agente de IA en n8n.
--
--  Ejecutar como superusuario o como el dueño (owner) de las tablas,
--  conectado a la base de datos del laboratorio (ej. aduana_db).
--
--  Defensa en profundidad:
--    1) Solo se otorga SELECT (nada de INSERT/UPDATE/DELETE/DDL).
--    2) Las sesiones del rol son read-only por defecto a nivel de servidor.
--    3) statement_timeout evita consultas eternas generadas por el LLM.
--    4) Se revoca CREATE sobre el esquema public.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Crear (o actualizar) el rol con LOGIN y contraseña. Idempotente.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agente_n8n_readonly') THEN
        CREATE ROLE agente_n8n_readonly WITH LOGIN PASSWORD 'AduanaReadOnly2026!';
    ELSE
        ALTER ROLE agente_n8n_readonly WITH PASSWORD 'AduanaReadOnly2026!';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- 2. Permiso de conexión a la base de datos ACTUAL (sin escribir su nombre).
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO agente_n8n_readonly', current_database());
END
$$;

-- -----------------------------------------------------------------------------
-- 3. Permisos sobre el esquema public: solo USAGE (ver objetos), nunca CREATE.
-- -----------------------------------------------------------------------------
REVOKE ALL    ON SCHEMA public FROM agente_n8n_readonly;
GRANT  USAGE  ON SCHEMA public TO   agente_n8n_readonly;

-- -----------------------------------------------------------------------------
-- 4. SOLO SELECT sobre TODAS las tablas existentes del esquema public.
--    (Primero se revoca todo para garantizar un estado limpio.)
-- -----------------------------------------------------------------------------
REVOKE ALL    ON ALL TABLES    IN SCHEMA public FROM agente_n8n_readonly;
REVOKE ALL    ON ALL SEQUENCES IN SCHEMA public FROM agente_n8n_readonly;
REVOKE ALL    ON ALL FUNCTIONS IN SCHEMA public FROM agente_n8n_readonly;
GRANT  SELECT ON ALL TABLES    IN SCHEMA public TO   agente_n8n_readonly;

-- -----------------------------------------------------------------------------
-- 5. SELECT automático sobre tablas que se creen en el FUTURO en public
--    (aplica a objetos creados por el rol que ejecuta este script).
-- -----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO agente_n8n_readonly;

-- -----------------------------------------------------------------------------
-- 6. Blindaje a nivel de sesión.
-- -----------------------------------------------------------------------------
ALTER ROLE agente_n8n_readonly SET default_transaction_read_only = on;   -- toda transacción es READ ONLY
ALTER ROLE agente_n8n_readonly SET statement_timeout             = '15s';
ALTER ROLE agente_n8n_readonly SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE agente_n8n_readonly SET search_path                   = public;

-- -----------------------------------------------------------------------------
-- 7. Verificación (opcional): lista los privilegios efectivos del rol.
--    Debe devolver únicamente filas con privilege_type = 'SELECT'.
-- -----------------------------------------------------------------------------
SELECT table_name, privilege_type
FROM   information_schema.role_table_grants
WHERE  grantee = 'agente_n8n_readonly'
ORDER  BY table_name;
