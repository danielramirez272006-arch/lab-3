-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 01_schema.sql
--  Motor   : PostgreSQL 13+ (probado con sintaxis estándar de PG 16)
--  Propósito: Crear las 14 tablas relacionales con todas sus restricciones
--             de integridad (PK, FK, UNIQUE, CHECK, DEFAULT).
--
--  Política de borrado (ON DELETE):
--    * RESTRICT -> Catálogos / entidades maestras (país, importador, agente,
--                  partida, producto, funcionario, bodega). No se pueden
--                  eliminar si existen registros que dependen de ellos.
--    * CASCADE  -> Entidades "hijas" que no tienen sentido sin su padre
--                  (detalle, liquidación, contenedor, inspección y
--                  movimientos de inventario).
--
--  Orden de creación: de tablas independientes a tablas dependientes.
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
-- 1. PAIS : Catálogo de países (origen / procedencia / domicilio).
-- -----------------------------------------------------------------------------
CREATE TABLE pais (
    id_pais        SERIAL        PRIMARY KEY,
    codigo_iso     CHAR(2)       NOT NULL UNIQUE
                                 CHECK (codigo_iso ~ '^[A-Z]{2}$'),   -- ISO 3166-1 alfa-2
    nombre         VARCHAR(100)  NOT NULL UNIQUE
);
COMMENT ON TABLE pais IS 'Catálogo de países según ISO 3166-1.';


-- -----------------------------------------------------------------------------
-- 2. IMPORTADOR : Persona jurídica/natural que importa mercancías.
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
-- 4. PARTIDA_ARANCELARIA : Clasificación del Sistema Armonizado (SA/SAC).
-- -----------------------------------------------------------------------------
CREATE TABLE partida_arancelaria (
    id_partida     SERIAL         PRIMARY KEY,
    codigo_sa      VARCHAR(12)    NOT NULL UNIQUE
                                  CHECK (codigo_sa ~ '^[0-9]{4}(\.[0-9]{2}){1,3}$'),  -- ej. 8471.30.00
    descripcion    VARCHAR(250)   NOT NULL,
    tasa_dai       NUMERIC(5,2)   NOT NULL DEFAULT 0
                                  CHECK (tasa_dai BETWEEN 0 AND 100),  -- Derecho Arancelario a la Importación (%)
    tasa_iva       NUMERIC(5,2)   NOT NULL DEFAULT 15
                                  CHECK (tasa_iva BETWEEN 0 AND 100),  -- Impuesto sobre ventas ISV/IVA (%)
    unidad_medida  VARCHAR(20)    NOT NULL DEFAULT 'UNIDAD'
                                  CHECK (unidad_medida IN ('UNIDAD', 'KG', 'LITRO', 'METRO', 'PAR', 'DOCENA', 'CAJA'))
);
COMMENT ON TABLE partida_arancelaria IS 'Partidas arancelarias del Sistema Armonizado con sus tasas.';


-- -----------------------------------------------------------------------------
-- 5. PRODUCTO : Mercancía catalogada y clasificada en una partida.
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
COMMENT ON TABLE producto IS 'Catálogo de productos/mercancías con partida y país de origen.';


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
COMMENT ON TABLE  funcionario               IS 'Funcionarios de aduana con relación recursiva de supervisión.';
COMMENT ON COLUMN funcionario.id_supervisor IS 'Relación recursiva: id del funcionario supervisor a cargo.';


-- -----------------------------------------------------------------------------
-- 7. DECLARACION : Declaración Única Aduanera (DUA / DUCA).
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
COMMENT ON COLUMN declaracion.estado    IS 'LEVANTE = mercancía liberada/autorizada para retiro.';


-- -----------------------------------------------------------------------------
-- 8. DETALLE_DECLARACION : Líneas de la declaración.
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
COMMENT ON TABLE detalle_declaracion IS 'Detalle de productos por declaración (PK compuesta).';


-- -----------------------------------------------------------------------------
-- 9. LIQUIDACION_ARANCEL : Cálculo de tributos. RELACIÓN 1:1 con declaración
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
COMMENT ON TABLE liquidacion_arancel IS 'Liquidación de tributos (DAI, IVA/ISV). Relación 1:1 con declaracion.';


-- -----------------------------------------------------------------------------
-- 10. CONTENEDOR : Unidades de carga asociadas a una declaración.
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
COMMENT ON TABLE contenedor IS 'Contenedores/unidades de transporte de cada declaración.';


-- -----------------------------------------------------------------------------
-- 11. BODEGA : Almacenes fiscales / depósitos temporales.
-- -----------------------------------------------------------------------------
CREATE TABLE bodega (
    id_bodega                   SERIAL         PRIMARY KEY,
    codigo                      VARCHAR(15)    NOT NULL UNIQUE,
    nombre                      VARCHAR(120)   NOT NULL,
    ubicacion                   VARCHAR(150)   NOT NULL,
    tipo                        VARCHAR(20)    NOT NULL
                                               CHECK (tipo IN ('FISCAL', 'DEPOSITO_TEMPORAL', 'ZONA_LIBRE', 'REFRIGERADA')),
    capacidad_m3                NUMERIC(12,2)  NOT NULL CHECK (capacidad_m3 > 0),
    id_funcionario_responsable  INTEGER        NOT NULL
                                               REFERENCES funcionario (id_funcionario) ON DELETE RESTRICT,
    activa                      BOOLEAN        NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE bodega IS 'Bodegas/almacenes bajo control aduanero.';


-- -----------------------------------------------------------------------------
-- 12. INVENTARIO_BODEGA : Existencias de un producto, de una declaración,
--     en una bodega concreta.
-- -----------------------------------------------------------------------------
CREATE TABLE inventario_bodega (
    id_inventario               SERIAL         UNIQUE,
    id_bodega                   INTEGER        NOT NULL
                                               REFERENCES bodega (id_bodega) ON DELETE RESTRICT,
    id_producto                 INTEGER        NOT NULL
                                               REFERENCES producto (id_producto) ON DELETE RESTRICT,
    id_declaracion              INTEGER        NOT NULL
                                               REFERENCES declaracion (id_declaracion) ON DELETE RESTRICT,
    cantidad_actual             NUMERIC(14,3)  NOT NULL DEFAULT 0 CHECK (cantidad_actual >= 0),
    ubicacion_rack              VARCHAR(20),
    fecha_ingreso               DATE           NOT NULL DEFAULT CURRENT_DATE,
    fecha_ultima_actualizacion  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inventario_bodega PRIMARY KEY (id_bodega, id_producto, id_declaracion)
);
COMMENT ON TABLE inventario_bodega IS 'Existencias por bodega, producto y declaración (tabla intermedia N:M con PK compuesta).';


-- -----------------------------------------------------------------------------
-- 13. MOVIMIENTO_INVENTARIO : Kardex de entradas/salidas/traslados/ajustes.
-- -----------------------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento      SERIAL         PRIMARY KEY,
    id_inventario      INTEGER        NOT NULL
                                      REFERENCES inventario_bodega (id_inventario) ON DELETE CASCADE,
    tipo_movimiento    VARCHAR(10)    NOT NULL
                                      CHECK (tipo_movimiento IN ('INGRESO', 'SALIDA', 'TRASLADO', 'AJUSTE')),
    cantidad           NUMERIC(14,3)  NOT NULL CHECK (cantidad > 0),
    fecha_movimiento   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_funcionario     INTEGER        NOT NULL
                                      REFERENCES funcionario (id_funcionario) ON DELETE RESTRICT,
    id_bodega_destino  INTEGER
                                      REFERENCES bodega (id_bodega) ON DELETE RESTRICT,
    observacion        VARCHAR(250),
    -- Un TRASLADO siempre debe indicar la bodega destino; los demás no.
    CONSTRAINT chk_mov_traslado CHECK (
        (tipo_movimiento =  'TRASLADO' AND id_bodega_destino IS NOT NULL) OR
        (tipo_movimiento <> 'TRASLADO' AND id_bodega_destino IS NULL)
    )
);
COMMENT ON TABLE movimiento_inventario IS 'Kardex: historial de movimientos de inventario.';


-- -----------------------------------------------------------------------------
-- 14. INSPECCION : Revisión documental / física / no intrusiva (rayos X).
-- -----------------------------------------------------------------------------
CREATE TABLE inspeccion (
    id_inspeccion     SERIAL        PRIMARY KEY,
    id_declaracion    INTEGER       NOT NULL
                                    REFERENCES declaracion (id_declaracion) ON DELETE CASCADE,
    id_contenedor     INTEGER
                                    REFERENCES contenedor (id_contenedor) ON DELETE CASCADE,
    id_funcionario    INTEGER       NOT NULL
                                    REFERENCES funcionario (id_funcionario) ON DELETE RESTRICT,
    fecha_inspeccion  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    canal             VARCHAR(10)   NOT NULL
                                    CHECK (canal IN ('VERDE', 'AMARILLO', 'ROJO')),   -- canal de selectividad
    tipo              VARCHAR(15)   NOT NULL
                                    CHECK (tipo IN ('DOCUMENTAL', 'FISICA', 'NO_INTRUSIVA')),
    resultado         VARCHAR(20)   NOT NULL DEFAULT 'PENDIENTE'
                                    CHECK (resultado IN ('PENDIENTE', 'CONFORME', 'CON_OBSERVACIONES', 'NO_CONFORME')),
    observaciones     TEXT
);
COMMENT ON TABLE inspeccion IS 'Inspecciones aduaneras por canal de selectividad.';


-- -----------------------------------------------------------------------------
-- ÍNDICES sobre llaves foráneas y columnas de filtrado frecuente
-- (PostgreSQL NO crea índices automáticamente para las FK).
-- -----------------------------------------------------------------------------
CREATE INDEX idx_importador_pais         ON importador            (id_pais);
CREATE INDEX idx_producto_partida        ON producto              (id_partida);
CREATE INDEX idx_producto_pais           ON producto              (id_pais_origen);
CREATE INDEX idx_declaracion_importador  ON declaracion           (id_importador);
CREATE INDEX idx_declaracion_agente      ON declaracion           (id_agente);
CREATE INDEX idx_declaracion_estado      ON declaracion           (estado);
CREATE INDEX idx_declaracion_fecha       ON declaracion           (fecha_declaracion);
CREATE INDEX idx_detalle_producto        ON detalle_declaracion   (id_producto);
CREATE INDEX idx_liquidacion_func        ON liquidacion_arancel   (id_funcionario_liquidador);
CREATE INDEX idx_contenedor_declaracion  ON contenedor            (id_declaracion);
CREATE INDEX idx_bodega_responsable      ON bodega                (id_funcionario_responsable);
CREATE INDEX idx_inventario_producto     ON inventario_bodega     (id_producto);
CREATE INDEX idx_inventario_declaracion  ON inventario_bodega     (id_declaracion);
CREATE INDEX idx_movimiento_inventario   ON movimiento_inventario (id_inventario);
CREATE INDEX idx_movimiento_funcionario  ON movimiento_inventario (id_funcionario);
CREATE INDEX idx_inspeccion_declaracion  ON inspeccion            (id_declaracion);
CREATE INDEX idx_inspeccion_contenedor   ON inspeccion            (id_contenedor);
CREATE INDEX idx_inspeccion_funcionario  ON inspeccion            (id_funcionario);
CREATE INDEX idx_funcionario_supervisor   ON funcionario           (id_supervisor);

COMMIT;
