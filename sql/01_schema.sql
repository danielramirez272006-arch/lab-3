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
-- 7. DECLARACION : DeclaraciÃ³n Ãšnica Aduanera (DUA / DUCA).
-- -----------------------------------------------------------------------------
CREATE TABLE declaracion (
    id_declaracion          SERIAL         PRIMARY KEY,
    numero_declaracion      VARCHAR(20)    NOT NULL UNIQUE,
    fecha_declaracion       DATE           NOT NULL DEFAULT CURRENT_DATE,
    id_importador           INTEGER        NOT NULL
                                           REFERENCES importador (id_importador) ON DELETE RESTRICT,
    id_agente               INTEGER        NOT NULL
                                           REFERENCES agente_aduanal (id_agente) ON DELETE RESTRICT,
    id_pais_procedencia     INTEGER        NOT NULL
                                           REFERENCES pais (id_pais) ON DELETE RESTRICT,
    id_funcionario_revisor  INTEGER
                                           REFERENCES funcionario (id_funcionario) ON DELETE RESTRICT,
    regimen                 VARCHAR(25)    NOT NULL DEFAULT 'IMPORTACION_DEFINITIVA'
                                           CHECK (regimen IN ('IMPORTACION_DEFINITIVA', 'IMPORTACION_TEMPORAL',
                                                              'EXPORTACION', 'TRANSITO', 'DEPOSITO')),
    tipo_transporte         VARCHAR(10)    NOT NULL
                                           CHECK (tipo_transporte IN ('MARITIMO', 'AEREO', 'TERRESTRE')),
    valor_fob               NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (valor_fob    >= 0),
    valor_flete             NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (valor_flete  >= 0),
    valor_seguro            NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (valor_seguro >= 0),
    -- CIF = FOB + Flete + Seguro (columna calculada, siempre consistente)
    valor_cif               NUMERIC(14,2)  GENERATED ALWAYS AS (valor_fob + valor_flete + valor_seguro) STORED,
    estado                  VARCHAR(15)    NOT NULL DEFAULT 'REGISTRADA'
                                           CHECK (estado IN ('REGISTRADA', 'EN_REVISION', 'INSPECCION',
                                                             'LIQUIDADA', 'LEVANTE', 'RECHAZADA', 'ANULADA')),
    fecha_registro          TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE  declaracion           IS 'Declaraciones aduaneras (DUA/DUCA). Montos en USD.';
COMMENT ON COLUMN declaracion.estado    IS 'LEVANTE = mercancÃ­a liberada/autorizada para retiro.';


-- -----------------------------------------------------------------------------
-- 8. DETALLE_DECLARACION : LÃ­neas de la declaraciÃ³n.
--    LLAVE PRIMARIA COMPUESTA (id_declaracion, id_producto).
-- -----------------------------------------------------------------------------
CREATE TABLE detalle_declaracion (
    id_declaracion   INTEGER        NOT NULL
                                    REFERENCES declaracion (id_declaracion) ON DELETE CASCADE,
    id_producto      INTEGER        NOT NULL
                                    REFERENCES producto (id_producto) ON DELETE RESTRICT,
    cantidad         NUMERIC(14,3)  NOT NULL CHECK (cantidad > 0),
    valor_unitario   NUMERIC(14,2)  NOT NULL CHECK (valor_unitario >= 0),   -- valor FOB declarado (USD)
    peso_bruto_kg    NUMERIC(14,3)  NOT NULL CHECK (peso_bruto_kg > 0),
    subtotal_fob     NUMERIC(16,2)  GENERATED ALWAYS AS (cantidad * valor_unitario) STORED,
    CONSTRAINT pk_detalle_declaracion PRIMARY KEY (id_declaracion, id_producto)
);
COMMENT ON TABLE detalle_declaracion IS 'Detalle de productos por declaraciÃ³n (PK compuesta).';


-- -----------------------------------------------------------------------------
-- 9. LIQUIDACION_ARANCEL : CÃ¡lculo de tributos. RELACIÃ“N 1:1 con declaraciÃ³n
--    (garantizada por UNIQUE NOT NULL sobre id_declaracion).
-- -----------------------------------------------------------------------------
CREATE TABLE liquidacion_arancel (
    id_liquidacion             SERIAL         PRIMARY KEY,
    numero_liquidacion         VARCHAR(20)    NOT NULL UNIQUE,
    id_declaracion             INTEGER        NOT NULL UNIQUE                -- <- 1:1
                                              REFERENCES declaracion (id_declaracion) ON DELETE CASCADE,
    id_funcionario_liquidador  INTEGER        NOT NULL
                                              REFERENCES funcionario (id_funcionario) ON DELETE RESTRICT,
    fecha_liquidacion          DATE           NOT NULL DEFAULT CURRENT_DATE,
    base_imponible             NUMERIC(14,2)  NOT NULL CHECK (base_imponible >= 0),  -- normalmente = CIF
    monto_dai                  NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (monto_dai   >= 0),
    monto_iva                  NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (monto_iva   >= 0),
    monto_otros                NUMERIC(14,2)  NOT NULL DEFAULT 0 CHECK (monto_otros >= 0),
    total_pagar                NUMERIC(14,2)  GENERATED ALWAYS AS (monto_dai + monto_iva + monto_otros) STORED,
    estado_pago                VARCHAR(10)    NOT NULL DEFAULT 'PENDIENTE'
                                              CHECK (estado_pago IN ('PENDIENTE', 'PAGADO', 'EXONERADO', 'ANULADO')),
    fecha_pago                 DATE,
    CONSTRAINT chk_liq_pago_fecha    CHECK (estado_pago <> 'PAGADO' OR fecha_pago IS NOT NULL),
    CONSTRAINT chk_liq_pago_orden    CHECK (fecha_pago IS NULL OR fecha_pago >= fecha_liquidacion)
);
COMMENT ON TABLE liquidacion_arancel IS 'LiquidaciÃ³n de tributos (DAI, IVA/ISV). RelaciÃ³n 1:1 con declaracion.';


-- -----------------------------------------------------------------------------
-- 10. CONTENEDOR : Unidades de carga asociadas a una declaraciÃ³n.
-- -----------------------------------------------------------------------------
CREATE TABLE contenedor (
    id_contenedor      SERIAL         PRIMARY KEY,
    numero_contenedor  VARCHAR(11)    NOT NULL UNIQUE
                                      CHECK (numero_contenedor ~ '^[A-Z]{4}[0-9]{7}$'),   -- formato ISO 6346
    id_declaracion     INTEGER        NOT NULL
                                      REFERENCES declaracion (id_declaracion) ON DELETE CASCADE,
    tipo               VARCHAR(6)     NOT NULL DEFAULT '40GP'
                                      CHECK (tipo IN ('20GP', '40GP', '40HC', '20RF', '40RF', 'OTRO')),
    peso_bruto_kg      NUMERIC(12,2)  NOT NULL CHECK (peso_bruto_kg > 0),
    numero_marchamo    VARCHAR(20)    UNIQUE,                                           -- sello/precinto
    estado             VARCHAR(15)    NOT NULL DEFAULT 'EN_PUERTO'
                                      CHECK (estado IN ('EN_TRANSITO', 'EN_PUERTO', 'EN_BODEGA',
                                                        'INSPECCIONADO', 'LIBERADO', 'RETENIDO')),
    fecha_arribo       DATE
);
COMMENT ON TABLE contenedor IS 'Contenedores/unidades de transporte de cada declaraciÃ³n.';


-- -----------------------------------------------------------------------------

COMMIT;

