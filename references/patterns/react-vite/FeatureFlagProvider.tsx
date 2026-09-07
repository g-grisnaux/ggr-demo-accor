import { DatadogProvider } from '@datadog/openfeature-browser';
import { OpenFeature } from '@openfeature/react-sdk';

// Pattern: Feature Flags — DatadogProvider init for OpenFeature React SDK
// Deps: @datadog/openfeature-browser, @openfeature/react-sdk, @openfeature/core
// Call initFeatureFlags() after datadogRum.init() and after user identity is known
// targetingKey must match the userId passed to datadogRum.setUser() (see UserIdentification.tsx)
// DatadogProvider hooks into the existing DD_RUM global — does NOT re-initialize RUM
// Adapt: add domain-specific attributes to context (plan, role, etc.)

const _provider = new DatadogProvider({
  applicationId: import.meta.env.VITE_DD_RUM_APPLICATION_ID,
  clientToken: import.meta.env.VITE_DD_RUM_CLIENT_TOKEN,
  site: import.meta.env.VITE_DD_SITE || 'datadoghq.com',
  env: import.meta.env.VITE_DD_ENV || 'local',
});

export function initFeatureFlags(userId: string, plan: string): void {
  OpenFeature.setProvider(_provider, { targetingKey: userId, plan });
}
