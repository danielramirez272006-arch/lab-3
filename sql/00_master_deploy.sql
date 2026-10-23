-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 00_master_deploy.sql
--  Propósito: Despliegue integral en un único script atómico.
--             Ejecuta DDL (14 tablas), DML (16+ filas por tabla) y
--             la configuración del rol de seguridad 'agente_n8n_readonly'.
--
--  Instrucciones de ejecución:
--    * psql:
--        createdb -U postgres aduana_db
--        psql -U postgres -d aduana_db -f sql/00_master_deploy.sql
--    * pgAdmin / DBeaver:
--        Abrir una ventana de SQL sobre la base aduana_db y ejecutar completo.
-- =============================================================================

\echo '==> [1/5] Iniciando creación de tablas y restricciones (DDL)...'
\i c:/Users/calva/taller-cli/lab3/sql/01_schema.sql

\echo '==> [2/5] Iniciando poblado de datos DML (>= 15 filas por tabla)...'
\i c:/Users/calva/taller-cli/lab3/sql/02_seed_data.sql

\echo '==> [3/5] Configurando rol de solo lectura agente_n8n_readonly...'
\i c:/Users/calva/taller-cli/lab3/sql/03_readonly_role.sql

\echo '==> [4/5] Creando vistas analíticas de alta velocidad...'
\i c:/Users/calva/taller-cli/lab3/sql/05_vistas_analiticas.sql

\echo '==> [5/5] Activando triggers automáticos de control de kardex...'
\i c:/Users/calva/taller-cli/lab3/sql/06_triggers_auditoria.sql

\echo '==> Verificación de salud del sistema:'
SELECT table_name, 
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text::int AS total_registros
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
