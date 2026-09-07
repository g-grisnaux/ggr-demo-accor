import { OpenFeatureProvider, useBooleanFlagValue, useStringFlagValue } from '@openfeature/react-sdk';

// Pattern: Feature Flags — boolean gate and string variant via OpenFeature React hooks
// Wrap your app root with <OpenFeatureProvider> after calling initFeatureFlags()
// Adapt: replace flag keys with your configured Datadog flag names

export { OpenFeatureProvider };

export function NewCheckoutGate({ children }: { children: React.ReactNode }) {
  const enabled = useBooleanFlagValue('checkout-new-flow', false);
  return enabled ? <>{children}</> : null;
}

export function ThemeVariant() {
  const variant = useStringFlagValue('ui-theme', 'control');
  const labels: Record<string, string> = { 'treatment-a': 'Theme A', 'treatment-b': 'Theme B' };
  return <div data-variant={variant}>{labels[variant] ?? 'Default Theme'}</div>;
}
