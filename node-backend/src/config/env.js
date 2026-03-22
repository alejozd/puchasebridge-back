const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const parseBool = (value, fallback = false) => {
  if (value == null) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
};

const parseOrigins = (value) =>
  String(value || 'http://localhost:5173,http://127.0.0.1:5173')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean);

module.exports = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 9000),
  logLevel: process.env.LOG_LEVEL || 'info',
  cors: {
    origins: parseOrigins(process.env.CORS_ORIGINS),
    credentials: parseBool(process.env.CORS_CREDENTIALS, true),
  },
  helisa: {
    user: process.env.HELISA_USER || 'HELISAADMON',
    pass: process.env.HELISA_PASS || '',
    server: process.env.HELISA_SERVER || '',
    dbBasePath: process.env.HELISA_DB_BASE_PATH || '',
    dbType: process.env.HELISA_DB_TYPE || 'S',
    empresa: process.env.HELISA_EMPRESA || '0',
  },
  bridge: {
    user: process.env.BRIDGE_USER || 'SYSDBA',
    pass: process.env.BRIDGE_PASS || '',
    dbPath: process.env.BRIDGE_DB_PATH || './database/PURCHASEBRIDGE.FDB',
  },
  paths: {
    inputDir: path.resolve(process.cwd(), process.env.INPUT_DIR || './PurchaseBridge/Input'),
    processedDir: path.resolve(process.cwd(), process.env.PROCESSED_DIR || './PurchaseBridge/Processed'),
  },
};
