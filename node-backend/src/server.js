const fs = require('fs/promises');
const app = require('./app');
const env = require('./config/env');
const logger = require('./config/logger');

(async () => {
  await fs.mkdir(env.paths.inputDir, { recursive: true });
  await fs.mkdir(env.paths.processedDir, { recursive: true });

  app.listen(env.port, () => {
    logger.info({ port: env.port }, 'Server is running');
  });
})();
