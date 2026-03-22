const { execute, getBridgeOptions } = require('../config/firebird');

const buscarEquivalencia = async (referenciaP, unidadP) =>
  execute(getBridgeOptions(), 'SELECT * FROM EQUIVALENCIA WHERE REFERENCIAP = ? AND UNIDADP = ?', [referenciaP, unidadP]);

const existeEquivalencia = async (referenciaP, unidadP) => {
  const rows = await buscarEquivalencia(referenciaP, unidadP);
  return rows.length > 0;
};

const crearEquivalencia = async (payload) =>
  execute(
    getBridgeOptions(),
    `INSERT INTO EQUIVALENCIA (CODIGOH, SUBCODIGOH, NOMBREH, REFERENCIAH, UNIDADH, UNIDADP, REFERENCIAP, FACTOR)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      payload.codigoH,
      payload.subCodigoH,
      payload.nombreH,
      payload.referenciaH,
      payload.unidadH,
      payload.unidadP,
      payload.referenciaP,
      payload.factor,
    ],
  );

const eliminarEquivalencia = async (referenciaP, unidadP) => {
  await execute(getBridgeOptions(), 'DELETE FROM EQUIVALENCIA WHERE REFERENCIAP = ? AND UNIDADP = ?', [referenciaP, unidadP]);
  return true;
};

const listarEquivalencias = async ({ referenciaP = '', unidadP = '', limite = 50 }) => {
  let sql = 'SELECT FIRST ? * FROM EQUIVALENCIA WHERE 1=1';
  const params = [limite];
  if (referenciaP.trim()) {
    sql += ' AND REFERENCIAP = ?';
    params.push(referenciaP);
  }
  if (unidadP.trim()) {
    sql += ' AND UNIDADP = ?';
    params.push(unidadP);
  }
  return execute(getBridgeOptions(), sql, params);
};

module.exports = { buscarEquivalencia, existeEquivalencia, crearEquivalencia, eliminarEquivalencia, listarEquivalencias };
