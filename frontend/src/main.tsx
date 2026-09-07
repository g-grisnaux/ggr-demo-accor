import './theme.css';
import { datadogRum } from '@datadog/browser-rum';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';

const rumAppId = import.meta.env.VITE_DD_RUM_APPLICATION_ID;
const rumClientToken = import.meta.env.VITE_DD_RUM_CLIENT_TOKEN;

if (rumAppId && rumClientToken) {
  datadogRum.init({
    applicationId: rumAppId,
    clientToken: rumClientToken,
    site: import.meta.env.VITE_DD_SITE || 'datadoghq.com',
    service: import.meta.env.VITE_DD_SERVICE || 'all-web',
    env: import.meta.env.VITE_DD_ENV || 'local',
    version: import.meta.env.VITE_DD_VERSION || '1.0.0',
    sessionSampleRate: 100,
    sessionReplaySampleRate: 100,
    trackUserInteractions: true,
    trackResources: true,
    trackLongTasks: true,
    defaultPrivacyLevel: 'allow',
    // Views are driven by the router, not by RUM guessing at SPA navigation.
    trackViewsManually: true,
    // Injects the trace context into the /graphql call so a RUM session links to
    // the BFF trace and, through it, to the REST spans underneath. Both
    // propagators are sent because the downstream REST APIs speak W3C.
    allowedTracingUrls: [
      { match: window.location.origin, propagatorTypes: ['datadog', 'tracecontext'] },
    ],
  });
} else {
  // Loud on purpose: a demo that silently runs without RUM is worse than one
  // that refuses to start.
  console.warn('[RUM] disabled — VITE_DD_RUM_APPLICATION_ID / VITE_DD_RUM_CLIENT_TOKEN not set');
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
