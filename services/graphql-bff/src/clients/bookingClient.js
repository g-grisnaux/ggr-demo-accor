const { makeClient } = require('./restClient');

const client = makeClient({
  name: 'booking-api',
  baseUrl: process.env.BOOKING_URL || 'http://booking-api:8082',
  // Booking fans out to payment-api, so it needs more headroom than a read.
  timeoutMs: 8000,
});

function createBooking(input) {
  return client.request('createBooking', '/bookings', { method: 'POST', body: input });
}

function getBooking(bookingId) {
  return client.request('getBooking', `/bookings/${bookingId}`);
}

function listBookings(guestId) {
  return client.request('listBookings', '/bookings', { query: { guestId } });
}

module.exports = { createBooking, getBooking, listBookings };
