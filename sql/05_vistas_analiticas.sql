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
