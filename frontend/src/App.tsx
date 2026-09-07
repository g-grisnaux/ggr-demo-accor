import { BrowserRouter, Routes, Route, Link, useLocation } from 'react-router-dom';
import { datadogRum } from '@datadog/browser-rum';
import { useEffect, useState } from 'react';
import ErrorBoundary from './components/ErrorBoundary';
import HotelSearch from './components/HotelSearch';
import MyBookings from './components/MyBookings';
import { currentGuestId } from './api/graphql';

/**
 * Deliberate front-end crash, for the RUM error scenario. Reading a property of
 * an undefined rate object is the shape of bug that actually breaks booking
 * funnels — the API changed and the client was not updated.
 */
function CrashTrigger() {
  const [boom, setBoom] = useState(false);
  if (boom) {
    const rate = undefined as unknown as { totalPrice: { amount: number } };
    return <span>{rate.totalPrice.amount}</span>;
  }
  return (
    <button className="btn btn-ghost btn-xs text-primary-content" onClick={() => setBoom(true)}>
      Break the funnel
    </button>
  );
}

// RUM treats a SPA route change as a new view, so the booking funnel shows up as
// distinct steps instead of one long session on "/".
function RouteTracker() {
  const location = useLocation();
  useEffect(() => {
    datadogRum.startView({ name: location.pathname });
  }, [location.pathname]);
  return null;
}

function App() {
  useEffect(() => {
    // No real auth in the demo; the stable per-browser guest id stands in, so
    // RUM sessions can be correlated with BFF-side flag targeting.
    datadogRum.setUser({ id: currentGuestId(), name: 'ALL demo guest' });
  }, []);

  return (
    <BrowserRouter>
      <RouteTracker />
      <div className="min-h-screen bg-base-200">
        <div className="navbar bg-primary px-4 text-primary-content">
          <div className="navbar-start">
            <span className="font-bold tracking-tight">ALL · Book a stay</span>
          </div>
          <div className="navbar-end gap-1">
            <Link to="/" className="btn btn-ghost btn-sm text-primary-content">Search</Link>
            <Link to="/bookings" className="btn btn-ghost btn-sm text-primary-content">My bookings</Link>
            <CrashTrigger />
          </div>
        </div>
        <main className="p-6">
          <ErrorBoundary>
            <Routes>
              <Route path="/" element={<HotelSearch />} />
              <Route path="/bookings" element={<MyBookings />} />
            </Routes>
          </ErrorBoundary>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default App;
