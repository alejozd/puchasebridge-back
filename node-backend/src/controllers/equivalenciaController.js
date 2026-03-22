const service = require('../services/equivalenciaService');

const list = async (req, res) => {
  const data = await service.list(req.query.referenciaP || '', req.query.unidadP || '', Number(req.query.limite || 50));
  return res.json(data);
};

const create = async (req, res) => {
  const data = await service.create(req.body || {});
  return res.status(201).json(data);
};

const remove = async (req, res) => {
  const data = await service.remove(req.query.referenciaP, req.query.unidadP);
  return res.json(data);
};

module.exports = { list, create, remove };
