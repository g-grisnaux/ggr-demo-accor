// Datadog Mobile RUM initialisation.
//
// This is the piece that answers "replace Firebase on Android and iOS". What it
// gives that Firebase does not: the same session that records a tap also
// carries the trace context into the BFF, so a slow screen can be followed into
// the GraphQL resolver and the REST call underneath it. Firebase stops at the
// app boundary.
//
// The RUM application id and client token come from the environment at build
// time rather than being committed — this repository is public.

import {
  DatadogProvider,
  DatadogProviderConfiguration,
  SdkVerbosity,
  TrackingConsent,
} from '@datadog/mobile-react-native';

// A distinct RUM application from the web one. Mixing a mobile app and a web
// app into a single RUM application makes every per-platform breakdown
// meaningless, which is exactly the comparison the architect asked for.
const APPLICATION_ID = process.env.EXPO_PUBLIC_DD_MOBILE_RUM_APP_ID || '';
const CLIENT_TOKEN = process.env.EXPO_PUBLIC_DD_RUM_CLIENT_TOKEN || '';
const ENV = process.env.EXPO_PUBLIC_DD_ENV || 'ggr-demo-accor-260907';
const SITE = process.env.EXPO_PUBLIC_DD_SITE || 'US1';

export const config = new DatadogProviderConfiguration(
  CLIENT_TOKEN,
  ENV,
  APPLICATION_ID,
  // Track user interactions, XHR/fetch resources, and errors. All three are on
  // because each one answers a different part of the Firebase replacement:
  // interactions give the funnel, resources give the network view, errors give
  // the crash reporting.
  true,
  true,
  true,
  // GRANTED rather than PENDING: this is a demo with no real users, so there is
  // no consent to collect. A real ALL build would start PENDING and flip after
  // the CMP resolves.
  TrackingConsent.GRANTED
);

config.site = SITE;
config.serviceName = 'all-mobile';
config.version = '1.0.0';

config.nativeCrashReportEnabled = true;
config.sessionSamplingRate = 100;
config.resourceTracingSamplingRate = 100;

// This is the line that makes mobile-to-backend correlation work. Without a
// first-party host the SDK records the request but injects no trace headers, so
// the mobile session and the backend trace stay two unrelated islands — which
// is precisely the gap they have with Firebase today.
config.firstPartyHosts = ['localhost', '10.0.2.2'];

config.verbosity = SdkVerbosity.WARN;

export { DatadogProvider };
