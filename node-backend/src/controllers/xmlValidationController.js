const fs = require('fs/promises');
const path = require('path');
const env = require('../config/env');
const { validateFile } = require('../services/xmlService');

const validate = async (req, res) => {
  const fileName = req.body?.fileName;
  if (!fileName) return res.status(400).json({ success: false, message: 'fileName is required in the body' });
  return res.json(await validateFile(path.basename(fileName)));
};

const validateBatch = async (req, res) => {
  let files = (req.body?.files || []).map((f) => path.basename(String(f)));
  if (!files.length) {
    try {
      const all = await fs.readdir(env.paths.inputDir);
      files = all.filter((f) => f.toLowerCase().endsWith('.xml'));
    } catch {
      files = [];
    }
  }

  const documentos = [];
  let validos = 0;
  let conErrores = 0;
  for (const fileName of files) {
    const result = await validateFile(fileName);
    if (result.valido) validos += 1;
    else conErrores += 1;
    documentos.push(result);
  }

  return res.json({ documentos, resumen: { total: files.length, validos, conErrores } });
};

module.exports = { validate, validateBatch };
