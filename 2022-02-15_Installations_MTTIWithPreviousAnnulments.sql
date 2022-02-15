WITH 
/*Subconsulta que extrae las ventas nuevas del 2021*/
ALTAS AS (
SELECT distinct RIGHT(CONCAT('0000000000',CONTRATO) ,10) AS Contrato,Formato_Fecha AS FechaAltas
FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-20_CR_ALTAS_V3_2021-01_A_2021-12_T` 
WHERE
Tipo_Venta="Nueva"
AND (Tipo_Cliente = "PROGRAMA HOGARES CONECTADOS" OR Tipo_Cliente="RESIDENCIAL" OR Tipo_Cliente="EMPLEADO")
AND extract(year from Formato_Fecha) = 2021 
AND Subcanal__Venta<>"OUTBOUND PYMES" AND Subcanal__Venta<>"INBOUND PYMES" AND Subcanal__Venta<>"HOTELERO" AND Subcanal__Venta<>"PYMES – NETCOM" 
AND Tipo_Movimiento= "Altas por venta" 
GROUP BY contrato, Formato_Fecha
),
/*Subconsulta que extrae las instalaciones finalizadas del 2021 y su respectiva fecha*/
INSTALACIONES AS (
SELECT
DISTINCT RIGHT(CONCAT('0000000000',NOMBRE_CONTRATO) ,10) AS NOMBRE_CONTRATO,FECHA_FINALIZACION as FechaInst, NO_ORDEN
FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_ORDENES_SERVICIO_2021-01_A_2021-11_D`
WHERE
EXTRACT(year FROM FECHA_APERTURA) = 2021 
AND TIPO_ORDEN ="INSTALACION"AND MOTIVO_ORDEN = "INSTALACION-Orden de servicio" 
AND ESTADO = "FINALIZADA"
AND FECHA_APERTURA IS NOT NULL AND FECHA_FINALIZACION IS NOT NULL
GROUP BY NO_ORDEN, NOMBRE_CONTRATO,FECHA_FINALIZACION
),
/*Subconsulta que extrae las instalaciones anuladas y sus fechas de apertura y finalización*/
ANULADAS AS (
SELECT
DISTINCT RIGHT(CONCAT('0000000000',NOMBRE_CONTRATO) ,10) AS NOMBRE_CONTRATO,FECHA_APERTURA as FechaApertura,FECHA_FINALIZACION as FechaCancela, NO_ORDEN
FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_ORDENES_SERVICIO_2021-01_A_2021-11_D`
WHERE
EXTRACT(year FROM FECHA_APERTURA) = 2021 
AND TIPO_ORDEN ="INSTALACION"AND MOTIVO_ORDEN = "INSTALACION-Orden de servicio" 
AND ESTADO = "ANULADA"  
AND FECHA_APERTURA IS NOT NULL AND FECHA_FINALIZACION IS NOT NULL
GROUP BY NO_ORDEN, NOMBRE_CONTRATO,FECHA_APERTURA, FECHA_FINALIZACION
),

/*Subconsulta que define los churners como contratos con desinstalaciones finalizadas que sucedieron 2 meses máximo después de la instalación finalizada*/
CHURNERSSO AS (
 SELECT DISTINCT RIGHT(CONCAT('0000000000',c.NOMBRE_CONTRATO) ,10) AS CONTRATOSO, FECHA_APERTURA
 FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_ORDENES_SERVICIO_2021-01_A_2021-11_D` c 
 INNER JOIN INSTALACIONES  i on RIGHT(CONCAT('0000000000',c.NOMBRE_CONTRATO) ,10) = i.NOMBRE_CONTRATO
 WHERE
  TIPO_ORDEN = "DESINSTALACION" AND (ESTADO <> "CANCELADA" OR ESTADO <> "ANULADA") AND FECHA_APERTURA IS NOT NULL
  AND FECHA_APERTURA > i.FechaInst   AND DATE_DIFF ( FECHA_APERTURA, i.FechaInst, DAY) <= 60
 ORDER BY CONTRATOSO
),

CHURNERSCRM AS
( SELECT DISTINCT RIGHT(CONCAT('0000000000',ACT_ACCT_CD) ,10) AS CONTRATOCRM,  MAX(CST_CHRN_DT) AS Maxfecha
FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-02-02_CRM_BULK_FILE_FINAL_HISTORIC_DATA_2021_D`
 GROUP BY CONTRATOCRM
    HAVING EXTRACT (MONTH FROM Maxfecha) = EXTRACT (MONTH FROM MAX(FECHA_EXTRACCION)) 
),

CRUCECHURNERS AS(
SELECT CONTRATOSO, CONTRATOCRM, EXTRACT (MONTH FROM c.Maxfecha) AS MesC, 
EXTRACT(MONTH FROM s.FECHA_APERTURA ) AS MesS
FROM CHURNERSCRM c LEFT JOIN CHURNERSSO s ON CONTRATOSO = CONTRATOCRM 
AND c.Maxfecha >= s.FECHA_APERTURA AND date_diff(c.Maxfecha, s.FECHA_APERTURA, MONTH) <= 3
GROUP BY contratoso, contratoCRM, MesC, MesS
),

/*Subconsulta que divide los churners y los no churners*/
CHURNFLAGRESULT AS(
SELECT DISTINCT n.NOMBRE_CONTRATO as Contrato , n.FechaApertura, n.FechaCancela,a.FechaAltas,i.FechaInst,
CASE WHEN c.CONTRATOSO IS NOT NULL THEN "Churner"
WHEN c.CONTRATOSO IS NULL THEN "NonChurner" end as ChurnFlag
FROM ANULADAS n 
INNER JOIN ALTAS a ON n.NOMBRE_CONTRATO=a.Contrato
INNER JOIN INSTALACIONES  i ON a.Contrato=i.NOMBRE_CONTRATO
LEFT JOIN CRUCECHURNERS c ON n.NOMBRE_CONTRATO = c.CONTRATOSO
GROUP BY Contrato, FechaApertura, FechaCancela, ChurnFlag, a.FechaAltas, i.FechaInst)

/*Consulta final que calcula el tiempo promedio entre la instalación y la fecha de apertura de la anulación por mes con una ventana de tiempo de un mes 
 entre la alta y la anulación y entre la instalación y la anulación*/
SELECT 
EXTRACT(month FROM c.FechaCancela) AS MES, 
ROUND(AVG(EXTRACT(day FROM c.FechaInst-c.FechaApertura)),2) AS tiempos_prom, 
COUNT (DISTINCT c.Contrato) AS Registros
FROM CHURNFLAGRESULT c
WHERE DATE_DIFF(c.FechaApertura  ,c.FechaAltas  ,DAY)<=30
AND DATE_DIFF(c.FechaInst ,c.FechaApertura , DAY )<=30
AND c.FechaInst >c.FechaAltas
AND c.FechaApertura >c.FechaAltas
AND c.FechaInst>FechaApertura
AND c.FechaInst>c.FechaApertura
--AND ChurnFlag = "Churner"
--AND ChurnFlag = "NonChurner"
GROUP BY MES ORDER BY MES
