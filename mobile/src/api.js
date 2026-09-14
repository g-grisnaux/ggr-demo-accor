// GraphQL client for the mobile app.
//
// The endpoint is reached through `kubectl port-forward`, because the BFF is a
// ClusterIP service and nothing in this demo is exposed to the internet. The
// Android emulator reaches the host through 10.0.2.2; the iOS simulator shares
// the host's localhost.
import { Platform } from 'react-native';
import { DdRum, DdLogs } from '@datadog/mobile-react-native';

const HOST = Platform.OS === 'android' ? '10.0.2.2' : 'localhost';
const ENDPOINT = process.env.EXPO_PUBLIC_BFF_URL || `http://${HOST}:8080/graphql`;

// Same client identity headers the web front sends, so the BFF's per-client
// metrics separate mobile from web without any extra work.
const CLIENT_NAME = 'all-ios-native';
const CLIENT_VERSION = '1.0.0';

export async function graphql(operationName, query, variables = {}) {
  const started = Date.now();
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-client-name': Platform.OS === 'android' ? 'all-android-native' : CLIENT_NAME,
      'x-client-version': CLIENT_VERSION,
      'x-guest-id': 'mobile-demo-guest',
    },
    body: JSON.stringify({ operationName, query, variables }),
  });

  const payload = await response.json();
  const elapsed = Date.now() - started;

  if (payload.errors?.length) {
    const first = payload.errors[0];
    const code = first.extensions?.code || 'UNKNOWN';
    const kind = first.extensions?.kind || 'SERVER';

    // Business rejections are actions, not errors — the same split the backend
    // makes. Sending a declined card to Error Tracking would bury the real
    // crashes under normal funnel behaviour.
    if (kind === 'BUSINESS') {
      DdRum.addAction('business_rejection', operationName, {
        error_code: code,
        decline_reason: first.extensions?.declineReason ?? null,
      }, Date.now());
      DdLogs.warn('graphql operation rejected', {
        operation: operationName,
        error_code: code,
        error_kind: kind,
      });
    } else {
      DdRum.addError(first.message, 'NETWORK', '', {
        operation: operationName,
        error_code: code,
        error_kind: kind,
      }, Date.now());
      DdLogs.error('graphql operation failed', {
        operation: operationName,
        error_code: code,
        error_kind: kind,
      });
    }

    const err = new Error(first.message);
    err.code = code;
    err.kind = kind;
    throw err;
  }

  DdLogs.info('graphql operation completed', {
    operation: operationName,
    duration_ms: elapsed,
  });

  return payload.data;
}

export const SEARCH_HOTELS = `
  query SearchHotels($city: String!, $checkIn: String!, $checkOut: String!) {
    searchHotels(city: $city, checkIn: $checkIn, checkOut: $checkOut) {
      nights
      resultCount
      hotels {
        id
        name
        brand
        starRating
        availability { available roomsLeft offers { rateCode totalPrice currency } }
      }
    }
  }
`;

export const CREATE_BOOKING = `
  mutation CreateBooking($input: CreateBookingInput!) {
    createBooking(input: $input) {
      reference
      status
      totalPrice
      currency
      payment { status method }
    }
  }
`;
