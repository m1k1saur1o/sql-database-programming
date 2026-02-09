-- bind para el año
VARIABLE b_anio NUMBER

-- se inicializa el año con el año actual
EXECUTE :b_anio := EXTRACT(YEAR FROM SYSDATE);

-- inicio del bloque
DECLARE      

    -- cursor que trae los datos para poblar la tabla DETALLE_APORTE_SBIF
    -- relaciona los datos del cliente, su tarjeta y las transacciones
    CURSOR c_cliente_trans(p_anio NUMBER) IS
        SELECT 
            c.numrun,
            c.dvrun,
            tc.nro_tarjeta,
            ttc.nro_transaccion,
            ttc.fecha_transaccion,
            ttc.cod_tptran_tarjeta,
            ttc.monto_total_transaccion,
            tas.porc_aporte_sbif
        FROM cliente c
        JOIN tarjeta_cliente tc ON c.numrun = tc.numrun
        JOIN transaccion_tarjeta_cliente ttc ON tc.nro_tarjeta = ttc.nro_tarjeta
        JOIN tramo_aporte_sbif tas ON ttc.monto_total_transaccion >= tas.tramo_inf_av_sav AND ttc.monto_total_transaccion <= tas.tramo_sup_av_sav
        WHERE ttc.cod_tptran_tarjeta IN (102, 103) AND EXTRACT(YEAR FROM ttc.fecha_transaccion) = p_anio
        ORDER BY ttc.fecha_transaccion, c.numrun;
    
    -- cursor que obtiene los datos para poblar la tabla RESUMEN_APORTE_SBIF
    -- Utiliza los datos de DETALLE_APORTE_SBIF 
    CURSOR c_resumen_sbif IS
        SELECT 
            EXTRACT(MONTH FROM fecha_transaccion) AS mes,
            tipo_transaccion,
            SUM(monto_transaccion) AS monto_total_mes,
            SUM(aporte_sbif) AS aporte_sbif_total_mes
        FROM detalle_aporte_sbif
        GROUP BY 
            EXTRACT(MONTH FROM fecha_transaccion),
            tipo_transaccion
        ORDER BY mes;
            
    -- declaracion del array para guardar los tipos de transaccion
    TYPE t_varray_trans IS VARRAY(3) OF VARCHAR2(50);
    
    -- declaracion de variables para los calculos, contadores para las exepciones y registros

    v_reg_cliente_trans c_cliente_trans%ROWTYPE;
    v_reg_resumen_sbif c_resumen_sbif%ROWTYPE;
    v_tipos_trans t_varray_trans;
    v_aporte_sbif NUMBER;
    v_desc_trans VARCHAR2(50);
    v_mes_anio VARCHAR2(6);
    v_contador    NUMBER := 0;

    -- exepcion en caso de que haya mas tipos de transaccion y no quepan
    -- en el varray
    e_varray_fuera_rango EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_varray_fuera_rango, -6533);

    -- exepcion en caso de que no hayan transacciones en el año
    e_sin_transacciones EXCEPTION;
    
    
BEGIN

    -- se truncan las tablas antes de llenarlas
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';
    
    -- se guardan los tipos de transaccion en el varray
    SELECT nombre_tptran_tarjeta
    BULK COLLECT INTO v_tipos_trans
    FROM tipo_transaccion_tarjeta;
    
    -- si no hay se lanza una exepcion de NO_DATA_FOUND
    IF v_tipos_trans.COUNT = 0 THEN
        RAISE NO_DATA_FOUND;
    END IF;

    -- comienza el loop para llenar la tabla DETALLE_APORTE_SBIF
    FOR v_reg_cliente_trans IN c_cliente_trans(:b_anio) LOOP
        
        -- se guarda la descripcion dependiendo del codigo del tipo
        -- de la transaccion
        CASE
            WHEN v_reg_cliente_trans.cod_tptran_tarjeta = 102 THEN v_desc_trans := v_tipos_trans(2);
            WHEN v_reg_cliente_trans.cod_tptran_tarjeta = 103 THEN v_desc_trans := v_tipos_trans(3);
        END CASE;
        
        -- se calcula el aporte sbif en base al monto total y el tramo 
        v_aporte_sbif := v_reg_cliente_trans.monto_total_transaccion * (v_reg_cliente_trans.porc_aporte_sbif / 100);
    
        -- se insertan los datos en la tabla DETALLE_APORTE_SBIF
        INSERT INTO detalle_aporte_sbif (
            numrun,
            dvrun,
            nro_tarjeta,
            nro_transaccion,
            fecha_transaccion,
            tipo_transaccion,
            monto_transaccion,
            aporte_sbif
        )
        VALUES (
            v_reg_cliente_trans.numrun,
            v_reg_cliente_trans.dvrun,
            v_reg_cliente_trans.nro_tarjeta,
            v_reg_cliente_trans.nro_transaccion,
            v_reg_cliente_trans.fecha_transaccion,
            v_desc_trans,
            v_reg_cliente_trans.monto_total_transaccion,
            v_aporte_sbif
        );
        
        -- el contador de las transacciones en el loop
        v_contador := v_contador + 1;
    END LOOP;
    
    -- se lanza una exepcion en caso de que no hayan transacciones
    -- en el año
    IF v_contador = 0 THEN
        RAISE e_sin_transacciones;
    END IF;

    -- loop para poblar la tabla RESUMEN_APORTE_SBIF
    FOR v_reg_resumen_sbif IN c_resumen_sbif LOOP
        
        -- se crea el texto para la primera columna con el mes 
        -- y el año concatenados
        v_mes_anio := LPAD(v_reg_resumen_sbif.mes, 2, '0') || :b_anio;
        
        -- se insertan los registros a la tabla RESUMEN_APORTE_SBIF
        INSERT INTO resumen_aporte_sbif (
            mes_anno,
            tipo_transaccion,
            monto_total_transacciones,
            aporte_total_abif
        )
        VALUES (
            v_mes_anio,
            v_reg_resumen_sbif.tipo_transaccion,
            v_reg_resumen_sbif.monto_total_mes,
            v_reg_resumen_sbif.aporte_sbif_total_mes
        );
    END LOOP;
    
    -- se confirman las inserciones a las tablas si es que no hay exepciones
    COMMIT;

-- exepciones del bloque
EXCEPTION

    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(
          'Error: No existen tipos de transacción cargados.'
        );

    WHEN e_varray_fuera_rango THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(
          'Error: El VARRAY de tipos de transacción no tiene suficientes elementos.'
        );

    WHEN e_sin_transacciones THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(
          'Error: No existen transacciones para el año ' || :b_anio
        );

    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(
          'Error inesperado: ' || SQLERRM
        );
    
END;