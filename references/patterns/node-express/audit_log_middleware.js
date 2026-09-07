const pino = require('pino');

// Pattern: SIEM — structured audit log for auth-relevant events
// Adapt: log fields relevant to your domain's security events
const audit = pino({ name: 'audit' });

function auditLogMiddleware(req, res, next) {
  res.on('finish', () => {
    audit.info({
      method: req.method,
      path: req.path,
      status: res.statusCode,
      remote: req.ip,
    }, 'request');
  });
  next();
}

module.exports = { auditLogMiddleware };
