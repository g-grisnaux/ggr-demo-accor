const { centsToAmount } = require('./hotelMapper');

function toBooking(dto) {
  return {
    id: String(dto.booking_id),
    reference: dto.reference,
    status: (dto.status || 'UNKNOWN').toUpperCase(),
    hotelId: String(dto.hotel_id),
    guestId: String(dto.guest_id),
    checkIn: dto.check_in,
    checkOut: dto.check_out,
    guests: dto.guests,
    roomType: dto.room_type,
    totalPrice: centsToAmount(dto.total_price_cents),
    currency: dto.currency || 'EUR',
    createdAt: dto.created_at,
    payment: dto.payment ? toPayment(dto.payment) : null,
  };
}

function toPayment(dto) {
  return {
    id: String(dto.payment_id),
    status: (dto.status || 'UNKNOWN').toUpperCase(),
    amount: centsToAmount(dto.amount_cents),
    currency: dto.currency || 'EUR',
    method: dto.method,
    // Present only on refusals — surfaced so the front can explain *why*.
    declineReason: dto.decline_reason || null,
  };
}

// GraphQL input -> REST DTO, the other direction of the same boundary.
function fromBookingInput(input) {
  return {
    hotel_id: input.hotelId,
    guest_id: input.guestId,
    check_in: input.checkIn,
    check_out: input.checkOut,
    guests: input.guests,
    rate_code: input.rateCode,
    room_type: input.roomType,
    payment_method: input.paymentMethod,
  };
}

module.exports = { toBooking, toPayment, fromBookingInput };
