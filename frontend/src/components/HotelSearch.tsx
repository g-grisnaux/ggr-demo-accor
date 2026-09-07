import { datadogRum } from '@datadog/browser-rum';
import { useState } from 'react';
import { graphql, GraphQLRequestError, currentGuestId } from '../api/graphql';
import { CREATE_BOOKING, SEARCH_HOTELS, type Booking, type Hotel, type RoomOffer, type SearchResult } from '../api/queries';

function isoDaysFromNow(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

const CITIES = ['Paris', 'Lyon', 'Marseille', 'Nice', 'London', 'Amsterdam', 'Berlin', 'Madrid'];

export default function HotelSearch() {
  const [city, setCity] = useState('Paris');
  const [checkIn, setCheckIn] = useState(isoDaysFromNow(7));
  const [checkOut, setCheckOut] = useState(isoDaysFromNow(10));
  const [guests, setGuests] = useState(2);

  const [result, setResult] = useState<SearchResult | null>(null);
  const [searching, setSearching] = useState(false);
  const [booking, setBooking] = useState<Booking | null>(null);
  const [bookingInFlight, setBookingInFlight] = useState<string | null>(null);
  const [message, setMessage] = useState<{ tone: 'error' | 'warn' | 'ok'; text: string } | null>(null);

  async function runSearch(event: React.FormEvent) {
    event.preventDefault();
    setSearching(true);
    setMessage(null);
    setBooking(null);

    const startedAt = performance.now();
    try {
      const data = await graphql<{ searchHotels: SearchResult }>('SearchHotels', SEARCH_HOTELS, {
        city,
        checkIn,
        checkOut,
        guests,
      });
      setResult(data.searchHotels);
      datadogRum.addAction('hotel_search', {
        city,
        nights: data.searchHotels.nights,
        result_count: data.searchHotels.resultCount,
        duration_ms: Math.round(performance.now() - startedAt),
      });
    } catch (err) {
      setResult(null);
      setMessage({
        tone: err instanceof GraphQLRequestError && err.kind === 'BUSINESS' ? 'warn' : 'error',
        text: describe(err),
      });
    } finally {
      setSearching(false);
    }
  }

  async function book(hotel: Hotel, offer: RoomOffer) {
    setBookingInFlight(`${hotel.id}-${offer.rateCode}`);
    setMessage(null);
    try {
      const data = await graphql<{ createBooking: Booking }>('CreateBooking', CREATE_BOOKING, {
        input: {
          hotelId: hotel.id,
          guestId: currentGuestId(),
          checkIn,
          checkOut,
          guests,
          rateCode: offer.rateCode,
          roomType: offer.roomType,
          paymentMethod: 'VISA',
        },
      });
      setBooking(data.createBooking);
      datadogRum.addAction('booking_confirmed', {
        hotel_id: hotel.id,
        rate_code: offer.rateCode,
        total_price: data.createBooking.totalPrice,
        reference: data.createBooking.reference,
      });
    } catch (err) {
      setMessage({
        tone: err instanceof GraphQLRequestError && err.kind === 'BUSINESS' ? 'warn' : 'error',
        text: describe(err),
      });
    } finally {
      setBookingInFlight(null);
    }
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <form onSubmit={runSearch} className="card bg-base-100 shadow">
        <div className="card-body grid grid-cols-1 gap-4 md:grid-cols-5 md:items-end">
          <label className="form-control">
            <span className="label-text mb-1">Destination</span>
            <select className="select select-bordered" value={city} onChange={(e) => setCity(e.target.value)}>
              {CITIES.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
          </label>
          <label className="form-control">
            <span className="label-text mb-1">Check-in</span>
            <input type="date" className="input input-bordered" value={checkIn} onChange={(e) => setCheckIn(e.target.value)} />
          </label>
          <label className="form-control">
            <span className="label-text mb-1">Check-out</span>
            <input type="date" className="input input-bordered" value={checkOut} onChange={(e) => setCheckOut(e.target.value)} />
          </label>
          <label className="form-control">
            <span className="label-text mb-1">Guests</span>
            <input
              type="number"
              min={1}
              max={6}
              className="input input-bordered"
              value={guests}
              onChange={(e) => setGuests(Number(e.target.value))}
            />
          </label>
          <button className="btn btn-primary" type="submit" disabled={searching}>
            {searching ? 'Searching…' : 'Search'}
          </button>
        </div>
      </form>

      {message && (
        <div className={`alert ${message.tone === 'error' ? 'alert-error' : message.tone === 'warn' ? 'alert-warning' : 'alert-success'}`}>
          <span>{message.text}</span>
        </div>
      )}

      {booking && (
        <div className="alert alert-success">
          <span>
            Booking <strong>{booking.reference}</strong> confirmed at {booking.hotel?.name} — {booking.totalPrice}{' '}
            {booking.currency}, paid by {booking.payment?.method}.
          </span>
        </div>
      )}

      {result && (
        <div className="space-y-3">
          <p className="text-sm opacity-70">
            {result.resultCount} properties · {result.nights} night{result.nights > 1 ? 's' : ''}
          </p>
          {result.hotels.map((hotel) => (
            <div key={hotel.id} className="card bg-base-100 shadow-sm">
              <div className="card-body">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <div>
                    <h3 className="card-title text-base">{hotel.name}</h3>
                    <p className="text-sm opacity-70">
                      {hotel.brand} · {hotel.city} · {hotel.starRating}★ · guest rating {hotel.guestRating}
                    </p>
                  </div>
                  {hotel.availability && !hotel.availability.available && (
                    <span className="badge badge-ghost">Sold out</span>
                  )}
                  {hotel.availability?.available && hotel.availability.roomsLeft <= 3 && (
                    <span className="badge badge-warning">{hotel.availability.roomsLeft} left</span>
                  )}
                </div>

                {hotel.availability?.offers.length ? (
                  <div className="mt-2 divide-y">
                    {hotel.availability.offers.map((offer) => (
                      <div key={offer.rateCode} className="flex flex-wrap items-center justify-between gap-2 py-2">
                        <div className="text-sm">
                          <span className="font-medium">{offer.roomType}</span>
                          <span className="opacity-70"> · {offer.boardType} · {offer.rateCode}</span>
                          {!offer.refundable && <span className="badge badge-sm badge-ghost ml-2">Non-refundable</span>}
                        </div>
                        <div className="flex items-center gap-3">
                          <span className="font-semibold">
                            {offer.totalPrice} {offer.currency}
                          </span>
                          <span className="text-xs opacity-70">+{offer.loyaltyPointsEarned} pts</span>
                          <button
                            className="btn btn-sm btn-primary"
                            disabled={bookingInFlight !== null}
                            onClick={() => book(hotel, offer)}
                          >
                            {bookingInFlight === `${hotel.id}-${offer.rateCode}` ? 'Booking…' : 'Book'}
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-sm opacity-60">No rates available for these dates.</p>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function describe(err: unknown): string {
  if (err instanceof GraphQLRequestError) {
    switch (err.code) {
      case 'INVALID_DATE':
        return `${err.message} — please adjust your dates.`;
      case 'PAYMENT_DECLINED':
        return `Payment was declined (${err.declineReason ?? 'unknown reason'}). Try another card.`;
      case 'HOTEL_UNAVAILABLE':
        return 'This property just sold out for your dates.';
      case 'RATE_EXPIRED':
        return 'That rate expired — refresh your search for current prices.';
      case 'UPSTREAM_UNAVAILABLE':
        return 'We could not reach our booking systems. Please retry in a moment.';
      default:
        return err.message;
    }
  }
  return 'Something went wrong. Please retry.';
}
