const repo = require('../repositories/equivalenciaRepository');
const { AppError } = require('../utils/errors');

const list = async (referenciaP = '', unidadP = '', limite = 50) => ({
  equivalencias: await repo.listarEquivalencias({ referenciaP, unidadP, limite }),
});

const create = async (body) => {
  if (body.codigoH == null) throw new AppError('codigoH is required', 400);
  if (!String(body.referenciaP || '').trim()) throw new AppError('referenciaP cannot be empty', 400);
  if (!String(body.unidadP || '').trim()) throw new AppError('unidadP cannot be empty', 400);
  if (!(Number(body.factor) > 0)) throw new AppError('factor must be greater than 0', 400);

  const exists = await repo.existeEquivalencia(body.referenciaP, body.unidadP);
  if (exists) throw new AppError('La equivalencia ya existe', 409);

  await repo.crearEquivalencia(body);
  return { success: true, message: 'Equivalencia creada correctamente' };
};

const remove = async (referenciaP, unidadP) => {
  if (!String(referenciaP || '').trim()) throw new AppError('El parámetro "referenciaP" es obligatorio', 400);
  if (!String(unidadP || '').trim()) throw new AppError('El parámetro "unidadP" es obligatorio', 400);
  const success = await repo.eliminarEquivalencia(referenciaP, unidadP);
  return { success, message: success ? 'Equivalencia eliminada correctamente' : 'No se encontró la equivalencia para eliminar' };
};

module.exports = { list, create, remove };
