-- Binds
VARIABLE b_mes NUMBER;
VARIABLE b_anio NUMBER;

-- Asignacion de la fecha
EXECUTE :b_mes := EXTRACT(MONTH FROM SYSDATE);
EXECUTE :b_anio := EXTRACT(YEAR  FROM SYSDATE);

-- Inicio del proceso
DECLARE
    -- Escalares
    v_mes NUMBER := :b_mes;
    v_anio NUMBER := :b_anio;
    v_contador NUMBER := 0;
    v_estado_civil estado_civil.nombre_estado_civil%TYPE;
    v_primer_nombre  empleado.pnombre_emp%TYPE;
    v_segundo_nombre empleado.snombre_emp%TYPE; 
    v_amemp empleado.apmaterno_emp%TYPE;
    v_appemp  empleado.appaterno_emp%TYPE;
    v_sueldo empleado.sueldo_base%TYPE;
    v_fecha_contrato empleado.fecha_contrato%TYPE;
    v_dvrun empleado.dvrun_emp%TYPE;
    v_run empleado.numrun_emp%TYPE;
    v_fecha_nac empleado.fecha_nac%TYPE;
    v_usuario_generado VARCHAR(100) := '';
    v_clave_generada VARCHAR(100) := '';
    v_id_estado_civil estado_civil.id_estado_civil%TYPE;
    
BEGIN
    -- Truncar la tabla al inicio
    EXECUTE IMMEDIATE 'TRUNCATE TABLE usuario_clave';
    
    -- Se comienza a iterar por los empleados
    FOR r IN (SELECT id_emp FROM empleado) LOOP

        -- se extraen los datos del usuario      
        SELECT 
            e.pnombre_emp,
            e.snombre_emp,
            e.appaterno_emp,
            e.apmaterno_emp,
            e.sueldo_base,
            e.fecha_contrato,
            e.dvrun_emp,
            e.numrun_emp,
            e.fecha_nac,
            ec.nombre_estado_civil,
            ec.id_estado_civil
        INTO
            v_primer_nombre,
            v_segundo_nombre,
            v_appemp,
            v_amemp,
            v_sueldo,
            v_fecha_contrato,
            v_dvrun,
            v_run,
            v_fecha_nac,
            v_estado_civil,
            v_id_estado_civil
        FROM
            empleado e JOIN estado_civil ec ON e.id_estado_civil = ec.id_estado_civil
        WHERE
            e.id_emp = r.id_emp;
        
        -- creacion nombre de usuario
        -- primera letra de su estado civil en minuscula
        v_usuario_generado := v_usuario_generado || LOWER(SUBSTR(v_estado_civil, 1, 1));
        
        -- tres primeras letras del primer nombre del empleado
        v_usuario_generado := v_usuario_generado || UPPER(SUBSTR(v_primer_nombre, 1, 3));
        
        -- largo de su primer nombre
        v_usuario_generado := v_usuario_generado || LENGTH(v_primer_nombre);
        
        -- asterisco
        v_usuario_generado := v_usuario_generado || '*';
        
        -- El último dígito de su sueldo base 
        v_usuario_generado := v_usuario_generado || SUBSTR(TO_CHAR(v_sueldo), -1);
        
        -- dígito verificador del run del empleado.
        v_usuario_generado := v_usuario_generado || v_dvrun;
        
        -- años que lleva trabajando en la empresa agregando X de ser necesario
        v_usuario_generado := v_usuario_generado || (v_anio - EXTRACT(YEAR FROM v_fecha_contrato));
        IF (v_anio - EXTRACT(YEAR FROM v_fecha_contrato)) < 10 THEN
            v_usuario_generado := v_usuario_generado || 'X';
        END IF;
        
        -- creacion clave de usuario
        -- tercer dígito del run del empleado
        v_clave_generada := v_clave_generada || SUBSTR(TO_CHAR(v_run), 3, 1);
        
        -- año de nacimiento del empleado aumentado en dos
        v_clave_generada := v_clave_generada || (EXTRACT(YEAR FROM v_fecha_contrato) + 2);
        
        -- tres últimos dígitos del sueldo base disminuido en uno
        v_clave_generada := v_clave_generada || SUBSTR(TO_CHAR(v_sueldo - 1), -3);
        
        --  letras de su apellido paterno, en minúscula, segun corresponda
        CASE
            WHEN v_id_estado_civil = 10 OR v_id_estado_civil = 60 THEN
                v_clave_generada := v_clave_generada || LOWER(SUBSTR(v_appemp, 1, 2));
            WHEN v_id_estado_civil = 20 OR v_id_estado_civil = 30 THEN
                v_clave_generada := v_clave_generada || LOWER(SUBSTR(v_appemp, 1, 1)) || LOWER(SUBSTR(v_appemp, -1));
            WHEN v_id_estado_civil = 40 THEN
                v_clave_generada := v_clave_generada || LOWER(SUBSTR(v_appemp, -3, 2));
            ELSE 
                v_clave_generada := v_clave_generada || LOWER(SUBSTR(v_appemp, -2));
        END CASE;
        
        -- identificación del empleado
        v_clave_generada := v_clave_generada || r.id_emp;
        
        -- mes y año de la base de datos
        v_clave_generada := v_clave_generada || v_mes || v_anio;
        
        -- se inserta la fila en la tabla usuario_clave
        INSERT INTO usuario_clave
        VALUES(
            r.id_emp,
            v_run,
            v_dvrun,
            v_primer_nombre ||' '|| v_segundo_nombre ||' '|| v_appemp ||' '|| v_amemp,
            v_usuario_generado,
            v_clave_generada
        );
  
        -- se aumenta el contador y resetean las variables
        v_contador := v_contador + 1;
        v_usuario_generado := '';
        v_clave_generada := '';
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('Empleados procesados: ' || v_contador);
    
    -- Se confirma la insercion
    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No se encontro ningun dato.');
    WHEN DUP_VAL_ON_INDEX THEN
      DBMS_OUTPUT.PUT_LINE('ID duplicado, no se inserta');
      ROLLBACK;
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;