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
CHURNERSCRM AS(
 SELECT DISTINCT RIGHT(CONCAT('0000000000',ACT_ACCT_CD) ,10) AS CONTRATOCRM,  MAX(CST_CHRN_DT) AS Maxfecha
 FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-02-02_CRM_BULK_FILE_FINAL_HISTORIC_DATA_2021_D`
 GROUP BY CONTRATOCRM
    HAVING EXTRACT (MONTH FROM Maxfecha) = EXTRACT (MONTH FROM MAX(FECHA_EXTRACCION)) 
 ),

 CRUCECHURNERS AS(
 SELECT CONTRATOCRM, MaxFecha, i.FechaCancela
 FROM ANULADAS i INNER JOIN CHURNERSCRM c ON i.NOMBRE_CONTRATO=c.CONTRATOCRM
 AND c.MaxFecha > i.FechaCancela AND DATE_DIFF (c.MaxFecha, i.FechaCancela, DAY) <= 60
 GROUP BY contratoCRM, MaxFecha, i.FechaCancela
),

/*Subconsulta que divide los churners y los no churners*/
CHURNFLAGRESULT AS(
SELECT DISTINCT n.NOMBRE_CONTRATO as Contrato , n.FechaApertura, n.FechaCancela,a.FechaAltas,
CASE WHEN c.CONTRATOCRM IS NOT NULL THEN "Churner"
WHEN c.CONTRATOCRM IS NULL THEN "NonChurner" end as ChurnFlag
FROM ANULADAS n 
INNER JOIN ALTAS a ON n.NOMBRE_CONTRATO=a.Contrato
LEFT JOIN CRUCECHURNERS c ON n.NOMBRE_CONTRATO = c.CONTRATOCRM
GROUP BY Contrato, FechaApertura, FechaCancela, ChurnFlag, a.FechaAltas)

/*Consulta final que calcula el tiempo promedio entre la instalación y la fecha de apertura de la anulación por mes con una ventana de tiempo de un mes 
 entre la alta y la anulación y entre la instalación y la anulación*/
SELECT 
EXTRACT(month FROM c.FechaCancela) AS MES, 
ROUND(AVG(EXTRACT(day FROM c.FechaCancela-c.FechaApertura)),2) AS tiempos_prom, 
COUNT (DISTINCT c.Contrato) AS Registros
FROM CHURNFLAGRESULT c
WHERE DATE_DIFF(c.FechaApertura  ,c.FechaAltas  ,DAY)<=30
AND DATE_DIFF(c.FechaCancela ,c.FechaApertura , DAY )<=30
AND c.FechaCancela >c.FechaAltas
--AND c.FechaApertura >c.FechaAltas
--AND c.FechaCancela>c.FechaApertura
AND ChurnFlag = "Churner"
--AND ChurnFlag = "NonChurner"
GROUP BY MES ORDER BY MES
