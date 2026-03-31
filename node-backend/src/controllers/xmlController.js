const fs = require('fs/promises');
const path = require('path');
const env = require('../config/env');
const { upload, listXmlFiles, parseXmlFromFile } = require('../services/xmlService');

const list = async (req, res) => res.json(await listXmlFiles());

const uploadMiddleware = upload.single('file');

const uploadXml = async (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded with field name "file"' });
  if (path.extname(req.file.originalname).toLowerCase() !== '.xml') return res.status(400).json({ success: false, message: 'The file must have a .xml extension' });

  await fs.mkdir(env.paths.inputDir, { recursive: true });
  const target = path.join(env.paths.inputDir, path.basename(req.file.originalname));
  await fs.rename(req.file.path, target);

  return res.json({ success: true, message: 'XML uploaded successfully', fileName: path.basename(req.file.originalname), path: target.replace(/\\/g, '/') });
};

const parse = async (req, res) => {
  const fileName = req.body?.fileName;
  if (!fileName) return res.status(400).json({ success: false, message: 'fileName is required in the body' });

  const parsed = await parseXmlFromFile(fileName);
  return res.json({ success: true, proveedor: parsed.provider, productos: parsed.products, totales: parsed.totals });
};

module.exports = { list, uploadMiddleware, uploadXml, parse };
