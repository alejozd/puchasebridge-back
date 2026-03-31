const authService = require('../services/authService');

const login = async (req, res) => {
  const { usuario, clave } = req.body || {};
  if (!usuario || !clave) return res.status(400).json({ error: 'Parámetros "usuario" y "clave" son obligatorios' });
  const data = await authService.login(usuario, clave);
  return res.json(data);
};

module.exports = { login };
