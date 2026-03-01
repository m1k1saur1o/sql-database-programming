-- CASO 1

-- Trigger para actualizar el consum total
CREATE OR REPLACE TRIGGER trg_actualizar_total_consumos
AFTER INSERT OR DELETE OR UPDATE OF monto ON consumo
FOR EACH ROW
BEGIN

    -- En el caso de la insercion se captura una exepcion en caso de que 
    -- ya exista una fila con el valor total para insertar o actualizar segun 
    -- corresponda
    IF INSERTING THEN
        BEGIN
            INSERT INTO total_consumos (id_huesped, monto_consumos)
            VALUES (:NEW.id_huesped, :NEW.monto);
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                UPDATE total_consumos
                SET monto_consumos = monto_consumos + :NEW.monto
                WHERE id_huesped = :NEW.id_huesped;
        END;
    END IF;

    -- En el caso de actualizar se asume que ya existe una fila
    IF UPDATING THEN
        IF :OLD.monto != :NEW.monto THEN
        
            UPDATE total_consumos
            SET monto_consumos = monto_consumos + (:NEW.monto - :OLD.monto)
            WHERE id_huesped = :NEW.id_huesped;
        END IF;
    END IF;

    -- Para borrar se asume que ya existe una fila
    IF DELETING THEN  
        UPDATE total_consumos
        SET monto_consumos = monto_consumos - :OLD.monto
        WHERE id_huesped = :OLD.id_huesped;
    END IF;

    COMMIT;
END;

-- Bloque pl/sql para las pruebas
BEGIN   
    -- Insercion nuevo consumo
    INSERT INTO consumo (id_consumo, id_reserva, id_huesped, monto)
    VALUES (11527, 1587, 340006, 150);

    -- Eliminar consumo ID 11473
    DELETE FROM consumo
    WHERE id_consumo = 11473;

    -- Actualizar consumo ID 10688 a 95
    UPDATE consumo
    SET monto = 95
    WHERE id_consumo = 10688;
    
    COMMIT;
END;

-- CASO 2

-- se crea el package
CREATE OR REPLACE PACKAGE pkg_tours AS

    -- Variable pública
    v_monto_tours NUMBER;

    -- Función pública
    FUNCTION fn_monto_tours (
        p_id_huesped NUMBER
    ) RETURN NUMBER;

END pkg_tours;

-- cuerpo del package
CREATE OR REPLACE PACKAGE BODY pkg_tours AS

    FUNCTION fn_monto_tours (
        p_id_huesped NUMBER
    ) RETURN NUMBER
    IS
        v_total NUMBER;
        v_existe NUMBER;
    BEGIN
        -- Ver si existe el huesped
        SELECT COUNT(*)
        INTO v_existe
        FROM huesped
        WHERE id_huesped = p_id_huesped;

        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20010,
                'El huésped no existe.'
            );
        END IF;

        -- Se calcula el monto de los tours
        SELECT NVL(SUM(ht.num_personas * t.valor_tour), 0)
        INTO v_total
        FROM huesped_tour ht
        JOIN tour t
            ON ht.id_tour = t.id_tour
        WHERE ht.id_huesped = p_id_huesped;

        -- Se guarda en la variable publica
        v_monto_tours := v_total;

        RETURN v_total;

    END fn_monto_tours;

END pkg_tours;

-- funciones

-- funcion para buscar la agencia del huesped
CREATE OR REPLACE FUNCTION fn_agencia_huesped (
    p_id_huesped NUMBER
) RETURN VARCHAR2
IS
    v_agencia agencia.nom_agencia%TYPE;
BEGIN

    -- Buscar agencia del huésped
    SELECT a.nom_agencia
    INTO v_agencia
    FROM huesped h
    JOIN agencia a
        ON h.id_agencia = a.id_agencia
    WHERE h.id_huesped = p_id_huesped;

    RETURN v_agencia;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DECLARE
            v_error VARCHAR2(4000);
        BEGIN
            v_error := SQLERRM;

            INSERT INTO reg_errores (
                id_error,
                nomsubprograma,
                msg_error
            )
            VALUES (
                sq_error.NEXTVAL,
                'Error en la función FN_AGENCIA_HUESPED al recuperar la agencia del huesped con id ' || p_id_huesped,
                v_error
            );

            COMMIT;
        END;
        RETURN 'NO REGISTRA AGENCIA';
END fn_agencia_huesped;

-- funcion para buscar los consumos del huesped
CREATE OR REPLACE FUNCTION fn_monto_consumos (
    p_id_huesped NUMBER
) RETURN NUMBER
IS
    v_monto total_consumos.monto_consumos%TYPE;
BEGIN

    -- se buscan los consumos
    SELECT monto_consumos
    INTO v_monto
    FROM total_consumos
    WHERE id_huesped = p_id_huesped;

    RETURN v_monto;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DECLARE
            v_error VARCHAR2(4000);
        BEGIN
            v_error := SQLERRM;

            INSERT INTO reg_errores (
                id_error,
                nomsubprograma,
                msg_error
            )
            VALUES (
                sq_error.NEXTVAL,
                'Error en la función FN_MONTO_CONSUMOS al recuperar los consumos del cliente con id ' || p_id_huesped,
                v_error
            );

            COMMIT;
        END;
        RETURN 0;
END fn_monto_consumos;

-- procedimiento para calcular el detalle del pago
CREATE OR REPLACE PROCEDURE sp_calcular_pago (
    p_fecha_texto IN VARCHAR2,  
    p_valor_dolar IN NUMBER
)
AS
    v_fecha DATE;  
    v_valor_persona NUMBER := 35000;
    v_detalle detalle_diario_huespedes%ROWTYPE;
BEGIN
    -- Se limpian las tablas
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_DIARIO_HUESPEDES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE REG_ERRORES';

    -- Convertimos el texto a DATE
    v_fecha := TO_DATE(p_fecha_texto, 'DD/MM/YYYY');

    -- Consultamos las reservas que terminan en el dia
    -- determinado, junto con los datos para calcular
    -- el costo del alojamiento
    FOR rec IN (
        SELECT 
            h.id_huesped,
            h.nom_huesped ||' '|| h.appat_huesped || ' ' || h.apmat_huesped AS nombre,
            r.estadia AS estadia,
            COUNT(dr.id_reserva) AS cantidad_habitaciones,
            SUM(ha.valor_habitacion) AS valor_habitacion,
            SUM(ha.valor_minibar) AS valor_minibar
        FROM huesped h
            JOIN reserva r ON h.id_huesped = r.id_huesped
            JOIN detalle_reserva dr ON dr.id_reserva = r.id_reserva
            JOIN habitacion ha ON ha.id_habitacion = dr.id_habitacion
        WHERE (r.ingreso + r.estadia) = v_fecha
        GROUP BY 
            h.id_huesped, 
            h.nom_huesped, 
            h.appat_huesped, 
            h.apmat_huesped,
            r.estadia
    ) LOOP

        -- se inicializan las variables del type para insertar en la tabla de detalles
        -- se considero que una habitacion significaba otra persona
        v_detalle.id_huesped := rec.id_huesped;
        v_detalle.nombre := rec.nombre;
        v_detalle.agencia := fn_agencia_huesped(rec.id_huesped);
        v_detalle.alojamiento := ((rec.valor_habitacion + rec.valor_minibar) * rec.estadia) * p_valor_dolar;
        v_detalle.consumos := fn_monto_consumos(rec.id_huesped) * p_valor_dolar;
        v_detalle.tours := pkg_tours.fn_monto_tours(rec.id_huesped) * p_valor_dolar;
        v_detalle.subtotal_pago := v_detalle.alojamiento + v_detalle.consumos + v_detalle.tours + (v_valor_persona * rec.cantidad_habitaciones);
        v_detalle.descuento_consumos := 0;

        -- se aplica el descuento segun corresponda
        IF v_detalle.agencia = 'VIAJES ALBERTI' THEN
            v_detalle.descuentos_agencia := ROUND(v_detalle.subtotal_pago * 0.12);
        ELSE
            v_detalle.descuentos_agencia := 0;
        END IF;

        v_detalle.total := v_detalle.subtotal_pago - v_detalle.descuentos_agencia;

        -- insercion a la tabla
        INSERT INTO detalle_diario_huespedes (
            id_huesped, 
            nombre, 
            agencia, 
            alojamiento, 
            consumos, 
            tours, 
            subtotal_pago,
            descuento_consumos, 
            descuentos_agencia, 
            total
        ) VALUES (
        v_detalle.id_huesped,
        v_detalle.nombre,
        v_detalle.agencia,
        v_detalle.alojamiento,
        v_detalle.consumos,
        v_detalle.tours,
        v_detalle.subtotal_pago,
        v_detalle.descuento_consumos,
        v_detalle.descuentos_agencia,
        v_detalle.total
        );
    END LOOP;
    COMMIT;
END sp_calcular_pago;

-- bloque pl/sql para usar el procedimiento
BEGIN
    sp_calcular_pago('18/08/2021', 915);
END;

