const { AppError } = require('../utils/errors');

module.exports = (err, req, res, next) => {
  req.log?.error({ err }, 'Unhandled error');
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({ error: err.message, details: err.details || undefined });
  }
  return res.status(500).json({ error: err.message || 'Internal Server Error' });
};
