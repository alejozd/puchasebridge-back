const fs = require('fs/promises');
const path = require('path');
const multer = require('multer');
const env = require('../config/env');
const { parseInvoice } = require('../utils/xmlParser');
const { validarDocumento } = require('./validationService');

const upload = multer({ dest: path.join(env.paths.inputDir, '.tmp') });

const listXmlFiles = async () => {
  try {
    const files = await fs.readdir(env.paths.inputDir);
    const xmlFiles = files.filter((f) => f.toLowerCase().endsWith('.xml'));
    const withStats = await Promise.all(
      xmlFiles.map(async (fileName) => {
        const full = path.join(env.paths.inputDir, fileName);
        const stat = await fs.stat(full);
        return {
          fileName,
          size: stat.size,
          lastModified: new Date(stat.mtime).toISOString().slice(0, 19).replace('T', ' '),
          sortDate: stat.mtime.getTime(),
        };
      }),
    );
    return withStats.sort((a, b) => b.sortDate - a.sortDate).map(({ sortDate, ...rest }) => rest);
  } catch {
    return [];
  }
};

const parseXmlFromFile = async (fileName) => {
  const safeName = path.basename(fileName);
  const fullPath = path.join(env.paths.inputDir, safeName);
  const xmlContent = await fs.readFile(fullPath, 'utf8');
  return parseInvoice(xmlContent);
};

const validateFile = async (fileName) => {
  try {
    const parsed = await parseXmlFromFile(fileName);
    const result = await validarDocumento({
      proveedor: parsed.provider,
      productos: parsed.products,
      totales: parsed.totals,
    });
    return { fileName, ...result };
  } catch (error) {
    return {
      fileName,
      valido: false,
      requiereHomologacion: false,
      proveedorExiste: false,
      productos: [],
      errores: [error.message],
    };
  }
};

module.exports = { upload, listXmlFiles, parseXmlFromFile, validateFile };
