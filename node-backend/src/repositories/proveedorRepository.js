const { execute, getHelisaCompanyOptions } = require('../config/firebird');
const { currentYear } = require('../utils/date');

const validarAnio = (anio) => (/^\d{4}$/.test(String(anio || '')) ? String(anio) : currentYear());

const obtenerProveedorPorNit = async (nitProveedor, anio = '') => {
  const year = validarAnio(anio);
  const tableName = `CPMA${year}`;
  const rows = await execute(
    getHelisaCompanyOptions('0'),
    `SELECT CODIGO FROM ${tableName} WHERE TRIM(IDENTIDAD) = ?`,
    [nitProveedor],
  );

  if (!rows.length) return { existe: false, codigo: '' };
  return { existe: true, codigo: String(rows[0].CODIGO || '') };
};

module.exports = { validarAnio, obtenerProveedorPorNit };
