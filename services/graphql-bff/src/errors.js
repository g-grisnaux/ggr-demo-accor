const { GraphQLError } = require('graphql');

// Business error taxonomy exposed through GraphQL `extensions.code`.
// These are the codes error rates get sliced by — an invalid date is a client
// mistake, a declined payment is a partner failure, and the two must never
// share an alert.
const CODES = {
  INVALID_DATE: 'INVALID_DATE',
  HOTEL_UNAVAILABLE: 'HOTEL_UNAVAILABLE',
  PAYMENT_DECLINED: 'PAYMENT_DECLINED',
  RATE_EXPIRED: 'RATE_EXPIRED',
  UPSTREAM_UNAVAILABLE: 'UPSTREAM_UNAVAILABLE',
};

class BusinessError extends GraphQLError {
  constructor(code, message, extra = {}) {
    super(message, { extensions: { code, kind: 'BUSINESS', ...extra } });
    this.name = 'BusinessError';
  }
}

// Upstream REST failures keep their originating service, so a trace can be
// pivoted straight onto the faulty API.
class UpstreamError extends GraphQLError {
  constructor(service, status, message) {
    super(message, {
      extensions: {
        code: CODES.UPSTREAM_UNAVAILABLE,
        kind: 'UPSTREAM',
        upstreamService: service,
        upstreamStatus: status,
      },
    });
    this.name = 'UpstreamError';
  }
}

module.exports = { CODES, BusinessError, UpstreamError };
