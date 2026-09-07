// REST DTO -> GraphQL DTO. The REST APIs are owned by other teams and speak
// snake_case with prices in cents; the public schema speaks camelCase with
// decimal amounts. Keeping the translation in one place means an upstream
// rename never leaks into the resolvers.

function toHotel(dto) {
  return {
    id: String(dto.hotel_id),
    name: dto.name,
    brand: dto.brand,
    city: dto.city,
    country: dto.country,
    starRating: dto.star_rating,
    guestRating: dto.guest_rating,
    address: dto.address,
    amenities: dto.amenities || [],
    // Deprecated in the public schema but still resolved for older mobile
    // builds — field-level usage metrics are what tell us when it can go.
    thumbnailUrl: dto.thumbnail_url || null,
  };
}

function toRoomOffer(dto) {
  return {
    rateCode: dto.rate_code,
    roomType: dto.room_type,
    boardType: dto.board_type,
    pricePerNight: centsToAmount(dto.price_per_night_cents),
    totalPrice: centsToAmount(dto.total_price_cents),
    currency: dto.currency || 'EUR',
    refundable: Boolean(dto.refundable),
    loyaltyPointsEarned: dto.loyalty_points_earned ?? 0,
  };
}

function toAvailability(dto) {
  return {
    hotelId: String(dto.hotel_id),
    available: Boolean(dto.available),
    roomsLeft: dto.rooms_left ?? 0,
    offers: (dto.offers || []).map(toRoomOffer),
  };
}

function centsToAmount(cents) {
  if (cents === undefined || cents === null) return null;
  return Math.round(cents) / 100;
}

module.exports = { toHotel, toRoomOffer, toAvailability, centsToAmount };
