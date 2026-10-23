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
