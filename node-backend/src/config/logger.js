const pino = require('pino');
const env = require('./env');

module.exports = pino({ level: env.logLevel });
