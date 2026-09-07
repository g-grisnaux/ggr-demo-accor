import { datadogRum } from '@datadog/browser-rum';
import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  message: string;
}

/**
 * Wraps the booking journey. A crash here is reported to RUM with the component
 * stack, which is what turns "the ALL site broke" into a specific component and
 * a replayable session.
 */
export default class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, message: '' };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, message: error.message };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    datadogRum.addError(error, {
      source: 'react-error-boundary',
      component_stack: info.componentStack,
      journey: 'booking',
    });
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="mx-auto max-w-xl">
          <div className="alert alert-error">
            <div>
              <h3 className="font-bold">The booking journey crashed</h3>
              <p className="text-sm">{this.state.message}</p>
              <p className="mt-2 text-xs opacity-80">
                Reported to RUM with the component stack and the session replay.
              </p>
            </div>
          </div>
          <button className="btn btn-sm mt-4" onClick={() => this.setState({ hasError: false, message: '' })}>
            Reset
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
