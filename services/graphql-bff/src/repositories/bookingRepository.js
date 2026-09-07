const bookingClient = require('../clients/bookingClient');
const { toBooking, fromBookingInput } = require('../mappers/bookingMapper');
const { parseStay } = require('./hotelRepository');
const { BusinessError, CODES } = require('../errors');

// Maps the REST error vocabulary of booking-api onto the public GraphQL error
// codes. Downstream teams change their wording; the public contract does not.
const UPSTREAM_CODE_MAP = {
  invalid_date_range: CODES.INVALID_DATE,
  past_check_in: CODES.INVALID_DATE,
  no_availability: CODES.HOTEL_UNAVAILABLE,
  sold_out: CODES.HOTEL_UNAVAILABLE,
  rate_expired: CODES.RATE_EXPIRED,
  payment_declined: CODES.PAYMENT_DECLINED,
  insufficient_funds: CODES.PAYMENT_DECLINED,
  card_expired: CODES.PAYMENT_DECLINED,
};

async function createBooking(input) {
  // Validate locally first — no point burning a REST call and a payment
  // authorization on a date range the client got wrong.
  parseStay(input.checkIn, input.checkOut);

  const { status, body } = await bookingClient.createBooking(fromBookingInput(input));

  if (status >= 400) {
    const upstreamCode = body.error_code || body.code || 'unknown';
    const mapped = UPSTREAM_CODE_MAP[upstreamCode];
    if (mapped) {
      throw new BusinessError(mapped, body.message || `Booking rejected (${upstreamCode})`, {
        upstreamErrorCode: upstreamCode,
        declineReason: body.decline_reason || null,
      });
    }
    // An unmapped 4xx is a contract drift between the BFF and booking-api —
    // worth alerting on, because it means the schema is lying to clients.
    throw new BusinessError(CODES.UPSTREAM_UNAVAILABLE, `Unmapped booking error: ${upstreamCode}`, {
      upstreamErrorCode: upstreamCode,
      contractDrift: true,
    });
  }

  return toBooking(body);
}

async function getBooking(bookingId) {
  const { status, body } = await bookingClient.getBooking(bookingId);
  if (status === 404) return null;
  return toBooking(body);
}

async function listBookings(guestId) {
  const { body } = await bookingClient.listBookings(guestId);
  return (body.bookings || []).map(toBooking);
}

module.exports = { createBooking, getBooking, listBookings };
