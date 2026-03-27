const { execute, getHelisaCompanyOptions } = require('../config/firebird');

const existeProducto = async (referencia, nombre) => {
  const rows = await execute(
    getHelisaCompanyOptions('0'),
    'SELECT CODIGO FROM INMAXXXX WHERE REFERENCIA = ? AND NOMBRE = ?',
    [referencia, nombre],
  );
  return rows.length > 0;
};

const buscarProductos = async (filtro, limite = 20) =>
  execute(
    getHelisaCompanyOptions('0'),
    'SELECT FIRST ? CODIGO, SUBCODIGO, NOMBRE, REFERENCIA, SUBCODIGO AS UNIDAD FROM INMAXXXX WHERE NOMBRE LIKE ? OR REFERENCIA LIKE ? ORDER BY NOMBRE',
    [limite, `%${String(filtro).toUpperCase()}%`, `%${String(filtro).toUpperCase()}%`],
  );

module.exports = { existeProducto, buscarProductos };
