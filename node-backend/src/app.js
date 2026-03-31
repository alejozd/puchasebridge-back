const express = require('express');
const cors = require('cors');
const pinoHttp = require('pino-http');
const env = require('./config/env');
const logger = require('./config/logger');
const authMiddleware = require('./middlewares/authMiddleware');
const errorMiddleware = require('./middlewares/errorMiddleware');
const routes = require('./routes');

const app = express();

app.use(pinoHttp({ logger }));
app.use(
  cors({
    origin(origin, cb) {
      if (!origin) return cb(null, env.cors.origins[0]);
      if (env.cors.origins.includes(origin)) return cb(null, origin);
      return cb(null, env.cors.origins[0]);
    },
    credentials: env.cors.credentials,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept'],
    exposedHeaders: ['Content-Disposition', 'Content-Type'],
    maxAge: 86400,
  }),
);

app.use(express.json({ limit: '10mb' }));
app.use(authMiddleware);
app.use(routes);
app.use(errorMiddleware);

module.exports = app;
