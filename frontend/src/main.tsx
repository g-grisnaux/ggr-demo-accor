import './theme.css';
import { datadogLogs } from '@datadog/browser-logs';
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

  // Browser Logs alongside RUM. Initialised with the same service and env, so a
  // log, the RUM session that produced it and the backend trace it triggered all
  // carry the same identity — this is the "the page broke and we have no useful
  // logs" gap on the current site.
  //
  // The SDK stamps session_id and view.id on every log when RUM is present, so
  // a log line opens its own session replay.
  datadogLogs.init({
    clientToken: rumClientToken,
    site: import.meta.env.VITE_DD_SITE || 'datadoghq.com',
    service: import.meta.env.VITE_DD_SERVICE || 'all-web',
    env: import.meta.env.VITE_DD_ENV || 'local',
    version: import.meta.env.VITE_DD_VERSION || '1.0.0',
    forwardErrorsToLogs: true,
    // console.warn/error only: forwarding every console.log would bury the
    // signal under React's development chatter.
    forwardConsoleLogs: ['warn', 'error'],
    forwardReports: 'all',
    sessionSampleRate: 100,
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
