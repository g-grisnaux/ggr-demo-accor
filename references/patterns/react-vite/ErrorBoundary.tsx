import { datadogRum } from '@datadog/browser-rum';
import { Component, ReactNode } from 'react';

// Pattern: Error boundary with RUM error reporting
// Adapt: wrap domain-critical UI sections
interface Props { children: ReactNode; }
interface State { hasError: boolean; }

export default class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError() { return { hasError: true }; }

  componentDidCatch(error: Error) {
    datadogRum.addError(error, { source: 'component' });
  }

  render() {
    if (this.state.hasError) return <div>Something went wrong.</div>;
    return this.props.children;
  }
}
