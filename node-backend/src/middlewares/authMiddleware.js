const { validateToken } = require('../services/authService');

const normalizePath = (input = '') => {
  const p = input.trim().toLowerCase();
  return p.length > 1 && p.endsWith('/') ? p.slice(0, -1) : p;
};

module.exports = (req, res, next) => {
  if (req.method === 'OPTIONS') return next();

  const path = normalizePath(req.path);
  if (path === '/auth/login' || path === '/ping') return next();

  const authorization = req.headers.authorization || '';
  if (!authorization) return res.status(401).json({ success: false, message: 'Token requerido' });
  if (!/^bearer\s+/i.test(authorization)) return res.status(401).json({ success: false, message: 'Token inválido' });

  const token = authorization.replace(/^bearer\s+/i, '').trim();
  const session = validateToken(token);
  req.session = session;
  return next();
};
