import { useEffect, useState } from 'react';
import { currentGuestId, graphql } from '../api/graphql';
import { MY_BOOKINGS, type Booking } from '../api/queries';

export default function MyBookings() {
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    graphql<{ bookings: Booking[] }>('MyBookings', MY_BOOKINGS, { guestId: currentGuestId() })
      .then((data) => setBookings(data.bookings))
      .catch((err) => setError(err.message));
  }, []);

  if (error) return <div className="alert alert-error mx-auto max-w-3xl"><span>{error}</span></div>;
  if (!bookings) return <p className="text-center opacity-60">Loading…</p>;
  if (bookings.length === 0) return <p className="text-center opacity-60">No bookings yet.</p>;

  return (
    <div className="mx-auto max-w-3xl overflow-x-auto">
      <table className="table bg-base-100">
        <thead>
          <tr>
            <th>Reference</th>
            <th>Hotel</th>
            <th>Stay</th>
            <th>Total</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {bookings.map((b) => (
            <tr key={b.id}>
              <td className="font-mono text-xs">{b.reference}</td>
              <td>{b.hotel?.name ?? '—'}</td>
              <td className="text-sm">{b.checkIn} → {b.checkOut}</td>
              <td>{b.totalPrice} {b.currency}</td>
              <td>
                <span className={`badge badge-sm ${b.status === 'CONFIRMED' ? 'badge-success' : 'badge-warning'}`}>
                  {b.status}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
