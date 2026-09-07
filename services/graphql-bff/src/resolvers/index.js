const tracer = require('dd-trace');
const hotelRepository = require('../repositories/hotelRepository');
const bookingRepository = require('../repositories/bookingRepository');
const { isDataloaderEnabled } = require('../featureFlags');
const { fieldTiming } = require('../telemetry');

// Resolvers stay thin: they wrap a repository call in a named span and hand the
// result back. All business rules live one layer down.
//
// dd-trace already emits a span per resolver; the explicit spans here add the
// domain arguments (city, stay length, hotel id) that make a trace searchable.

function traced(parentType, fieldName, fn, { deprecated = false } = {}) {
  const record = fieldTiming(parentType, fieldName, deprecated);
  return async (parent, args, ctx, info) => {
    const started = process.hrtime.bigint();
    try {
      return await tracer.trace(
        'graphql.resolve',
        {
          resource: `${parentType}.${fieldName}`,
          tags: {
            'graphql.parent_type': parentType,
            'graphql.field': fieldName,
            'graphql.field.deprecated': deprecated,
          },
        },
        () => fn(parent, args, ctx, info)
      );
    } finally {
      record(Number(process.hrtime.bigint() - started) / 1e6);
    }
  };
}

const resolvers = {
  Query: {
    searchHotels: traced('Query', 'searchHotels', async (_p, args, ctx) => {
      const { hotels, nights } = await hotelRepository.searchHotels(args);
      const span = tracer.scope().active();
      if (span) {
        span.setTag('search.city', args.city);
        span.setTag('search.nights', nights);
        span.setTag('search.result_count', hotels.length);
      }
      // The loader can only be built here: it is scoped to the stay dates, which
      // aren't known when the request context is created. Hotel.availability
      // then resolves through it without the client repeating the dates.
      const batchingEnabled = await isDataloaderEnabled(ctx.guestId, ctx.tier);
      if (span) span.setTag('bff.dataloader.enabled', batchingEnabled);
      ctx.availabilityLoader = hotelRepository.createAvailabilityLoader({
        checkIn: args.checkIn,
        checkOut: args.checkOut,
        batchingEnabled,
      });

      return { nights, resultCount: hotels.length, hotels };
    }),

    hotel: traced('Query', 'hotel', (_p, { id }) => hotelRepository.getHotel(id)),

    booking: traced('Query', 'booking', (_p, { id }) => bookingRepository.getBooking(id)),

    bookings: traced('Query', 'bookings', (_p, { guestId }) => bookingRepository.listBookings(guestId)),
  },

  Mutation: {
    createBooking: traced('Mutation', 'createBooking', async (_p, { input }) => {
      const booking = await bookingRepository.createBooking(input);
      const span = tracer.scope().active();
      if (span) {
        span.setTag('booking.reference', booking.reference);
        span.setTag('booking.hotel_id', booking.hotelId);
        span.setTag('booking.status', booking.status);
      }
      return booking;
    }),
  },

  Hotel: {
    // Resolved once per hotel in the result set. With the dataloader on, the
    // whole page collapses into a single batched REST call; with it off, this
    // is the N+1.
    availability: traced('Hotel', 'availability', async (hotel, _args, ctx) => {
      if (!ctx.availabilityLoader) return null;
      return ctx.availabilityLoader.load(hotel.id);
    }),

    thumbnailUrl: traced('Hotel', 'thumbnailUrl', (hotel) => hotel.thumbnailUrl, {
      deprecated: true,
    }),
  },

  Booking: {
    hotel: traced('Booking', 'hotel', (booking) => hotelRepository.getHotel(booking.hotelId)),
  },
};

module.exports = { resolvers };
