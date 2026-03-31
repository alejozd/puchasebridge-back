const crypto = require('crypto');

const sessions = new Map();

const createSession = ({ codigo, nombre }) => {
  const token = crypto.randomUUID().replace(/-/g, '');
  sessions.set(token, { codigo, nombre });
  return token;
};

const getSession = (token) => sessions.get(token);

module.exports = { createSession, getSession };
