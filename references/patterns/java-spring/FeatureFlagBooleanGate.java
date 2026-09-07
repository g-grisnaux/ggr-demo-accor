package com.example.service;

import com.datadoghq.openfeature.Provider;
import dev.openfeature.sdk.*;

// Pattern: Feature Flags — boolean gate with user targeting context
// Deps: add to pom.xml:
//   com.datadoghq:dd-openfeature:1.57.0
//   dev.openfeature:sdk:1.18.2
// Adapt: replace "checkout-new-flow" with your flag key; add domain attributes to context
public class FeatureFlagBooleanGate {

    private static final Client client;

    static {
        OpenFeatureAPI api = OpenFeatureAPI.getInstance();
        api.setProviderAndWait(new Provider());
        client = api.getClient();
    }

    public boolean isCheckoutEnabled(String userId, String plan) {
        EvaluationContext ctx = new MutableContext(userId)
            .add("plan", plan);
        return client.getBooleanValue("checkout-new-flow", false, ctx);
    }
}
