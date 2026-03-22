const path = require('path');
const Firebird = require('node-firebird');
const env = require('./env');

const attach = (options) =>
  new Promise((resolve, reject) => {
    Firebird.attach(options, (err, db) => (err ? reject(err) : resolve(db)));
  });

const query = (db, sql, params = []) =>
  new Promise((resolve, reject) => {
    db.query(sql, params, (err, result) => (err ? reject(err) : resolve(result || [])));
  });

const execute = async (options, sql, params = []) => {
  const db = await attach(options);
  try {
    return await query(db, sql, params);
  } finally {
    db.detach();
  }
};

const withTransaction = async (options, callback) => {
  const db = await attach(options);
  let tx;
  try {
    tx = await new Promise((resolve, reject) => {
      db.transaction(Firebird.ISOLATION_READ_COMMITTED, (err, transaction) =>
        err ? reject(err) : resolve(transaction),
      );
    });

    const txQuery = (sql, params = []) =>
      new Promise((resolve, reject) => {
        tx.query(sql, params, (err, result) => (err ? reject(err) : resolve(result || [])));
      });

    const result = await callback(txQuery);
    await new Promise((resolve, reject) => tx.commit((err) => (err ? reject(err) : resolve())));
    return result;
  } catch (error) {
    if (tx) {
      await new Promise((resolve) => tx.rollback(() => resolve()));
    }
    throw error;
  } finally {
    db.detach();
  }
};

const normalizeEmpresa = (empresaCode) => {
  const num = Number(empresaCode);
  if (!Number.isFinite(num)) return 'heli00bd.hgw';
  return num < 10 ? `heli0${num}bd.hgw` : `heli${num}bd.hgw`;
};

const getHelisaMainOptions = () => ({
  host: env.helisa.server || 'localhost',
  database:
    env.helisa.dbType === 'S'
      ? path.join(env.helisa.dbBasePath, 'helisabd.hgw')
      : `${env.helisa.server}:${path.join(env.helisa.dbBasePath, 'helisabd.hgw')}`,
  user: env.helisa.user,
  password: env.helisa.pass,
  lowercase_keys: false,
  role: null,
  pageSize: 4096,
});

const getHelisaCompanyOptions = (empresaCode = '0') => ({
  host: env.helisa.server || 'localhost',
  database:
    env.helisa.dbType === 'S'
      ? path.join(env.helisa.dbBasePath, normalizeEmpresa(empresaCode))
      : `${env.helisa.server}:${path.join(env.helisa.dbBasePath, normalizeEmpresa(empresaCode))}`,
  user: env.helisa.user,
  password: env.helisa.pass,
  lowercase_keys: false,
  role: null,
  pageSize: 4096,
});

const getBridgeOptions = () => ({
  host: 'localhost',
  database: path.resolve(process.cwd(), env.bridge.dbPath),
  user: env.bridge.user,
  password: env.bridge.pass,
  lowercase_keys: false,
  role: null,
  pageSize: 4096,
});

module.exports = { execute, withTransaction, getBridgeOptions, getHelisaMainOptions, getHelisaCompanyOptions };
