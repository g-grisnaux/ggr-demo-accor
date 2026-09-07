import { datadogRum } from '@datadog/browser-rum';

// Pattern: RUM custom action — track user interactions
// Adapt: use domain-relevant action names and context
export default function CustomActionButton({ label, actionName }: { label: string; actionName: string }) {
  const handleClick = () => {
    datadogRum.addAction(actionName, { label, timestamp: Date.now() });
  };

  return <button onClick={handleClick}>{label}</button>;
}
