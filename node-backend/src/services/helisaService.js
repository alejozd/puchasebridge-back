const { executeHelisa } = require('../repositories/documentoRepository');
const { toHeDate } = require('../utils/date');

const formatDocumentNumber = (tipo, consecutivo) => `${String(tipo || '').trim()}${String(consecutivo || 0).padStart(8, '0')}`;

const insertarOrdenCompra = async ({ header, detalles }) => {
  const suffix = header.anio;
  const docu = `DOCU${suffix}`;
  const ocma = `OCMA${suffix}`;
  const octr = `OCTR${suffix}`;

  const docuRows = await executeHelisa(`SELECT FIRST 1 TIPO, CONSECUTIVO FROM ${docu} WHERE MODULO = 10 AND CLASE = 31`);
  if (!docuRows.length) throw new Error('No se encontró configuración de Orden de Compra en DOCUXXXX');

  const tipo = docuRows[0].TIPO;
  const consecutivo = docuRows[0].CONSECUTIVO;
  const documento = formatDocumentNumber(tipo, consecutivo);

  for (let i = 0; i < detalles.length; i += 1) {
    const d = detalles[i];
    await executeHelisa(
      `INSERT INTO ${octr} (DOCUMENTO, CONSECUTIVO, CLASE, CODIGO_BODEGA, CODIGO_CONCEPTO, SUBCODIGO, LISTAPRECIO, CANTIDAD, UNIDADES_DEVUELTAS, VR_UNITARIO, VR_TOTAL, TF_IVA, VR_IVA, TF_DESCUENTO, VR_DESCUENTO, VR_ICA, VR_RETEICA, VR_RETEIVA, VR_RETEFUENTE, HACE_PARTE_COSTO, HACE_PARTE_COSTO_NIIF, DISPERSION) VALUES (?, ?, ?, 1, ?, ?, 0, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'N', 'N', 'N')`,
      [documento, i + 1, d.clase, d.codigoConcepto, d.subcodigo, d.cantidad, d.valorUnitario, d.valorTotal, d.tfIva, d.vrIva, d.tfDescuento, d.vrDescuento, d.vrIca, d.vrReteIca, d.vrReteIva, d.vrReteFuente],
    );
  }

  const totals = await executeHelisa(`SELECT SUM(VR_TOTAL) AS ART_BRUTO, SUM(VR_DESCUENTO) AS ART_DESC, SUM(VR_IVA) AS ART_IVA, SUM(VR_ICA) AS ART_ICA, SUM(VR_RETEICA) AS TOTAL_RETEICA, SUM(VR_RETEIVA) AS TOTAL_RETEIVA, SUM(VR_RETEFUENTE) AS TOTAL_RETEFUENTE FROM ${octr} WHERE DOCUMENTO = ?`, [documento]);
  const t = totals[0] || {};

  await executeHelisa(
    `INSERT INTO ${ocma} (DOCUMENTO, FECHA, CODIGO_TERCERO, CLASE_FAC, ESTADO_DOCUMENTO, ART_TOTAL_BRUTO, ART_TOTAL_DESCUENTO, ART_TOTAL_IVA, ART_TOTAL_ICA, TOTAL_RETEICA, TOTAL_RETEIVA, TOTAL_RETEFUENTE, TASA_CAMBIO, NOMBRE_PANTALLA, NOMBRE_USUARIO, CODIGO_USUARIO, FECHA_SISTEMA) VALUES (?, ?, ?, 1, 1, ?, ?, ?, ?, ?, ?, ?, 1, 'PURCHASE', ?, ?, CURRENT_TIMESTAMP)`,
    [documento, toHeDate(header.fecha), header.codigoTercero, t.ART_BRUTO || 0, t.ART_DESC || 0, t.ART_IVA || 0, t.ART_ICA || 0, t.TOTAL_RETEICA || 0, t.TOTAL_RETEIVA || 0, t.TOTAL_RETEFUENTE || 0, header.nombreUsuario, header.codigoUsuario],
  );

  await executeHelisa(`UPDATE ${docu} SET CONSECUTIVO = CONSECUTIVO + 1 WHERE MODULO = 10 AND CLASE = 31`);
  return documento;
};

module.exports = { insertarOrdenCompra };
