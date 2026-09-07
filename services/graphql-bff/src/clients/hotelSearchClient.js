const { makeClient } = require('./restClient');

const client = makeClient({
  name: 'hotel-search-api',
  baseUrl: process.env.HOTEL_SEARCH_URL || 'http://hotel-search-api:8081',
});

function searchHotels({ city, checkIn, checkOut, guests }) {
  return client.request('searchHotels', '/hotels', {
    query: { city, checkIn, checkOut, guests },
  });
}

function getHotel(hotelId) {
  return client.request('getHotel', `/hotels/${hotelId}`);
}

// Per-hotel availability. Called once per hotel when the dataloader is off —
// this is the N+1 the trace flamegraph exposes.
function getAvailability(hotelId, { checkIn, checkOut }) {
  return client.request('getAvailability', `/hotels/${hotelId}/availability`, {
    query: { checkIn, checkOut },
  });
}

// Batched availability. One REST call for the whole page of results.
function getAvailabilityBatch(hotelIds, { checkIn, checkOut }) {
  return client.request('getAvailabilityBatch', '/availability', {
    query: { hotelIds: hotelIds.join(','), checkIn, checkOut },
  });
}

module.exports = { searchHotels, getHotel, getAvailability, getAvailabilityBatch };
