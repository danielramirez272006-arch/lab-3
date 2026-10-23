-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 01_schema.sql
--  Motor   : PostgreSQL 13+ (probado con sintaxis estÃ¡ndar de PG 16)
--  PropÃ³sito: Crear las 14 tablas relacionales con todas sus restricciones
--             de integridad (PK, FK, UNIQUE, CHECK, DEFAULT).
--
--  PolÃ­tica de borrado (ON DELETE):
--    * RESTRICT -> CatÃ¡logos / entidades maestras (paÃ­s, importador, agente,
--                  partida, producto, funcionario, bodega). No se pueden
--                  eliminar si existen registros que dependen de ellos.
--    * CASCADE  -> Entidades "hijas" que no tienen sentido sin su padre
--                  (detalle, liquidaciÃ³n, contenedor, inspecciÃ³n y
--                  movimientos de inventario).
--
--  Orden de creaciÃ³n: de tablas independientes a tablas dependientes.
-- =============================================================================

BEGIN;

-- Limpieza opcional para re-ejecutar el script en un entorno de laboratorio.
DROP TABLE IF EXISTS inspeccion             CASCADE;
DROP TABLE IF EXISTS movimiento_inventario  CASCADE;
DROP TABLE IF EXISTS inventario_bodega      CASCADE;
DROP TABLE IF EXISTS bodega                 CASCADE;
DROP TABLE IF EXISTS contenedor             CASCADE;
DROP TABLE IF EXISTS liquidacion_arancel    CASCADE;
DROP TABLE IF EXISTS detalle_declaracion    CASCADE;
DROP TABLE IF EXISTS declaracion            CASCADE;
DROP TABLE IF EXISTS funcionario            CASCADE;
DROP TABLE IF EXISTS producto               CASCADE;
DROP TABLE IF EXISTS partida_arancelaria    CASCADE;
DROP TABLE IF EXISTS agente_aduanal         CASCADE;
DROP TABLE IF EXISTS importador             CASCADE;
DROP TABLE IF EXISTS pais                   CASCADE;


-- -----------------------------------------------------------------------------
-- 1. PAIS : CatÃ¡logo de paÃ­ses (origen / procedencia / domicilio).
-- -----------------------------------------------------------------------------
CREATE TABLE pais (
    id_pais        SERIAL        PRIMARY KEY,
    codigo_iso     CHAR(2)       NOT NULL UNIQUE
                                 CHECK (codigo_iso ~ '^[A-Z]{2}$'),   -- ISO 3166-1 alfa-2
    nombre         VARCHAR(100)  NOT NULL UNIQUE
);
COMMENT ON TABLE pais IS 'CatÃ¡logo de paÃ­ses segÃºn ISO 3166-1.';


-- -----------------------------------------------------------------------------
-- 2. IMPORTADOR : Persona jurÃ­dica/natural que importa mercancÃ­as.
-- -----------------------------------------------------------------------------
CREATE TABLE importador (
    id_importador         SERIAL        PRIMARY KEY,
    identificacion_fiscal VARCHAR(20)   NOT NULL UNIQUE,              -- RTN / NIT / RFC
    razon_social          VARCHAR(150)  NOT NULL,
    direccion             VARCHAR(250),
    telefono              VARCHAR(20),
    email                 VARCHAR(120)  UNIQUE
                                        CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    id_pais               INTEGER       NOT NULL
                                        REFERENCES pais (id_pais) ON DELETE RESTRICT,
    estado                VARCHAR(15)   NOT NULL DEFAULT 'ACTIVO'
                                        CHECK (estado IN ('ACTIVO', 'INACTIVO', 'SUSPENDIDO')),
    fecha_registro        DATE          NOT NULL DEFAULT CURRENT_DATE
);
COMMENT ON TABLE importador IS 'Importadores registrados ante la aduana.';


-- -----------------------------------------------------------------------------
-- 3. AGENTE_ADUANAL : Profesional autorizado que tramita las declaraciones.
-- -----------------------------------------------------------------------------
CREATE TABLE agente_aduanal (
    id_agente                   SERIAL        PRIMARY KEY,
    numero_licencia             VARCHAR(20)   NOT NULL UNIQUE,
    nombre                      VARCHAR(80)   NOT NULL,
    apellido                    VARCHAR(80)   NOT NULL,
    email                       VARCHAR(120)  UNIQUE
                                              CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    telefono                    VARCHAR(20),
    fecha_emision_licencia      DATE          NOT NULL,
    fecha_vencimiento_licencia  DATE          NOT NULL,
    estado                      VARCHAR(15)   NOT NULL DEFAULT 'ACTIVO'
                                              CHECK (estado IN ('ACTIVO', 'INACTIVO', 'SUSPENDIDO')),
    CONSTRAINT chk_agente_vigencia CHECK (fecha_vencimiento_licencia > fecha_emision_licencia)
);
COMMENT ON TABLE agente_aduanal IS 'Agentes aduanales con licencia para tramitar declaraciones.';


-- -----------------------------------------------------------------------------
-- 4. PARTIDA_ARANCELARIA : ClasificaciÃ³n del Sistema Armonizado (SA/SAC).
-- -----------------------------------------------------------------------------
CREATE TABLE partida_arancelaria (
    id_partida     SERIAL         PRIMARY KEY,
    codigo_sa      VARCHAR(12)    NOT NULL UNIQUE
                                  CHECK (codigo_sa ~ '^[0-9]{4}(\.[0-9]{2}){1,3}$'),  -- ej. 8471.30.00
    descripcion    VARCHAR(250)   NOT NULL,
    tasa_dai       NUMERIC(5,2)   NOT NULL DEFAULT 0
                                  CHECK (tasa_dai BETWEEN 0 AND 100),  -- Derecho Arancelario a la ImportaciÃ³n (%)
    tasa_iva       NUMERIC(5,2)   NOT NULL DEFAULT 15
                                  CHECK (tasa_iva BETWEEN 0 AND 100),  -- Impuesto sobre ventas ISV/IVA (%)
    unidad_medida  VARCHAR(20)    NOT NULL DEFAULT 'UNIDAD'
                                  CHECK (unidad_medida IN ('UNIDAD', 'KG', 'LITRO', 'METRO', 'PAR', 'DOCENA', 'CAJA'))
);
COMMENT ON TABLE partida_arancelaria IS 'Partidas arancelarias del Sistema Armonizado con sus tasas.';


-- -----------------------------------------------------------------------------
-- 5. PRODUCTO : MercancÃ­a catalogada y clasificada en una partida.
-- -----------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto         SERIAL         PRIMARY KEY,
    codigo              VARCHAR(20)    NOT NULL UNIQUE,
    descripcion         VARCHAR(250)   NOT NULL,
    id_partida          INTEGER        NOT NULL
                                       REFERENCES partida_arancelaria (id_partida) ON DELETE RESTRICT,
    id_pais_origen      INTEGER        NOT NULL
                                       REFERENCES pais (id_pais) ON DELETE RESTRICT,
    peso_unitario_kg    NUMERIC(12,3)  NOT NULL CHECK (peso_unitario_kg > 0),
    valor_unitario_usd  NUMERIC(14,2)  NOT NULL CHECK (valor_unitario_usd >= 0)   -- valor de referencia
);
COMMENT ON TABLE producto IS 'CatÃ¡logo de productos/mercancÃ­as con partida y paÃ­s de origen.';


-- -----------------------------------------------------------------------------
-- 6. FUNCIONARIO : Personal de la aduana.
-- -----------------------------------------------------------------------------
CREATE TABLE funcionario (
    id_funcionario   SERIAL        PRIMARY KEY,
    codigo_empleado  VARCHAR(15)   NOT NULL UNIQUE,
    nombre           VARCHAR(80)   NOT NULL,
    apellido         VARCHAR(80)   NOT NULL,
    cargo            VARCHAR(20)   NOT NULL
                                   CHECK (cargo IN ('INSPECTOR', 'LIQUIDADOR', 'SUPERVISOR',
                                                    'JEFE_BODEGA', 'ADMINISTRADOR')),
    email            VARCHAR(120)  NOT NULL UNIQUE
                                   CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    id_supervisor    INTEGER
                                   REFERENCES funcionario (id_funcionario) ON DELETE SET NULL,
    fecha_ingreso    DATE          NOT NULL DEFAULT CURRENT_DATE,
    activo           BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_funcionario_no_auto_supervisor CHECK (id_supervisor IS NULL OR id_supervisor <> id_funcionario)
);
COMMENT ON TABLE  funcionario               IS 'Funcionarios de aduana con relaciÃ³n recursiva de supervisiÃ³n.';
COMMENT ON COLUMN funcionario.id_supervisor IS 'RelaciÃ³n recursiva: id del funcionario supervisor a cargo.';


-- -----------------------------------------------------------------------------

COMMIT;

