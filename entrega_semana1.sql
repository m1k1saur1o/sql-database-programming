 -- caso 1

 -- ingresar run con puntos y guion: 11.111.111-1
 -- valores menores a v_tramo_1 estaran en el tramo 1
 -- v_tramo_2_inicio marca el inicio del tramo 2 y v_tramo_2_fin su final
 -- los valores mayores a v_tramo_2_fin estaran en el tramo 3
 
 DECLARE
    v_run VARCHAR2(30) := '&v_run';
    v_tramo_1 NUMBER := &v_tramo_1;
    v_tramo_2_inicio NUMBER := &v_tramo_2_inicio;
    v_tramo_2_fin NUMBER := &v_tramo_2_fin;
    v_pesos_normales NUMBER := &v_pesos_normales;
    v_pesos_extra_tramo_1 NUMBER := &v_pesos_extra_tramo_1;
    v_pesos_extra_tramo_2 NUMBER := &v_pesos_extra_tramo_2;
    v_pesos_extra_tramo_3 NUMBER := &v_pesos_extra_tramo_3;
    v_nro_cliente cliente.nro_cliente%TYPE;
    v_nombre_completo VARCHAR2(100);
    v_tipo_cliente tipo_cliente.nombre_tipo_cliente%TYPE;
    v_monto_creditos NUMBER;
    v_monto_suma NUMBER;
    v_cod_tipo_cliente cliente.cod_tipo_cliente%TYPE;
BEGIN
    -- extranccion de datos de las tablas
    SELECT
        c.nro_cliente,
        c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno,
        tc.nombre_tipo_cliente,
        c.cod_tipo_cliente,
        SUM(cc.monto_solicitado)
    INTO
        -- asignacion a las variables
        v_nro_cliente,
        v_nombre_completo,
        v_tipo_cliente,
        v_cod_tipo_cliente,
        v_monto_creditos      
    FROM
        cliente c JOIN credito_cliente cc ON c.nro_cliente = cc.nro_cliente
        JOIN tipo_cliente tc ON c.cod_tipo_cliente = tc.cod_tipo_cliente
    WHERE
        EXTRACT(YEAR FROM cc.fecha_otorga_cred) = EXTRACT(YEAR FROM SYSDATE) - 1
        AND REPLACE(TO_CHAR(c.numrun, '99G999G999', 'NLS_NUMERIC_CHARACTERS='',.''' ) || '-' || c.dvrun, ' ', '') = REPLACE(v_run, ' ', '')
    GROUP BY
        c.nro_cliente,
        c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno,
        tc.nombre_tipo_cliente,
        c.cod_tipo_cliente;
    
    -- calculo del monto de todosuma
    IF v_cod_tipo_cliente = 2 THEN
        IF v_monto_creditos < v_tramo_1 THEN
            v_monto_suma := FLOOR(v_monto_creditos / 100000) * (v_pesos_normales + v_pesos_extra_tramo_1);
        ELSIF v_monto_creditos > v_tramo_2_inicio AND v_monto_creditos < v_tramo_2_fin THEN
            v_monto_suma := FLOOR(v_monto_creditos / 100000) * (v_pesos_normales + v_pesos_extra_tramo_2);
        ELSE 
            v_monto_suma := FLOOR(v_monto_creditos / 100000) * (v_pesos_normales + v_pesos_extra_tramo_3);
        END IF;
    ELSE
        v_monto_suma := FLOOR(v_monto_creditos / 100000) * v_pesos_normales;
    END IF;
    
    -- borrar la fila con el cliente si ya existe
    DELETE FROM CLIENTE_TODOSUMA
    WHERE NRO_CLIENTE = v_nro_cliente;
    
    -- insercion de la nueva fila
    INSERT INTO CLIENTE_TODOSUMA
    (
        NRO_CLIENTE,
        RUN_CLIENTE,
        NOMBRE_CLIENTE,
        TIPO_CLIENTE,
        MONTO_SOLIC_CREDITOS,
        MONTO_PESOS_TODOSUMA
    )
    VALUES
    (
        v_nro_cliente,
        v_run,
        v_nombre_completo,
        v_tipo_cliente,
        v_monto_creditos,
        v_monto_suma
    );
    COMMIT;
    
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Cliente no encontrado.');
        WHEN TOO_MANY_ROWS THEN
            DBMS_OUTPUT.PUT_LINE('Existe más de un cliente con ese nombre.');
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('Error inesperado: ' || SQLERRM);
END;

-- caso 2

DECLARE
    v_nro_cliente cliente.nro_cliente%TYPE := &v_nro_cliente;
    v_nro_solicitud_credito credito_cliente.nro_solic_credito%TYPE := &v_nro_solicitud_credito;
    v_cantidad_cuotas NUMBER := &v_cantidad_cuotas;
    v_valor_cuota NUMBER;
    v_cod_credito credito.cod_credito%TYPE;
    v_cantidad_creditos_anio_pasado NUMBER;
    v_primera_cuota NUMBER;
    v_segunda_cuota NUMBER;
    v_ultima_cuota  NUMBER;
    v_fecha_ultima_cuota cuota_credito_cliente.fecha_venc_cuota%TYPE;
    
BEGIN
    -- seleccion codigo del credito
    SELECT cod_credito
    INTO v_cod_credito
    FROM credito_cliente
    WHERE nro_cliente = v_nro_cliente AND
    nro_solic_credito = v_nro_solicitud_credito;
    
    -- primera cuota sin pagar para eliminacion
    SELECT MIN(nro_cuota)
    INTO v_primera_cuota
    FROM cuota_credito_cliente
    WHERE nro_solic_credito = v_nro_solicitud_credito AND 
    fecha_pago_cuota IS NULL;
    
    -- ultima cuota para agregar más cuotas a la cola
    SELECT MAX(nro_cuota)
    INTO v_ultima_cuota
    FROM cuota_credito_cliente
    WHERE nro_solic_credito = v_nro_solicitud_credito;
    
    -- fecha de vencimiento de la ultima cuota
    SELECT fecha_venc_cuota
    INTO v_fecha_ultima_cuota
    FROM cuota_credito_cliente
    WHERE nro_cuota = v_ultima_cuota AND
    nro_solic_credito = v_nro_solicitud_credito;
    
    -- valor de la ultima cuota
    SELECT valor_cuota
    INTO v_valor_cuota
    FROM cuota_credito_cliente
    WHERE nro_cuota = v_ultima_cuota AND
    nro_solic_credito = v_nro_solicitud_credito;
    
    -- seleccion cantidad de creditos año pasado
    SELECT COUNT(nro_solic_credito)
    INTO v_cantidad_creditos_anio_pasado
    FROM credito_cliente
    WHERE nro_cliente = v_nro_cliente AND
    EXTRACT(YEAR FROM fecha_otorga_cred) = EXTRACT(YEAR FROM SYSDATE) - 1;
    
    -- condonacion deuda de ultima cuota segun condiciones
    IF v_cantidad_creditos_anio_pasado > 1 THEN
        UPDATE cuota_credito_cliente
        SET fecha_pago_cuota = v_fecha_ultima_cuota
        WHERE nro_solic_credito = v_nro_solicitud_credito AND
        nro_cuota = v_ultima_cuota;         
    END IF;
    
    CASE v_cod_credito
        WHEN 1 THEN
            IF v_cantidad_cuotas = 1 THEN
                
                -- se elimina la primera cuota
                DELETE FROM cuota_credito_cliente
                WHERE nro_solic_credito = v_nro_solicitud_credito AND
                nro_cuota = v_primera_cuota;
                
                -- se agrega la cuota al final con el interes respectivo
                 INSERT INTO cuota_credito_cliente VALUES (
                    v_nro_solicitud_credito,
                    v_ultima_cuota + 1,
                    ADD_MONTHS(v_fecha_ultima_cuota, 1),
                    v_valor_cuota,
                    NULL, 
                    NULL,
                    NULL,
                    NULL
                );
                
                
            ELSE
                -- segunda cuota de ser necesario para caso 1
                SELECT MIN(nro_cuota)
                INTO v_segunda_cuota
                FROM cuota_credito_cliente
                WHERE nro_solic_credito = v_nro_solicitud_credito AND 
                fecha_pago_cuota IS NULL AND 
                nro_cuota > v_primera_cuota;
                
                -- se elimina la primera cuota
                DELETE FROM cuota_credito_cliente
                WHERE nro_solic_credito = v_nro_solicitud_credito AND
                nro_cuota = v_primera_cuota;
                
                -- se elimina la segunda cuota
                DELETE FROM cuota_credito_cliente
                WHERE nro_solic_credito = v_nro_solicitud_credito AND
                nro_cuota = v_segunda_cuota;
                
                INSERT INTO cuota_credito_cliente VALUES (
                    v_nro_solicitud_credito,
                    v_ultima_cuota + 1,
                    ADD_MONTHS(v_fecha_ultima_cuota, 1),
                    ROUND(v_valor_cuota * 1.005),
                    NULL, 
                    NULL,
                    NULL,
                    NULL
                );
                
                INSERT INTO cuota_credito_cliente VALUES (
                    v_nro_solicitud_credito,
                    v_ultima_cuota + 2,
                    ADD_MONTHS(v_fecha_ultima_cuota, 2),
                    ROUND(v_valor_cuota * 1.005),
                    NULL, 
                    NULL,
                    NULL,
                    NULL
                );
                
            END IF;
            
        WHEN 2 THEN
        
            -- se elemina la primera cuota 
            DELETE FROM cuota_credito_cliente
            WHERE nro_solic_credito = v_nro_solicitud_credito AND
            nro_cuota = v_primera_cuota;
            
            -- se agrega la cuota al final con el interes respectivo
            INSERT INTO cuota_credito_cliente VALUES (
                    v_nro_solicitud_credito,
                    v_ultima_cuota + 1,
                    ADD_MONTHS(v_fecha_ultima_cuota, 1),
                    ROUND(v_valor_cuota * 1.01),
                    NULL, 
                    NULL,
                    NULL,
                    NULL
            );
            
        ELSE   
            -- se elemina la primera cuota
            DELETE FROM cuota_credito_cliente
            WHERE nro_solic_credito = v_nro_solicitud_credito AND
            nro_cuota = v_primera_cuota;
            
            -- se agrega la cuota al final con el interes respectivo
            INSERT INTO cuota_credito_cliente VALUES (
                    v_nro_solicitud_credito,
                    v_ultima_cuota + 1,
                    ADD_MONTHS(v_fecha_ultima_cuota, 1),
                    ROUND(v_valor_cuota * 1.02),
                    NULL, 
                    NULL,
                    NULL,
                    NULL
            );
            
    END CASE;
    COMMIT;
    
    EXCEPTION
    WHEN NO_DATA_FOUND THEN
       DBMS_OUTPUT.PUT_LINE('No se encontró algún dato necesario (cuota o crédito).');
    WHEN TOO_MANY_ROWS THEN
       DBMS_OUTPUT.PUT_LINE('Error: más de un registro coincide con la selección.');
    WHEN DUP_VAL_ON_INDEX THEN
       DBMS_OUTPUT.PUT_LINE('Error: la cuota que intenta insertar ya existe.');
    WHEN VALUE_ERROR THEN
       DBMS_OUTPUT.PUT_LINE('Error: conversión de datos o overflow.');
    WHEN OTHERS THEN
       ROLLBACK;
       DBMS_OUTPUT.PUT_LINE('Error inesperado: ' || SQLERRM);
END;