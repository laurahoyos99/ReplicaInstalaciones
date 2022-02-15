WITH
  /* Subconsulta que extrae las instalaciones finalizadas en 2021*/
  INSTALACIONES2021 AS(
  SELECT
    DISTINCT RIGHT(CONCAT('0000000000',NOMBRE_CONTRATO) ,10) AS NOMBRE_CONTRATO,FECHA_APERTURA as FechaApertura,FECHA_FINALIZACION as FechaInst,NO_ORDEN
  FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_ORDENES_SERVICIO_2021-01_A_2021-11_D`
  WHERE
    EXTRACT(year FROM FECHA_APERTURA) = 2021 AND TIPO_ORDEN ="INSTALACION"
    AND MOTIVO_ORDEN = "INSTALACION-Orden de servicio" AND ESTADO = "FINALIZADA" AND FECHA_APERTURA IS NOT NULL AND FECHA_FINALIZACION IS NOT NULL
  GROUP BY
    NO_ORDEN, NOMBRE_CONTRATO,FECHA_APERTURA,FECHA_FINALIZACION ),
  /* Subconsulta que extrae las ventas nuevas de las altas - por ajustar con nueva base*/
  ALTAS AS (
  SELECT DISTINCT RIGHT(CONCAT('0000000000',CONTRATO) ,10) AS Contrato, MAX(Formato_Fecha) AS fecha
  FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-20_CR_ALTAS_V3_2021-01_A_2021-12_T`
 WHERE
  Tipo_Venta="Nueva"
  AND (Tipo_Cliente = "PROGRAMA HOGARES CONECTADOS" OR Tipo_Cliente="RESIDENCIAL" OR Tipo_Cliente="EMPLEADO")
  AND extract(year from Formato_Fecha) = 2021 
  AND Subcanal__Venta<>"OUTBOUND PYMES" AND Subcanal__Venta<>"INBOUND PYMES" AND Subcanal__Venta<>"HOTELERO" AND Subcanal__Venta<>"PYMES – NETCOM" 
  AND Tipo_Movimiento= "Altas por venta"
  GROUP BY contrato ),

CHURNERSSO AS(
 SELECT DISTINCT RIGHT(CONCAT('0000000000',c.NOMBRE_CONTRATO) ,10) AS CONTRATOSO, FECHA_APERTURA
 FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_ORDENES_SERVICIO_2021-01_A_2021-11_D` c 
 INNER JOIN INSTALACIONES2021 i on RIGHT(CONCAT('0000000000',c.NOMBRE_CONTRATO) ,10) = i.NOMBRE_CONTRATO
 WHERE
  TIPO_ORDEN = "DESINSTALACION" AND (ESTADO <> "CANCELADA" OR ESTADO <> "ANULADA") AND FECHA_APERTURA IS NOT NULL
  AND c.FECHA_APERTURA > i.FechaInst AND DATE_DIFF (c.FECHA_APERTURA, i.FechaInst, DAY) <= 60
 ORDER BY CONTRATOSO),

 CHURNERSCRM AS(
 SELECT DISTINCT RIGHT(CONCAT('0000000000',ACT_ACCT_CD) ,10) AS CONTRATOCRM,  MAX(CST_CHRN_DT) AS Maxfecha
 FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-02-02_CRM_BULK_FILE_FINAL_HISTORIC_DATA_2021_D`
 GROUP BY CONTRATOCRM
    HAVING EXTRACT (MONTH FROM Maxfecha) = EXTRACT (MONTH FROM MAX(FECHA_EXTRACCION)) 
 ),

 CRUCECHURNERS AS(
 SELECT CONTRATOSO, CONTRATOCRM, FECHA_APERTURA
 FROM CHURNERSCRM c LEFT JOIN CHURNERSSO s ON CONTRATOSO = CONTRATOCRM 
 AND c.Maxfecha >= s.FECHA_APERTURA AND date_diff(c.Maxfecha, s.FECHA_APERTURA, MONTH) <= 3
 GROUP BY contratoso, contratoCRM, FECHA_APERTURA
),

CHURNFLAGRESULT AS(
  SELECT DISTINCT i.NOMBRE_CONTRATO as Contrato , i.FechaApertura, i.FechaInst,
  CASE WHEN c.CONTRATOSO IS NOT NULL THEN "Churner"
  WHEN c.CONTRATOSO IS NULL THEN "NonChurner" end as ChurnFlag
  FROM INSTALACIONES2021 i INNER JOIN ALTAS a ON i.NOMBRE_CONTRATO = a.CONTRATO LEFT JOIN CRUCECHURNERS c ON i.NOMBRE_CONTRATO = c.CONTRATOSO
  GROUP BY Contrato, FechaApertura, FechaInst, ChurnFlag)

SELECT EXTRACT(month FROM c.FechaInst) AS MES, ROUND(AVG(EXTRACT(day FROM c.FechaInst-c.FechaApertura)),2) AS tiempos_instalacion_prom, COUNT (DISTINCT c.Contrato) AS Registros
FROM CHURNFLAGRESULT c
--WHERE ChurnFlag = "Churner"
--WHERE ChurnFlag = "NonChurner"
GROUP BY MES
ORDER BY MES
