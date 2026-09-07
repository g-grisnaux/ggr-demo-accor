const DataLoader = require('dataloader');
const tracer = require('dd-trace');
const hotelSearch = require('../clients/hotelSearchClient');
const { toHotel, toAvailability } = require('../mappers/hotelMapper');
const { BusinessError, CODES } = require('../errors');

// Repository layer: owns the business rules and the batching strategy. Resolvers
// stay thin and never touch an API client directly.

function parseStay(checkIn, checkOut) {
  const start = new Date(checkIn);
  const end = new Date(checkOut);

  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    throw new BusinessError(CODES.INVALID_DATE, 'Check-in and check-out must be valid ISO dates', {
      checkIn,
      checkOut,
    });
  }
  if (end <= start) {
    throw new BusinessError(CODES.INVALID_DATE, 'Check-out must be after check-in', {
      checkIn,
      checkOut,
    });
  }
  const nights = Math.round((end - start) / 86400000);
  if (nights > 30) {
    throw new BusinessError(CODES.INVALID_DATE, 'Stays longer than 30 nights are not bookable online', {
      nights,
    });
  }
  return { start, end, nights };
}

// One dataloader per request, so batching never leaks across guests or stays.
function createAvailabilityLoader({ checkIn, checkOut, batchingEnabled }) {
  if (!batchingEnabled) {
    // Degraded path: DataLoader still dedupes identical keys, but each hotel
    // gets its own REST round-trip.
    return new DataLoader(
      async (hotelIds) =>
        Promise.all(
          hotelIds.map(async (id) => {
            const { body } = await hotelSearch.getAvailability(id, { checkIn, checkOut });
            return toAvailability(body);
          })
        ),
      { cache: true, batch: false }
    );
  }

  return new DataLoader(
    async (hotelIds) =>
      tracer.trace(
        'bff.dataloader.availability',
        { tags: { 'dataloader.batch_size': hotelIds.length } },
        async () => {
          const { body } = await hotelSearch.getAvailabilityBatch([...hotelIds], { checkIn, checkOut });
          const byHotel = new Map(
            (body.availability || []).map((dto) => [String(dto.hotel_id), toAvailability(dto)])
          );
          // DataLoader requires the result array to line up with the keys.
          return hotelIds.map(
            (id) => byHotel.get(String(id)) || { hotelId: String(id), available: false, roomsLeft: 0, offers: [] }
          );
        }
      ),
    { maxBatchSize: 50 }
  );
}

async function searchHotels({ city, checkIn, checkOut, guests }) {
  const { nights } = parseStay(checkIn, checkOut);
  const { body } = await hotelSearch.searchHotels({ city, checkIn, checkOut, guests });
  const hotels = (body.hotels || []).map(toHotel);
  return { hotels, nights };
}

async function getHotel(hotelId) {
  const { status, body } = await hotelSearch.getHotel(hotelId);
  if (status === 404) {
    throw new BusinessError(CODES.HOTEL_UNAVAILABLE, `Hotel ${hotelId} is not bookable`, { hotelId });
  }
  return toHotel(body);
}

module.exports = { searchHotels, getHotel, createAvailabilityLoader, parseStay };
