from ddtrace import tracer
from openfeature import api
from ddtrace.openfeature import DataDogProvider
from openfeature.evaluation_context import EvaluationContext

# Pattern: Feature Flags — boolean gate with user targeting context
# Deps: ddtrace>=3.19.0, openfeature-sdk>=0.5.0
# Adapt: replace "checkout-new-flow" with your flag key; add domain attributes to context

tracer.configure()
api.set_provider(DataDogProvider())
_client = api.get_client()


def is_checkout_enabled(user_id: str, plan: str) -> bool:
    ctx = EvaluationContext(targeting_key=user_id, attributes={"plan": plan})
    return _client.get_boolean_value("checkout-new-flow", False, ctx)
