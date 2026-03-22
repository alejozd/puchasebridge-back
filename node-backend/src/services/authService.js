const env = require('../config/env');
const { findUserByName, findEmpresa } = require('../repositories/authRepository');
const { createSession, getSession } = require('../utils/authStore');
const { AppError } = require('../utils/errors');

const login = async (usuario, clave) => {
  const user = await findUserByName(usuario);
  if (!user) throw new AppError('Usuario no encontrado', 401);
  if (String(user.CLAVE) !== String(clave)) throw new AppError('Clave incorrecta', 401);

  const empresa = await findEmpresa(env.helisa.empresa);
  if (!empresa) throw new AppError('Configuración de empresa no válida en Helisa', 500);

  const token = createSession({ codigo: user.CODIGO, nombre: user.NOMBRE });

  return {
    usuario: { codigo: user.CODIGO, nombre: user.NOMBRE },
    empresa: {
      codigo: empresa.CODIGO,
      nombre: empresa.NOMBRE,
      identidad: empresa.IDENTIDAD,
      anoActual: empresa.ANOACTUAL,
      tarifaReteCree: empresa.TARIFA_RETE_CREE,
    },
    success: true,
    token,
  };
};

const validateToken = (token) => {
  const session = getSession(token);
  if (!session) throw new AppError('Token inválido', 401);
  return session;
};

module.exports = { login, validateToken };
