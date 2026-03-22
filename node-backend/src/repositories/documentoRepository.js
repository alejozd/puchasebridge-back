const { execute, withTransaction, getBridgeOptions, getHelisaMainOptions } = require('../config/firebird');

const documentoExiste = async (xmlFileName) => {
  const rows = await execute(getBridgeOptions(), 'SELECT ID FROM DOCUMENTO WHERE XML_FILENAME = ?', [xmlFileName]);
  return rows.length > 0;
};

const guardarDocumento = async ({ header, detalles, insertarOrdenCompra }) =>
  withTransaction(getBridgeOptions(), async (query) => {
    const ins = await query(
      'INSERT INTO DOCUMENTO (PROVEEDOR, FECHA, TOTAL, ESTADO, XML_FILENAME) VALUES (?, ?, ?, ?, ?) RETURNING ID',
      [header.proveedor, header.fecha, header.total, header.estado, header.xmlFileName],
    );
    const documentoId = ins[0].ID;

    for (const d of detalles) {
      await query(
        'INSERT INTO DOCUMENTO_DETALLE (DOCUMENTO_ID, CODIGO_PRODUCTO, CANTIDAD, PRECIO, TOTAL) VALUES (?, ?, ?, ?, ?)',
        [documentoId, d.codigoProducto, d.cantidad, d.precio, d.total],
      );
    }

    const documentoERP = await insertarOrdenCompra();
    await query('UPDATE DOCUMENTO SET ESTADO = ? WHERE ID = ?', [documentoERP, documentoId]);
    return documentoERP;
  });

const executeHelisa = async (sql, params = []) => execute(getHelisaMainOptions(), sql, params);

module.exports = { documentoExiste, guardarDocumento, executeHelisa };
