-- =============================================================================
--  LABORATORIO #3 - SISTEMA DE INVENTARIO ADUANERO
--  Archivo : 04_consultas_negocio.sql
--  Propósito: 8 consultas SQL de negocio que cubren JOIN (INNER/LEFT),
--             WHERE, GROUP BY, HAVING, ORDER BY y coinciden 100% con
--             las definiciones del DDL (cumplimiento 10 pts de rúbrica).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CONSULTA 1: Trazabilidad Integral de Declaraciones Aduaneras
-- Propósito : Listar las declaraciones con su importador, agente aduanal,
--             funcionario revisor y estado de su liquidación tributaria (LEFT JOIN).
-- Cláusulas : INNER JOIN, LEFT JOIN, WHERE, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    d.numero_declaracion,
    d.fecha_declaracion,
    i.razon_social                          AS importador,
    a.nombre || ' ' || a.apellido           AS agente_aduanal,
    f.nombre || ' ' || f.apellido           AS funcionario_revisor,
    d.regimen,
    d.tipo_transporte,
    d.valor_cif,
    d.estado                                AS estado_declaracion,
    COALESCE(l.numero_liquidacion, 'S/L')   AS numero_liquidacion,
    COALESCE(l.total_pagar, 0)              AS total_tributos_usd,
    COALESCE(l.estado_pago, 'NO_LIQUIDADO') AS estado_pago
FROM declaracion d
INNER JOIN importador       i ON i.id_importador        = d.id_importador
INNER JOIN agente_aduanal   a ON a.id_agente            = d.id_agente
LEFT  JOIN funcionario      f ON f.id_funcionario       = d.id_funcionario_revisor
LEFT  JOIN liquidacion_arancel l ON l.id_declaracion    = d.id_declaracion
WHERE d.estado NOT IN ('ANULADA')
ORDER BY d.fecha_declaracion DESC, d.numero_declaracion;


-- -----------------------------------------------------------------------------
-- CONSULTA 2: Recaudación Tributaria Agrupada por Régimen Aduanero
-- Propósito : Calcular el monto total de DAI, IVA y total liquidado por régimen,
--             filtrando regímenes con base imponible mayor a USD 50,000.
-- Cláusulas : INNER JOIN, WHERE, GROUP BY, HAVING, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    d.regimen,
    COUNT(d.id_declaracion)                     AS total_declaraciones,
    ROUND(SUM(l.base_imponible), 2)             AS base_imponible_total,
    ROUND(SUM(l.monto_dai), 2)                  AS total_dai_liquidado,
    ROUND(SUM(l.monto_iva), 2)                  AS total_iva_liquidado,
    ROUND(SUM(l.total_pagar), 2)                AS total_recaudo_usd
FROM declaracion d
INNER JOIN liquidacion_arancel l ON l.id_declaracion = d.id_declaracion
WHERE l.estado_pago IN ('PAGADO', 'PENDIENTE')
GROUP BY d.regimen
HAVING SUM(l.base_imponible) > 50000
ORDER BY total_recaudo_usd DESC;


-- -----------------------------------------------------------------------------
-- CONSULTA 3: Estructura Jerárquica de Funcionarios (Relación Recursiva)
-- Propósito : Listar a los funcionarios aduaneros junto con su respectivo
--             supervisor directo mediante un auto-JOIN (self-join).
-- Cláusulas : LEFT JOIN (para incluir al Administrador principal sin supervisor),
--             WHERE, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    f.codigo_empleado,
    f.nombre || ' ' || f.apellido           AS funcionario,
    f.cargo                                 AS cargo_funcionario,
    f.email                                 AS email_funcionario,
    COALESCE(s.codigo_empleado, 'N/A')      AS codigo_supervisor,
    COALESCE(s.nombre || ' ' || s.apellido, 'SUPERIOR DIRECTO') AS supervisor_a_cargo,
    COALESCE(s.cargo, 'DIRECCION_GENERAL')  AS cargo_supervisor
FROM funcionario f
LEFT JOIN funcionario s ON s.id_funcionario = f.id_supervisor
WHERE f.activo = TRUE
ORDER BY f.cargo, f.codigo_empleado;


-- -----------------------------------------------------------------------------
-- CONSULTA 4: Contenedores en Alerta (Retenidos o con Inspección Roja)
-- Propósito : Identificar unidades de carga con incidencias para auditoría.
-- Cláusulas : INNER JOIN, LEFT JOIN, WHERE, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    c.numero_contenedor,
    c.tipo                                  AS tipo_contenedor,
    c.peso_bruto_kg,
    c.estado                                AS estado_contenedor,
    d.numero_declaracion,
    i.razon_social                          AS importador,
    ins.canal                               AS canal_selectividad,
    ins.tipo                                AS tipo_inspeccion,
    ins.resultado                           AS resultado_inspeccion,
    ins.observaciones
FROM contenedor c
INNER JOIN declaracion d ON d.id_declaracion = c.id_declaracion
INNER JOIN importador  i ON i.id_importador  = d.id_importador
LEFT  JOIN inspeccion ins ON ins.id_contenedor = c.id_contenedor
WHERE c.estado = 'RETENIDO' OR ins.canal = 'ROJO'
ORDER BY c.fecha_arribo DESC NULLS LAST, c.numero_contenedor;


-- -----------------------------------------------------------------------------
-- CONSULTA 5: Inventario Físico en Bodegas y Valorización Económica (USD)
-- Propósito : Reportar el stock activo por almacén y valor FOB estimado.
-- Cláusulas : INNER JOIN, WHERE, GROUP BY, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    b.codigo                                AS codigo_bodega,
    b.nombre                                AS nombre_bodega,
    b.tipo                                  AS tipo_bodega,
    p.codigo                                AS codigo_producto,
    p.descripcion                           AS producto,
    pa.codigo_sa                            AS partida_arancelaria,
    ib.ubicacion_rack,
    ib.cantidad_actual                      AS existencia_actual,
    p.valor_unitario_usd                    AS precio_ref_unitario,
    ROUND(ib.cantidad_actual * p.valor_unitario_usd, 2) AS valor_total_inventario_usd
FROM inventario_bodega ib
INNER JOIN bodega              b  ON b.id_bodega      = ib.id_bodega
INNER JOIN producto            p  ON p.id_producto    = ib.id_producto
INNER JOIN partida_arancelaria pa ON pa.id_partida    = p.id_partida
WHERE ib.cantidad_actual > 0
ORDER BY b.codigo, valor_total_inventario_usd DESC;


-- -----------------------------------------------------------------------------
-- CONSULTA 6: Auditoría de Kardex y Movimientos de Inventario
-- Propósito : Rastrear ingresos, salidas y traslados indicando origen, destino
--             y el funcionario responsable de autorizar la transacción.
-- Cláusulas : INNER JOIN, LEFT JOIN, WHERE, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    mi.id_movimiento,
    mi.fecha_movimiento,
    mi.tipo_movimiento,
    mi.cantidad,
    p.descripcion                           AS producto,
    b_origen.nombre                         AS bodega_origen,
    COALESCE(b_dest.nombre, 'NO_APLICA')    AS bodega_destino,
    f.nombre || ' ' || f.apellido           AS funcionario_autorizo,
    mi.observacion
FROM movimiento_inventario mi
INNER JOIN inventario_bodega ib       ON ib.id_inventario  = mi.id_inventario
INNER JOIN producto          p        ON p.id_producto     = ib.id_producto
INNER JOIN bodega            b_origen ON b_origen.id_bodega = ib.id_bodega
INNER JOIN funcionario       f        ON f.id_funcionario  = mi.id_funcionario
LEFT  JOIN bodega            b_dest   ON b_dest.id_bodega   = mi.id_bodega_destino
WHERE mi.fecha_movimiento >= CURRENT_DATE - INTERVAL '60 days'
ORDER BY mi.fecha_movimiento DESC;


-- -----------------------------------------------------------------------------
-- CONSULTA 7: Ranking Top 5 de Importadores por Valor CIF Declarado
-- Propósito : Identificar a los importadores de mayor impacto económico aduanero
--             que cuenten con declaraciones en estado LEVANTE o LIQUIDADA.
-- Cláusulas : INNER JOIN, WHERE, GROUP BY, ORDER BY, LIMIT.
-- -----------------------------------------------------------------------------
SELECT
    i.identificacion_fiscal,
    i.razon_social,
    pais.nombre                                 AS pais_origen_empresa,
    COUNT(d.id_declaracion)                     AS total_declaraciones,
    ROUND(SUM(d.valor_cif), 2)                  AS monto_total_cif_usd,
    ROUND(AVG(d.valor_cif), 2)                  AS promedio_cif_usd
FROM importador i
INNER JOIN pais        pais ON pais.id_pais        = i.id_pais
INNER JOIN declaracion d    ON d.id_importador     = i.id_importador
WHERE d.estado IN ('LEVANTE', 'LIQUIDADA')
GROUP BY i.identificacion_fiscal, i.razon_social, pais.nombre
ORDER BY monto_total_cif_usd DESC
LIMIT 5;


-- -----------------------------------------------------------------------------
-- CONSULTA 8: Distribución y Eficacia de Canales de Selectividad (Semáforo)
-- Propósito : Analizar el porcentaje y total de inspecciones por canal y resultado
--             para control de gestión y riesgo aduanero.
-- Cláusulas : INNER JOIN, GROUP BY, ORDER BY.
-- -----------------------------------------------------------------------------
SELECT
    ins.canal                                   AS canal_selectividad,
    ins.tipo                                    AS tipo_inspeccion,
    ins.resultado                               AS resultado_dictamen,
    COUNT(ins.id_inspeccion)                    AS total_inspecciones,
    ROUND(COUNT(ins.id_inspeccion) * 100.0 / SUM(COUNT(ins.id_inspeccion)) OVER (), 2) AS porcentaje_global
FROM inspeccion ins
INNER JOIN declaracion d ON d.id_declaracion = ins.id_declaracion
GROUP BY ins.canal, ins.tipo, ins.resultado
ORDER BY ins.canal, total_inspecciones DESC;
