const { procesarDocumentos } = require('../services/documentoService');

const procesar = async (req, res) => {
  const result = await procesarDocumentos({ files: req.body?.files || [], session: req.session });
  return res.json(result);
};

module.exports = { procesar };
