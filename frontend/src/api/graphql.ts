import { datadogRum } from '@datadog/browser-rum';

// Client identity travels on every GraphQL call. The BFF turns these headers
// into span tags and metric dimensions, which is how "which app version is
// hitting this deprecated field" gets answered.
const CLIENT_NAME = import.meta.env.VITE_CLIENT_NAME || 'all-web';
const CLIENT_VERSION = import.meta.env.VITE_CLIENT_VERSION || '3.4.0';

export interface GraphQLError {
  message: string;
  extensions?: {
    code?: string;
    kind?: string;
    declineReason?: string | null;
    upstreamService?: string;
  };
}

export class GraphQLRequestError extends Error {
  readonly code: string;
  readonly kind: string;
  readonly declineReason: string | null;

  constructor(errors: GraphQLError[]) {
    const first = errors[0];
    super(first?.message || 'GraphQL request failed');
    this.name = 'GraphQLRequestError';
    this.code = first?.extensions?.code || 'UNKNOWN';
    this.kind = first?.extensions?.kind || 'SERVER';
    this.declineReason = first?.extensions?.declineReason ?? null;
  }
}

export async function graphql<T>(
  operationName: string,
  query: string,
  variables: Record<string, unknown> = {}
): Promise<T> {
  const response = await fetch('/graphql', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-client-name': CLIENT_NAME,
      'x-client-version': CLIENT_VERSION,
      'x-guest-id': currentGuestId(),
    },
    body: JSON.stringify({ operationName, query, variables }),
  });

  const payload = await response.json();

  if (payload.errors?.length) {
    const error = new GraphQLRequestError(payload.errors);
    // Business rejections are expected outcomes, not front-end faults. Sending
    // them to RUM as errors would bury the real JavaScript failures, so they go
    // in as an action carrying the code instead.
    if (error.kind === 'BUSINESS') {
      datadogRum.addAction('booking_rejected', {
        error_code: error.code,
        decline_reason: error.declineReason,
        operation: operationName,
      });
    } else {
      datadogRum.addError(error, {
        operation: operationName,
        error_code: error.code,
        error_kind: error.kind,
      });
    }
    throw error;
  }

  return payload.data as T;
}

// A stable per-browser guest id, so RUM sessions and BFF flag targeting line up
// on the same identity across reloads.
export function currentGuestId(): string {
  const key = 'all-demo-guest-id';
  let id = localStorage.getItem(key);
  if (!id) {
    id = `guest-${Math.random().toString(36).slice(2, 10)}`;
    localStorage.setItem(key, id);
  }
  return id;
}
