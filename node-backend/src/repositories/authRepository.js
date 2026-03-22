const { execute, getHelisaMainOptions } = require('../config/firebird');

const findUserByName = async (username) => {
  const rows = await execute(getHelisaMainOptions(), 'SELECT CODIGO, NOMBRE, CLAVE FROM USUARIOS WHERE NOMBRE = ?', [username]);
  return rows[0] || null;
};

const findEmpresa = async (empresaCode) => {
  const rows = await execute(
    getHelisaMainOptions(),
    'SELECT CODIGO, NOMBRE, IDENTIDAD, ANOACTUAL, TARIFA_RETE_CREE FROM DIRECTOR WHERE CODIGO = ?',
    [empresaCode],
  );
  return rows[0] || null;
};

module.exports = { findUserByName, findEmpresa };
