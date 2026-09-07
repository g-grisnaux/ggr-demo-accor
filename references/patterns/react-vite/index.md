# Instrumentation patterns — React Vite

| Pattern | Feature | Description |
|---------|---------|-------------|
| CustomActionButton.tsx | rum | RUM custom action tracking |
| UserIdentification.tsx | rum | RUM user identification |
| ErrorBoundary.tsx | rum | Error boundary with RUM error reporting |
| FeatureFlagProvider.tsx | delivery:feature-flags | DatadogProvider init for OpenFeature client-side SDK |
| FeatureFlagGate.tsx | delivery:feature-flags | Boolean gate and string variant via OpenFeature React hooks |
| design-system.md | all | DaisyUI component classes, theme location, rebrand instructions |

> **MCP tip:** When the [Datadog Feature Flag MCP server](https://docs.datadoghq.com/feature_flags/feature_flag_mcp_server/) is configured in Claude Code, an AI agent can create, validate, and update flags directly without leaving the IDE (`create-feature-flag`, `check-flag-implementation`, `list-feature-flags`). Currently React-only.
