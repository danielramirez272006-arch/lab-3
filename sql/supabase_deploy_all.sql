-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO (SUPABASE CONSOLIDATED)
--  Copiar todo este contenido y pegarlo directamente en el SQL Editor de Supabase
-- =============================================================================


-- ==================== ARCHIVO: 01_schema.sql ====================
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


-- ==================== ARCHIVO: 02_seed_data.sql ====================
-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 02_seed_data.sql
--  Propósito: Poblado de datos DML con AL MENOS 15 REGISTROS por cada una
--             de las 14 tablas (cumplimiento 100% de la rúbrica).
--  Integridad: No viola restricciones CHECK, UNIQUE, FK ni relaciones 1:1.
-- =============================================================================

BEGIN;

TRUNCATE inspeccion, movimiento_inventario, inventario_bodega, bodega, contenedor,
         liquidacion_arancel, detalle_declaracion, declaracion, funcionario, producto,
         partida_arancelaria, agente_aduanal, importador, pais
RESTART IDENTITY CASCADE;

-- -----------------------------------------------------------------------------
-- 1. PAIS (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO pais (codigo_iso, nombre) VALUES
 ('HN', 'Honduras'),        -- 1
 ('US', 'Estados Unidos'),  -- 2
 ('CN', 'China'),           -- 3
 ('MX', 'México'),          -- 4
 ('DE', 'Alemania'),        -- 5
 ('GT', 'Guatemala'),       -- 6
 ('JP', 'Japón'),           -- 7
 ('CO', 'Colombia'),        -- 8
 ('ES', 'España'),          -- 9
 ('PA', 'Panamá'),          -- 10
 ('CR', 'Costa Rica'),      -- 11
 ('SV', 'El Salvador'),     -- 12
 ('NI', 'Nicaragua'),       -- 13
 ('BR', 'Brasil'),          -- 14
 ('KR', 'Corea del Sur'),   -- 15
 ('IT', 'Italia');          -- 16

-- -----------------------------------------------------------------------------
-- 2. IMPORTADOR (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO importador (identificacion_fiscal, razon_social, direccion, telefono, email, id_pais, estado, fecha_registro) VALUES
 ('08019001234567', 'Distribuidora Centroamericana S.A.',   'Blvd. Suyapa, Tegucigalpa',        '+504 2232-1000', 'compras@dicensa.hn',     1, 'ACTIVO',     '2020-03-15'),
 ('08019005551234', 'Tecnología Global de Honduras S.A.',   'Col. Palmira, Tegucigalpa',        '+504 2239-4500', 'import@tecglobal.hn',    1, 'ACTIVO',     '2021-07-01'),
 ('05019002223334', 'Agroindustrias del Valle S. de R.L.',  'Carretera a Puerto Cortés km 5',   '+504 2553-7788', 'logistica@agrovalle.hn', 1, 'ACTIVO',     '2019-11-20'),
 ('08019007778889', 'Farmacéutica Nacional S.A.',           'Zona Industrial Amarateca',        '+504 2224-9090', 'aduanas@farmanal.hn',    1, 'ACTIVO',     '2018-05-10'),
 ('05019009990001', 'Textiles San Pedro S.A.',              'Barrio Guamilito, San Pedro Sula', '+504 2550-1122', 'info@textilessps.hn',    1, 'SUSPENDIDO', '2022-02-28'),
 ('08011990123456', 'Importadora Comercial del Sur',       'Choluteca Centro',                 '+504 2782-3344', 'sur@comercial.hn',      1, 'ACTIVO',     '2021-01-15'),
 ('05011985654321', 'Maquinaria Pesada de Cortés S.A.',     'Puerto Cortés, Zona Portuaria',    '+504 2665-9900', 'ventas@maquicortes.hn',  1, 'ACTIVO',     '2017-09-12'),
 ('08011995778899', 'Alimentos Balanceados Hondureños',     'Zambrano, Fco Morazán',            '+504 2764-5500', 'import@albahsa.hn',      1, 'ACTIVO',     '2016-04-18'),
 ('05011998443322', 'Auto Partes y Motores Express',        'Av. Circunvalación, SPS',          '+504 2557-8899', 'repuestos@autopartes.hn',1, 'ACTIVO',     '2022-08-30'),
 ('08012001112233', 'Inversiones Químicas del Atlántico',   'El Hatillo, Tegucigalpa',          '+504 2211-0022', 'quimica@inveratla.hn',   1, 'ACTIVO',     '2020-10-05'),
 ('05012005445566', 'Ferretería Industrial Metropolitana', 'Col. Prado Alto, San Pedro Sula',   '+504 2556-7788', 'compras@ferremetro.hn',  1, 'ACTIVO',     '2015-12-01'),
 ('08012008778899', 'Distribuidora Médica Hospitalaria',   'Col. Tepeyac, Tegucigalpa',        '+504 2235-6677', 'logistica@dimeho.hn',    1, 'ACTIVO',     '2019-06-25'),
 ('01011992334455', 'Consorcio Pesquero de La Ceiba',      'Barrio La Isla, La Ceiba',         '+504 2440-2211', 'pesca@ceibamar.hn',      1, 'ACTIVO',     '2018-03-14'),
 ('03011988112233', 'Cafés Finos de Comayagua S.A.',       'Barrio Torondón, Comayagua',       '+504 2772-1199', 'export@cafefino.hn',     1, 'ACTIVO',     '2017-11-08'),
 ('05012010998877', 'Electrodomésticos y Hogar S.A.',      'Bulevar del Norte, SPS',           '+504 2566-4433', 'hogar@electrosps.hn',    1, 'INACTIVO',   '2023-01-20'),
 ('08012015667788', 'Compañía Papelera Central S.A.',       'Anillo Periférico, Tegucigalpa',   '+504 2245-8800', 'aduanas@papelerac.hn',   1, 'ACTIVO',     '2021-11-15');

-- -----------------------------------------------------------------------------
-- 3. AGENTE_ADUANAL (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO agente_aduanal (numero_licencia, nombre, apellido, email, telefono, fecha_emision_licencia, fecha_vencimiento_licencia, estado) VALUES
 ('AA-2019-001', 'Roberto',   'Fúnez',      'rfunez@agentes.hn',      '+504 9988-1111', '2019-01-10', '2027-01-10', 'ACTIVO'),
 ('AA-2020-014', 'Patricia',  'Velásquez',  'pvelasquez@agentes.hn',  '+504 9988-2222', '2020-06-01', '2026-12-31', 'ACTIVO'),
 ('AA-2021-027', 'Fernando',  'Ordóñez',    'fordonez@agentes.hn',    '+504 9988-3333', '2021-03-15', '2029-03-15', 'ACTIVO'),
 ('AA-2016-005', 'Claudia',   'Rivera',     'crivera@agentes.hn',     '+504 9988-4444', '2016-02-01', '2026-02-01', 'SUSPENDIDO'),
 ('AA-2018-040', 'Manuel',    'Gómez',      'mgomez@agentes.hn',      '+504 9988-5555', '2018-05-12', '2028-05-12', 'ACTIVO'),
 ('AA-2017-012', 'Elena',     'Castro',     'ecastro@agentes.hn',     '+504 9988-6666', '2017-08-20', '2027-08-20', 'ACTIVO'),
 ('AA-2022-055', 'Héctor',    'Mendoza',    'hmendoza@agentes.hn',    '+504 9988-7777', '2022-01-18', '2030-01-18', 'ACTIVO'),
 ('AA-2020-033', 'Silvia',    'Torres',     'storres@agentes.hn',     '+504 9988-8888', '2020-11-04', '2028-11-04', 'ACTIVO'),
 ('AA-2015-008', 'Ricardo',   'Aguilar',    'raguilar@agentes.hn',    '+504 9988-9999', '2015-09-30', '2027-09-30', 'ACTIVO'),
 ('AA-2023-061', 'Gabriela',  'Ponce',      'gponce@agentes.hn',      '+504 9911-2233', '2023-04-15', '2031-04-15', 'ACTIVO'),
 ('AA-2019-022', 'Oscar',     'Valladares', 'ovalladares@agentes.hn', '+504 9922-3344', '2019-07-22', '2027-07-22', 'ACTIVO'),
 ('AA-2021-048', 'Norma',     'Lagos',      'nlagos@agentes.hn',      '+504 9933-4455', '2021-10-10', '2029-10-10', 'ACTIVO'),
 ('AA-2018-019', 'Víctor',    'Reyes',      'vreyes@agentes.hn',      '+504 9944-5566', '2018-03-05', '2026-11-30', 'ACTIVO'),
 ('AA-2022-070', 'Karla',     'Espinoza',   'kespinoza@agentes.hn',   '+504 9955-6677', '2022-06-14', '2030-06-14', 'ACTIVO'),
 ('AA-2016-015', 'Danilo',    'Montoya',    'dmontoya@agentes.hn',    '+504 9966-7788', '2016-12-01', '2024-12-01', 'INACTIVO'),
 ('AA-2024-080', 'Andrea',    'Solórzano',  'asolorzano@agentes.hn',  '+504 9977-8899', '2024-02-01', '2032-02-01', 'ACTIVO');

-- -----------------------------------------------------------------------------
-- 4. PARTIDA_ARANCELARIA (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO partida_arancelaria (codigo_sa, descripcion, tasa_dai, tasa_iva, unidad_medida) VALUES
 ('8471.30.00', 'Máquinas automáticas portátiles para procesamiento de datos (laptops)',  0, 15, 'UNIDAD'), -- 1
 ('8517.13.00', 'Teléfonos inteligentes (smartphones)',                                   0, 15, 'UNIDAD'), -- 2
 ('3004.90.99', 'Medicamentos dosificados para uso humano',                               0,  0, 'CAJA'),   -- 3
 ('8703.23.90', 'Vehículos de turismo de cilindrada 1500 a 3000 cc',                      15, 15, 'UNIDAD'), -- 4
 ('6109.10.00', 'Camisetas de punto de algodón',                                          15, 15, 'UNIDAD'), -- 5
 ('8429.52.00', 'Excavadoras con superestructura giratoria de 360°',                      0, 15, 'UNIDAD'), -- 6
 ('3102.10.00', 'Urea, incluso en disolución acuosa (fertilizante)',                      0,  0, 'KG'),     -- 7
 ('8528.72.00', 'Televisores en colores con pantalla plana',                              15, 15, 'UNIDAD'), -- 8
 ('1006.30.90', 'Arroz semiblanqueado o blanqueado',                                      10, 15, 'KG'),     -- 9
 ('0901.11.00', 'Café en grano sin tostar ni descafeinar',                                15, 15, 'KG'),     -- 10
 ('8418.10.00', 'Combinaciones de refrigerador y congelador con puertas separadas',       15, 15, 'UNIDAD'), -- 11
 ('8704.22.90', 'Vehículos automóviles para transporte de mercancías g.v.w. 5 a 20 ton',  10, 15, 'UNIDAD'), -- 12
 ('4802.56.00', 'Papel bond en hojas para fotocopiado e impresión',                       5, 15, 'KG'),     -- 13
 ('9403.20.00', 'Muebles de metal para oficina',                                          15, 15, 'UNIDAD'), -- 14
 ('8471.50.00', 'Unidades de procesamiento digital (servidores / CPU)',                    0, 15, 'UNIDAD'), -- 15
 ('2710.19.21', 'Aceites lubricantes de petróleo preparados',                             5, 15, 'LITRO');  -- 16

-- -----------------------------------------------------------------------------
-- 5. PRODUCTO (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO producto (codigo, descripcion, id_partida, id_pais_origen, peso_unitario_kg, valor_unitario_usd) VALUES
 ('PRD-0001', 'Laptop Dell Latitude 5540 Core i7',  1,  2,     2.100,    950.00), -- 1
 ('PRD-0002', 'Laptop Lenovo ThinkPad E14 Ryzen 5', 1,  3,     1.600,    720.00), -- 2
 ('PRD-0003', 'Smartphone Samsung Galaxy A55 128GB',2,  3,     0.210,    310.00), -- 3
 ('PRD-0004', 'Apple iPhone 15 128GB Medianoche',   2,  3,     0.170,    680.00), -- 4
 ('PRD-0005', 'Amoxicilina 500mg caja x 21 cápsulas',3, 4,     0.050,      3.50), -- 5
 ('PRD-0006', 'Toyota Corolla Sedán 2026 1.8L',     4,  7,  1350.000,  18500.00), -- 6
 ('PRD-0007', 'Camiseta básica de algodón 100% M',   5,  6,     0.200,      2.80), -- 7
 ('PRD-0008', 'Excavadora Hidráulica Cat 320',      6,  2, 22000.000, 185000.00), -- 8
 ('PRD-0009', 'Urea agrícola perlada saco 50 kg',   7,  3,    50.000,     28.00), -- 9
 ('PRD-0010', 'Smart TV LG 55 pulg 4K UHD WebOS',   8,  4,    17.500,    420.00), -- 10
 ('PRD-0011', 'Arroz Grano Largo Precocido Saco 25kg', 9, 2,  25.000,     14.50), -- 11
 ('PRD-0012', 'Café Especial Arábica Pergamino',   10,  1,    46.000,    180.00), -- 12
 ('PRD-0013', 'Refrigerador Inverter No Frost 380L', 11, 4,   68.000,    540.00), -- 13
 ('PRD-0014', 'Camión Isuzu Forward 10 Toneladas',  12,  7,  4500.000,  42000.00), -- 14
 ('PRD-0015', 'Servidor Rack Dell PowerEdge R660',  15,  2,    19.000,   3200.00), -- 15
 ('PRD-0016', 'Aceite Sintético para Motor 5W-30 Galón', 16, 2, 3.800,    32.00); -- 16

-- -----------------------------------------------------------------------------
-- 6. FUNCIONARIO (16 registros) con relación recursiva (id_supervisor)
-- -----------------------------------------------------------------------------
-- Primero insertamos los funcionarios jerárquicos (administradores y supervisores)
INSERT INTO funcionario (codigo_empleado, nombre, apellido, cargo, email, id_supervisor, fecha_ingreso, activo) VALUES
 ('FUN-001', 'Carlos',   'Mejía',     'ADMINISTRADOR', 'cmejia@aduanas.gob.hn',     NULL, '2014-02-01', TRUE), -- 1 (Jefe máximo)
 ('FUN-002', 'Sandra',   'Guzmán',    'SUPERVISOR',    'sguzman@aduanas.gob.hn',    1,    '2016-04-15', TRUE), -- 2
 ('FUN-003', 'Marco',    'Cáceres',   'SUPERVISOR',    'mcaceres@aduanas.gob.hn',   1,    '2015-08-20', TRUE), -- 3
 ('FUN-004', 'Jorge',    'Zelaya',    'JEFE_BODEGA',   'jzelaya@aduanas.gob.hn',    1,    '2016-09-05', TRUE), -- 4
 ('FUN-005', 'Sofía',    'Martínez',  'JEFE_BODEGA',   'smartinez@aduanas.gob.hn',  1,    '2019-11-11', TRUE), -- 5
 ('FUN-006', 'Ana',      'Rodríguez', 'INSPECTOR',     'arodriguez@aduanas.gob.hn', 2,    '2018-08-15', TRUE), -- 6
 ('FUN-007', 'Luis',     'Hernández', 'INSPECTOR',     'lhernandez@aduanas.gob.hn', 2,    '2020-01-10', TRUE), -- 7
 ('FUN-008', 'Diana',    'Barahona',  'INSPECTOR',     'dbarahona@aduanas.gob.hn',  2,    '2021-05-18', TRUE), -- 8
 ('FUN-009', 'Wilmer',   'Paz',       'INSPECTOR',     'wpaz@aduanas.gob.hn',       2,    '2022-02-01', TRUE), -- 9
 ('FUN-010', 'María',    'Castillo',  'LIQUIDADOR',    'mcastillo@aduanas.gob.hn',  3,    '2017-03-20', TRUE), -- 10
 ('FUN-011', 'Nelson',   'García',    'LIQUIDADOR',    'ngarcia@aduanas.gob.hn',    3,    '2018-06-12', TRUE), -- 11
 ('FUN-012', 'Karla',    'Flores',    'LIQUIDADOR',    'kflores@aduanas.gob.hn',    3,    '2019-09-25', TRUE), -- 12
 ('FUN-013', 'Eduardo',  'Pineda',    'LIQUIDADOR',    'epineda@aduanas.gob.hn',    3,    '2021-07-30', TRUE), -- 13
 ('FUN-014', 'Ramiro',   'López',     'INSPECTOR',     'rlopez@aduanas.gob.hn',     2,    '2023-01-15', TRUE), -- 14
 ('FUN-015', 'Carmen',   'Bueso',     'JEFE_BODEGA',   'cbueso@aduanas.gob.hn',     1,    '2020-03-10', TRUE), -- 15
 ('FUN-016', 'Felipe',   'Salinas',   'INSPECTOR',     'fsalinas@aduanas.gob.hn',   2,    '2024-01-10', FALSE);-- 16

-- -----------------------------------------------------------------------------
-- 7. DECLARACION (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO declaracion (numero_declaracion, fecha_declaracion, id_importador, id_agente, id_pais_procedencia,
                         id_funcionario_revisor, regimen, tipo_transporte, valor_fob, valor_flete, valor_seguro, estado) VALUES
 ('DUA-2026-000101', '2026-09-02',  2,  1,  2, 6,  'IMPORTACION_DEFINITIVA', 'MARITIMO',  203000.00,  4500.00, 1015.00, 'LEVANTE'),     -- 1
 ('DUA-2026-000102', '2026-09-10',  2,  2,  3, 6,  'IMPORTACION_DEFINITIVA', 'MARITIMO',  291000.00,  6800.00, 1455.00, 'LIQUIDADA'),   -- 2
 ('DUA-2026-000103', '2026-09-18',  4,  3,  4, 7,  'IMPORTACION_DEFINITIVA', 'TERRESTRE',  70000.00,  1200.00,  350.00, 'LEVANTE'),     -- 3
 ('DUA-2026-000104', '2026-09-25',  1,  1,  7, 7,  'IMPORTACION_DEFINITIVA', 'MARITIMO',  222000.00,  9600.00, 1110.00, 'INSPECCION'),  -- 4
 ('DUA-2026-000105', '2026-10-05',  3,  2,  2, 8,  'IMPORTACION_TEMPORAL',   'MARITIMO',  370000.00, 12000.00, 1850.00, 'EN_REVISION'), -- 5
 ('DUA-2026-000106', '2026-10-12',  3,  3,  3, 8,  'IMPORTACION_DEFINITIVA', 'MARITIMO',   28000.00,  3500.00,  140.00, 'REGISTRADA'),  -- 6
 ('DUA-2026-000107', '2026-10-15',  1,  2,  4, 6,  'IMPORTACION_DEFINITIVA', 'TERRESTRE', 126000.00,  2100.00,  630.00, 'LIQUIDADA'),   -- 7
 ('DUA-2026-000108', '2026-10-20',  5,  3,  6, 9,  'IMPORTACION_DEFINITIVA', 'TERRESTRE',  28000.00,   600.00,  140.00, 'RECHAZADA'),   -- 8
 ('DUA-2026-000109', '2026-10-21',  6,  5,  2, 6,  'IMPORTACION_DEFINITIVA', 'MARITIMO',   58000.00,  2800.00,  290.00, 'LEVANTE'),     -- 9
 ('DUA-2026-000110', '2026-10-22',  7,  6,  7, 7,  'IMPORTACION_DEFINITIVA', 'MARITIMO',  210000.00,  8500.00, 1050.00, 'INSPECCION'),  -- 10
 ('DUA-2026-000111', '2026-10-22',  8,  7,  3, 8,  'IMPORTACION_DEFINITIVA', 'MARITIMO',   56000.00,  4000.00,  280.00, 'REGISTRADA'),  -- 11
 ('DUA-2026-000112', '2026-10-23',  9,  8,  2, 9,  'IMPORTACION_DEFINITIVA', 'AEREO',      32000.00,  3100.00,  320.00, 'EN_REVISION'), -- 12
 ('DUA-2026-000113', '2026-10-23', 10,  9,  2, 6,  'IMPORTACION_DEFINITIVA', 'MARITIMO',   64000.00,  3800.00,  320.00, 'LIQUIDADA'),   -- 13
 ('DUA-2026-000114', '2026-10-23', 11, 10,  4, 7,  'IMPORTACION_DEFINITIVA', 'TERRESTRE',  81000.00,  1900.00,  405.00, 'REGISTRADA'),  -- 14
 ('DUA-2026-000115', '2026-10-23', 12, 11,  4, 8,  'IMPORTACION_DEFINITIVA', 'AEREO',      45000.00,  2500.00,  225.00, 'LIQUIDADA'),   -- 15
 ('DUA-2026-000116', '2026-10-23', 14, 12,  1, 9,  'EXPORTACION',            'MARITIMO',   90000.00,  4200.00,  450.00, 'LEVANTE');     -- 16

-- -----------------------------------------------------------------------------
-- 8. DETALLE_DECLARACION (20 registros, PK compuesta id_declaracion + id_producto)
-- -----------------------------------------------------------------------------
INSERT INTO detalle_declaracion (id_declaracion, id_producto, cantidad, valor_unitario, peso_bruto_kg) VALUES
 ( 1,  1,   100,    950.00,   231.000), -- 1
 ( 1,  2,   150,    720.00,   264.000), -- 2
 ( 2,  3,   500,    310.00,   125.000), -- 3
 ( 2,  4,   200,    680.00,    45.000), -- 4
 ( 3,  5, 20000,      3.50,  1100.000), -- 5
 ( 4,  6,    12,  18500.00, 16200.000), -- 6
 ( 5,  8,     2, 185000.00, 44000.000), -- 7
 ( 6,  9,  1000,     28.00, 50250.000), -- 8
 ( 7, 10,   300,    420.00,  5900.000), -- 9
 ( 8,  7, 10000,      2.80,  2150.000), -- 10
 ( 9, 11,  4000,     14.50, 100500.000),-- 11
 (10, 14,     5,  42000.00, 22600.000), -- 12
 (11,  9,  2000,     28.00, 100500.000),-- 13
 (12, 15,    10,   3200.00,   210.000), -- 14
 (13, 16,  2000,     32.00,  7900.000), -- 15
 (14, 13,   150,    540.00, 10300.000), -- 16
 (15,  5, 12857.143,  3.50,   750.000), -- 17
 (16, 12,   500,    180.00, 23100.000), -- 18
 ( 2,  1,    20,    950.00,    46.000), -- 19
 ( 7,  8,     1, 185000.00, 22000.000); -- 20

-- -----------------------------------------------------------------------------
-- 9. LIQUIDACION_ARANCEL (16 registros, relación 1:1 con cada declaración)
-- -----------------------------------------------------------------------------
INSERT INTO liquidacion_arancel (numero_liquidacion, id_declaracion, id_funcionario_liquidador, fecha_liquidacion,
                                 base_imponible, monto_dai, monto_iva, monto_otros, estado_pago, fecha_pago)
VALUES
 ('LIQ-2026-000101',  1, 10, '2026-09-05', 208515.00,     0.00, 31277.25,   50.00, 'PAGADO',    '2026-09-07'),
 ('LIQ-2026-000102',  2, 10, '2026-09-13', 299255.00,     0.00, 44888.25,   50.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000103',  3, 11, '2026-09-21',  71550.00,     0.00,      0.00,    0.00, 'EXONERADO', NULL),
 ('LIQ-2026-000104',  4, 11, '2026-09-28', 232710.00, 34906.50, 40142.48,   75.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000105',  5, 12, '2026-10-08', 383850.00,     0.00, 57577.50,  100.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000106',  6, 12, '2026-10-15',  31640.00,     0.00,      0.00,    0.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000107',  7, 10, '2026-10-18', 128730.00, 19309.50, 22205.93,   50.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000108',  8, 13, '2026-10-21',  28740.00,  4311.00,  4957.65,    0.00, 'ANULADO',   NULL),
 ('LIQ-2026-000109',  9, 10, '2026-10-22',  61090.00,  6109.00, 10079.85,   25.00, 'PAGADO',    '2026-10-23'),
 ('LIQ-2026-000110', 10, 11, '2026-10-23', 219550.00, 21955.00, 36225.75,   80.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000111', 11, 12, '2026-10-23',  60280.00,     0.00,      0.00,    0.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000112', 12, 13, '2026-10-23',  35420.00,     0.00,  5313.00,   40.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000113', 13, 10, '2026-10-23',  68120.00,  3406.00, 10728.90,   30.00, 'PAGADO',    '2026-10-23'),
 ('LIQ-2026-000114', 14, 11, '2026-10-23',  83305.00, 12495.75, 14370.11,   50.00, 'PENDIENTE', NULL),
 ('LIQ-2026-000115', 15, 12, '2026-10-23',  47725.00,     0.00,      0.00,    0.00, 'PAGADO',    '2026-10-23'),
 ('LIQ-2026-000116', 16, 13, '2026-10-23',  94650.00,     0.00,      0.00,    0.00, 'EXONERADO', NULL);

-- -----------------------------------------------------------------------------
-- 10. CONTENEDOR (16 registros, formato ISO 6346: 4 letras + 7 dígitos)
-- -----------------------------------------------------------------------------
INSERT INTO contenedor (numero_contenedor, id_declaracion, tipo, peso_bruto_kg, numero_marchamo, estado, fecha_arribo) VALUES
 ('MSCU1234565',  1, '40HC',  2850.00, 'MR-500101', 'LIBERADO',      '2026-09-01'), -- 1
 ('MAEU7654321',  2, '40GP',  1950.00, 'MR-500102', 'EN_BODEGA',     '2026-09-09'), -- 2
 ('CMAU2468101',  2, '20GP',  1320.00, 'MR-500103', 'EN_BODEGA',     '2026-09-09'), -- 3
 ('ONEU1357913',  4, '40HC', 12400.00, 'MR-500104', 'RETENIDO',      '2026-09-24'), -- 4
 ('ONEU1122334',  4, '40HC', 11900.00, 'MR-500105', 'RETENIDO',      '2026-09-24'), -- 5
 ('HLCU5566778',  5, 'OTRO', 48500.00, 'MR-500106', 'EN_PUERTO',     '2026-10-04'), -- 6
 ('COSU9988776',  6, '40GP', 27100.00, 'MR-500107', 'EN_TRANSITO',   NULL),         -- 7
 ('COSU9988777',  6, '40GP', 27050.00, 'MR-500108', 'EN_TRANSITO',   NULL),         -- 8
 ('TRLU4455667',  3, '40RF',  4300.00, 'MR-500109', 'LIBERADO',      '2026-09-17'), -- 9
 ('TRLU7788990',  7, '40GP',  9800.00, 'MR-500110', 'EN_BODEGA',     '2026-10-14'), -- 10
 ('TRLU3344556',  8, '40GP',  6150.00, 'MR-500111', 'RETENIDO',      '2026-10-19'), -- 11
 ('MSCU9876543',  9, '40HC', 26500.00, 'MR-500112', 'LIBERADO',      '2026-10-20'), -- 12
 ('MAEU1239874', 10, 'OTRO', 23000.00, 'MR-500113', 'INSPECCIONADO', '2026-10-21'), -- 13
 ('SUDU5432109', 11, '40GP', 28000.00, 'MR-500114', 'EN_PUERTO',     '2026-10-22'), -- 14
 ('ZIMU8765432', 13, '20GP', 12500.00, 'MR-500115', 'LIBERADO',      '2026-10-22'), -- 15
 ('EGLV3456789', 16, '40HC', 24000.00, 'MR-500116', 'LIBERADO',      '2026-10-23'); -- 16

-- -----------------------------------------------------------------------------
-- 11. BODEGA (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO bodega (codigo, nombre, ubicacion, tipo, capacidad_m3, id_funcionario_responsable, activa) VALUES
 ('BOD-FIS-01', 'Bodega Fiscal Puerto Cortés',          'Puerto Cortés, Cortés',          'FISCAL',            25000,  4, TRUE), -- 1
 ('BOD-DT-02',  'Depósito Temporal Toncontín',          'Tegucigalpa, Francisco Morazán', 'DEPOSITO_TEMPORAL',  8000,  5, TRUE), -- 2
 ('BOD-REF-03', 'Bodega Refrigerada San Pedro Sula',    'San Pedro Sula, Cortés',         'REFRIGERADA',        3000, 15, TRUE), -- 3
 ('BOD-ZL-04',  'Zona Libre Puerto Cortés Almacén A',   'Puerto Cortés, Cortés',          'ZONA_LIBRE',        15000,  4, TRUE), -- 4
 ('BOD-FIS-05', 'Bodega Fiscal La Mesa',                'La Lima, Cortés',                'FISCAL',            12000,  5, TRUE), -- 5
 ('BOD-DT-06',  'Depósito Aduanero Palmerola Central',  'Comayagua, Comayagua',           'DEPOSITO_TEMPORAL', 18000, 15, TRUE), -- 6
 ('BOD-REF-07', 'Frigorífico Aduanero Puerto Cortés',   'Muelle Fiscal, Puerto Cortés',   'REFRIGERADA',        4500,  4, TRUE), -- 7
 ('BOD-FIS-08', 'Almacén Fiscal El Amatillo',          'Goascorán, Valle',               'FISCAL',             6000,  5, TRUE), -- 8
 ('BOD-FIS-09', 'Almacén Fiscal Guasaule',             'El Triunfo, Choluteca',          'FISCAL',             5000,  5, TRUE), -- 9
 ('BOD-ZL-10',  'Zona Libre Choloma Depósito Central',  'Choloma, Cortés',                'ZONA_LIBRE',        22000, 15, TRUE), -- 10
 ('BOD-DT-11',  'Depósito Temporal Corinto',            'Omoa, Cortés',                   'DEPOSITO_TEMPORAL',  7500,  4, TRUE), -- 11
 ('BOD-FIS-12', 'Bodega Fiscal Agua Caliente',         'Ocotepeque, Ocotepeque',         'FISCAL',             4000,  5, TRUE), -- 12
 ('BOD-REF-13', 'Cámara Fría Toncontín Carga',          'Aeropuerto Toncontín, Tegucigalpa','REFRIGERADA',      2000, 15, TRUE), -- 13
 ('BOD-FIS-14', 'Almacén Fiscal Roatán Port',           'Coxen Hole, Roatán',             'FISCAL',             3500,  4, TRUE), -- 14
 ('BOD-DT-15',  'Depósito Aduanero San Lorenzo',        'Puerto San Lorenzo, Valle',      'DEPOSITO_TEMPORAL',  9000,  5, TRUE), -- 15
 ('BOD-ZL-16',  'Zona Franca Villanueva Industrial',    'Villanueva, Cortés',             'ZONA_LIBRE',        14000, 15, TRUE); -- 16

-- -----------------------------------------------------------------------------
-- 12. INVENTARIO_BODEGA (16 registros, PK compuesta: id_bodega + id_producto + id_declaracion)
-- -----------------------------------------------------------------------------
INSERT INTO inventario_bodega (id_bodega, id_producto, id_declaracion, cantidad_actual, ubicacion_rack, fecha_ingreso) VALUES
 ( 1,  3,  2,   500.000, 'A-01-03',    '2026-09-14'), -- 1
 ( 1,  4,  2,   200.000, 'A-01-04',    '2026-09-14'), -- 2
 ( 1,  6,  4,    12.000, 'PATIO-V-01', '2026-09-26'), -- 3
 ( 2, 10,  7,   300.000, 'B-02-01',    '2026-10-15'), -- 4
 ( 2,  7,  8, 10000.000, 'C-05-02',    '2026-10-20'), -- 5
 ( 3,  5,  3,     0.000, 'R-01-01',    '2026-09-18'), -- 6 (despachado)
 ( 1,  1,  1,     0.000, 'A-02-01',    '2026-09-03'), -- 7 (despachado)
 ( 1,  2,  1,     0.000, 'A-02-02',    '2026-09-03'), -- 8 (despachado)
 ( 4, 11,  9,  4000.000, 'ZL-PAL-01',  '2026-10-21'), -- 9
 ( 1, 14, 10,     5.000, 'PATIO-C-02', '2026-10-22'), -- 10
 ( 5, 15, 12,    10.000, 'E-01-10',    '2026-10-23'), -- 11
 ( 1, 16, 13,  2000.000, 'D-03-05',    '2026-10-23'), -- 12
 ( 2, 13, 14,   150.000, 'B-04-12',    '2026-10-23'), -- 13
 ( 3,  5, 15, 12857.000, 'R-02-04',    '2026-10-23'), -- 14
 ( 6,  9,  6,  1000.000, 'SILO-01',    '2026-10-14'), -- 15
 ( 1,  8,  5,     2.000, 'PATIO-M-01', '2026-10-06'); -- 16

-- -----------------------------------------------------------------------------
-- 13. MOVIMIENTO_INVENTARIO (16 registros de kardex)
-- -----------------------------------------------------------------------------
INSERT INTO movimiento_inventario (id_inventario, tipo_movimiento, cantidad, fecha_movimiento, id_funcionario, id_bodega_destino, observacion) VALUES
 ( 7, 'INGRESO',   100.000, '2026-09-03 08:30',  4, NULL, 'Ingreso contenedor MSCU1234565'),
 ( 8, 'INGRESO',   150.000, '2026-09-03 08:45',  4, NULL, 'Ingreso contenedor MSCU1234565'),
 ( 1, 'INGRESO',   500.000, '2026-09-14 10:00',  4, NULL, 'Ingreso contenedor MAEU7654321'),
 ( 2, 'INGRESO',   200.000, '2026-09-14 10:20',  4, NULL, 'Ingreso contenedor CMAU2468101'),
 ( 7, 'SALIDA',    100.000, '2026-09-08 14:00',  4, NULL, 'Despacho con levante DUA-2026-000101'),
 ( 8, 'SALIDA',    150.000, '2026-09-08 14:10',  4, NULL, 'Despacho con levante DUA-2026-000101'),
 ( 6, 'INGRESO', 20000.000, '2026-09-18 07:15', 15, NULL, 'Ingreso cadena de frío TRLU4455667'),
 ( 6, 'SALIDA',  20000.000, '2026-09-22 16:30', 15, NULL, 'Despacho con levante DUA-2026-000103'),
 ( 3, 'INGRESO',    12.000, '2026-09-26 09:00',  4, NULL, 'Vehículos en patio, retenidos por inspección'),
 ( 4, 'INGRESO',   300.000, '2026-10-15 11:00',  5, NULL, 'Ingreso TRLU7788990'),
 ( 5, 'INGRESO', 10000.000, '2026-10-20 13:40',  5, NULL, 'Mercancía retenida por subvaluación'),
 ( 9, 'INGRESO',  4000.000, '2026-10-21 15:00',  4, NULL, 'Ingreso arroz a zona libre'),
 (10, 'INGRESO',     5.000, '2026-10-22 09:30',  4, NULL, 'Ingreso camiones en patio'),
 (11, 'INGRESO',    10.000, '2026-10-23 10:00',  5, NULL, 'Ingreso servidores Dell'),
 (12, 'INGRESO',  2000.000, '2026-10-23 11:15',  4, NULL, 'Ingreso lubricantes autorizados'),
 (13, 'TRASLADO',   50.000, '2026-10-23 14:00',  5,    4, 'Traslado preventivo hacia Zona Libre');

-- -----------------------------------------------------------------------------
-- 14. INSPECCION (16 registros)
-- -----------------------------------------------------------------------------
INSERT INTO inspeccion (id_declaracion, id_contenedor, id_funcionario, fecha_inspeccion, canal, tipo, resultado, observaciones) VALUES
 ( 1,  1,  6, '2026-09-04 09:00', 'VERDE',    'DOCUMENTAL',   'CONFORME',          'Sin novedad en documentación de laptops.'),
 ( 2,  2,  7, '2026-09-12 10:30', 'AMARILLO', 'DOCUMENTAL',   'CON_OBSERVACIONES', 'Diferencia menor en factura comercial, subsanada.'),
 ( 3,  9,  6, '2026-09-19 08:15', 'VERDE',    'DOCUMENTAL',   'CONFORME',          'Certificados sanitarios y cadena de frío en regla.'),
 ( 4,  4,  7, '2026-09-27 11:00', 'ROJO',     'FISICA',       'PENDIENTE',         'Programada revisión física de número VIN y chasis.'),
 ( 4,  5,  8, '2026-09-27 15:00', 'ROJO',     'NO_INTRUSIVA', 'CON_OBSERVACIONES', 'Rayos X muestran bultos adicionales no declarados.'),
 ( 8, 11,  6, '2026-10-21 09:45', 'ROJO',     'FISICA',       'NO_CONFORME',       'Mercancía subvaluada; valor declarado inferior a referencia.'),
 ( 7, 10,  7, '2026-10-16 10:00', 'AMARILLO', 'DOCUMENTAL',   'CONFORME',          'Documentación completa de televisores.'),
 ( 5,  6,  8, '2026-10-06 14:20', 'ROJO',     'FISICA',       'CONFORME',          'Excavadoras verificadas en patio, número de serie coincide.'),
 ( 9, 12,  9, '2026-10-21 11:00', 'VERDE',    'DOCUMENTAL',   'CONFORME',          'Despacho expedito de arroz.'),
 (10, 13,  7, '2026-10-22 16:30', 'ROJO',     'FISICA',       'PENDIENTE',         'Pendiente dictamen de homologación vehicular.'),
 (11, 14,  6, '2026-10-22 17:00', 'AMARILLO', 'DOCUMENTAL',   'CONFORME',          'Revisión de certificados de origen de fertilizantes.'),
 (12, NULL,8, '2026-10-23 09:00', 'AMARILLO', 'DOCUMENTAL',   'CONFORME',          'Revisión documental aérea de servidores.'),
 (13, 15,  9, '2026-10-23 10:45', 'VERDE',    'DOCUMENTAL',   'CONFORME',          'Lubricantes con permiso ambiental aprobado.'),
 (14, NULL,6, '2026-10-23 11:30', 'AMARILLO', 'DOCUMENTAL',   'PENDIENTE',         'Pendiente confirmación de pago de aranceles.'),
 (15, NULL,7, '2026-10-23 14:00', 'VERDE',    'DOCUMENTAL',   'CONFORME',          'Medicamentos con visto bueno de ARSA.'),
 (16, 16,  8, '2026-10-23 15:30', 'VERDE',    'DOCUMENTAL',   'CONFORME',          'Exportación de café con certificado IHCAFE verificado.');

COMMIT;


-- ==================== ARCHIVO: 03_readonly_role.sql ====================
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



-- ==================== ARCHIVO: 05_vistas_analiticas.sql ====================
-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 05_vistas_analiticas.sql
--  Propósito: Vistas desnormalizadas de alto rendimiento para auditoría,
--             reportes gerenciales y aceleración de consultas del AI Agent.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- VISTA 1: v_declaraciones_resumen
-- Propósito: Visión 360° de la declaración, combinando importador, agente,
--            revisor aduanero y estado financiero de la liquidación de tributos.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_declaraciones_resumen AS
SELECT
    d.id_declaracion,
    d.numero_declaracion,
    d.fecha_declaracion,
    d.regimen,
    d.tipo_transporte,
    d.estado                               AS estado_declaracion,
    i.identificacion_fiscal                AS rtn_importador,
    i.razon_social                         AS importador,
    p_proc.nombre                          AS pais_procedencia,
    a.numero_licencia                      AS licencia_agente,
    a.nombre || ' ' || a.apellido          AS agente_aduanal,
    COALESCE(f.nombre || ' ' || f.apellido, 'SIN_ASIGNAR') AS funcionario_revisor,
    d.valor_fob,
    d.valor_flete,
    d.valor_seguro,
    d.valor_cif,
    COALESCE(l.numero_liquidacion, 'S/L')  AS numero_liquidacion,
    COALESCE(l.monto_dai, 0)               AS dai_usd,
    COALESCE(l.monto_iva, 0)               AS iva_usd,
    COALESCE(l.total_pagar, 0)             AS total_tributos_usd,
    COALESCE(l.estado_pago, 'NO_LIQUIDADO') AS estado_pago,
    l.fecha_pago
FROM declaracion d
INNER JOIN importador     i      ON i.id_importador        = d.id_importador
INNER JOIN agente_aduanal a      ON a.id_agente            = d.id_agente
INNER JOIN pais           p_proc ON p_proc.id_pais         = d.id_pais_procedencia
LEFT  JOIN funcionario    f      ON f.id_funcionario       = d.id_funcionario_revisor
LEFT  JOIN liquidacion_arancel l ON l.id_declaracion       = d.id_declaracion;

COMMENT ON VIEW v_declaraciones_resumen IS 'Visión consolidada de declaraciones aduaneras con tributos e importadores.';


-- -----------------------------------------------------------------------------
-- VISTA 2: v_inventario_activo
-- Propósito: Monitoreo en tiempo real de existencias físicas en bodegas
--            aduaneras con valorización FOB estimada en USD.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_inventario_activo AS
SELECT
    ib.id_inventario,
    b.codigo                               AS codigo_bodega,
    b.nombre                               AS nombre_bodega,
    b.tipo                                 AS tipo_bodega,
    b.ubicacion                            AS ubicacion_bodega,
    p.codigo                               AS codigo_producto,
    p.descripcion                          AS producto,
    pa.codigo_sa                           AS partida_arancelaria,
    p_orig.nombre                          AS pais_origen_producto,
    d.numero_declaracion,
    ib.ubicacion_rack,
    ib.cantidad_actual,
    pa.unidad_medida,
    p.valor_unitario_usd                   AS valor_unitario_ref_usd,
    ROUND(ib.cantidad_actual * p.valor_unitario_usd, 2) AS valor_total_usd,
    ib.fecha_ingreso,
    ib.fecha_ultima_actualizacion
FROM inventario_bodega ib
INNER JOIN bodega              b      ON b.id_bodega       = ib.id_bodega
INNER JOIN producto            p      ON p.id_producto     = ib.id_producto
INNER JOIN partida_arancelaria pa     ON pa.id_partida     = p.id_partida
INNER JOIN pais                p_orig ON p_orig.id_pais    = p.id_pais_origen
INNER JOIN declaracion         d      ON d.id_declaracion  = ib.id_declaracion
WHERE ib.cantidad_actual > 0;

COMMENT ON VIEW v_inventario_activo IS 'Stock físico activo en bodegas con valorización comercial.';


-- -----------------------------------------------------------------------------
-- VISTA 3: v_alertas_riesgo
-- Propósito: Panel de control de incidentes aduaneros (contenedores retenidos,
--            declaraciones rechazadas o inspecciones con canal ROJO).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas_riesgo AS
SELECT
    c.id_contenedor,
    c.numero_contenedor,
    c.tipo                                 AS tipo_contenedor,
    c.estado                               AS estado_contenedor,
    d.numero_declaracion,
    d.estado                               AS estado_declaracion,
    i.identificacion_fiscal,
    i.razon_social                         AS importador,
    ins.id_inspeccion,
    ins.fecha_inspeccion,
    ins.canal                              AS canal_selectividad,
    ins.tipo                               AS tipo_inspeccion,
    ins.resultado                          AS resultado_inspeccion,
    f.nombre || ' ' || f.apellido          AS funcionario_inspector,
    ins.observaciones
FROM contenedor c
INNER JOIN declaracion d   ON d.id_declaracion = c.id_declaracion
INNER JOIN importador  i   ON i.id_importador  = d.id_importador
LEFT  JOIN inspeccion  ins ON ins.id_contenedor = c.id_contenedor
LEFT  JOIN funcionario f   ON f.id_funcionario = ins.id_funcionario
WHERE c.estado = 'RETENIDO' 
   OR d.estado = 'RECHAZADA'
   OR ins.canal = 'ROJO'
   OR ins.resultado = 'NO_CONFORME';

COMMENT ON VIEW v_alertas_riesgo IS 'Incidentes y alertas operativas de selectividad y retenciones.';


-- -----------------------------------------------------------------------------
-- VISTA 4: v_organigrama_aduanas
-- Propósito: Visualizar la estructura jerárquica de funcionarios y supervisores.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_organigrama_aduanas AS
SELECT
    f.id_funcionario,
    f.codigo_empleado,
    f.nombre || ' ' || f.apellido          AS funcionario,
    f.cargo,
    f.email,
    f.activo,
    s.codigo_empleado                      AS codigo_supervisor,
    COALESCE(s.nombre || ' ' || s.apellido, 'DIRECCION_GENERAL') AS supervisor_directo,
    s.cargo                                AS cargo_supervisor
FROM funcionario f
LEFT JOIN funcionario s ON s.id_funcionario = f.id_supervisor;

COMMENT ON VIEW v_organigrama_aduanas IS 'Jerarquía y supervisión de funcionarios de aduana.';

-- Otorgar permisos de lectura al rol de n8n sobre las vistas
GRANT SELECT ON v_declaraciones_resumen TO agente_n8n_readonly;
GRANT SELECT ON v_inventario_activo    TO agente_n8n_readonly;
GRANT SELECT ON v_alertas_riesgo       TO agente_n8n_readonly;
GRANT SELECT ON v_organigrama_aduanas  TO agente_n8n_readonly;

COMMIT;


-- ==================== ARCHIVO: 06_triggers_auditoria.sql ====================
-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 06_triggers_auditoria.sql
--  Propósito: Automatización de consistencia del Kardex con existencias.
--             Actualiza inventario_bodega.cantidad_actual ante cada INSERT
--             en movimiento_inventario (INGRESO, SALIDA, TRASLADO, AJUSTE)
--             y previene saldos negativos.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- FUNCIÓN TRIGGER: fn_actualizar_inventario_kardex
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_actualizar_inventario_kardex()
RETURNS TRIGGER AS $$
DECLARE
    v_stock_actual NUMERIC(14,3);
    v_id_bodega_origen INTEGER;
    v_id_producto INTEGER;
    v_id_declaracion INTEGER;
    v_id_inventario_destino INTEGER;
BEGIN
    -- Obtener datos del lote de inventario origen
    SELECT cantidad_actual, id_bodega, id_producto, id_declaracion
    INTO v_stock_actual, v_id_bodega_origen, v_id_producto, v_id_declaracion
    FROM inventario_bodega
    WHERE id_inventario = NEW.id_inventario;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El lote de inventario % no existe en inventario_bodega', NEW.id_inventario;
    END IF;

    -- 1. Movimiento de INGRESO
    IF NEW.tipo_movimiento = 'INGRESO' THEN
        UPDATE inventario_bodega
        SET cantidad_actual = cantidad_actual + NEW.cantidad,
            fecha_ultima_actualizacion = CURRENT_TIMESTAMP
        WHERE id_inventario = NEW.id_inventario;

    -- 2. Movimiento de SALIDA
    ELSIF NEW.tipo_movimiento = 'SALIDA' THEN
        IF v_stock_actual < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para despacho. Disponible: %, Solicitado: %', 
                v_stock_actual, NEW.cantidad;
        END IF;

        UPDATE inventario_bodega
        SET cantidad_actual = cantidad_actual - NEW.cantidad,
            fecha_ultima_actualizacion = CURRENT_TIMESTAMP
        WHERE id_inventario = NEW.id_inventario;

    -- 3. Movimiento de TRASLADO (entre bodegas)
    ELSIF NEW.tipo_movimiento = 'TRASLADO' THEN
        IF v_stock_actual < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para traslado. Disponible: %, Solicitado: %', 
                v_stock_actual, NEW.cantidad;
        END IF;

        -- Descontar de bodega origen
        UPDATE inventario_bodega
        SET cantidad_actual = cantidad_actual - NEW.cantidad,
            fecha_ultima_actualizacion = CURRENT_TIMESTAMP
        WHERE id_inventario = NEW.id_inventario;

        -- Verificar si ya existe el lote en la bodega destino
        SELECT id_inventario INTO v_id_inventario_destino
        FROM inventario_bodega
        WHERE id_bodega = NEW.id_bodega_destino
          AND id_producto = v_id_producto
          AND id_declaracion = v_id_declaracion;

        IF FOUND THEN
            -- Sumar al lote existente en destino
            UPDATE inventario_bodega
            SET cantidad_actual = cantidad_actual + NEW.cantidad,
                fecha_ultima_actualizacion = CURRENT_TIMESTAMP
            WHERE id_inventario = v_id_inventario_destino;
        ELSE
            -- Crear nuevo lote en bodega destino
            INSERT INTO inventario_bodega (id_bodega, id_producto, id_declaracion, cantidad_actual, ubicacion_rack, fecha_ingreso)
            VALUES (NEW.id_bodega_destino, v_id_producto, v_id_declaracion, NEW.cantidad, 'RACK-TRASLADO', CURRENT_DATE);
        END IF;

    -- 4. Movimiento de AJUSTE (reemplaza el stock al valor registrado o aplica corrección)
    ELSIF NEW.tipo_movimiento = 'AJUSTE' THEN
        UPDATE inventario_bodega
        SET cantidad_actual = NEW.cantidad,
            fecha_ultima_actualizacion = CURRENT_TIMESTAMP
        WHERE id_inventario = NEW.id_inventario;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- TRIGGER: trg_actualizar_inventario_kardex
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_actualizar_inventario_kardex ON movimiento_inventario;

CREATE TRIGGER trg_actualizar_inventario_kardex
AFTER INSERT ON movimiento_inventario
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_inventario_kardex();

COMMENT ON FUNCTION fn_actualizar_inventario_kardex() IS 'Sincroniza inventario_bodega.cantidad_actual ante cada movimiento de kardex.';

COMMIT;

