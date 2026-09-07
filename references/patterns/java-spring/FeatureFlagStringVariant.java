package com.example.service;

import dev.openfeature.sdk.*;

// Pattern: Feature Flags — string variant for A/B branching
// Adapt: replace "ui-theme" with your flag key; variant values must match Datadog flag config
public class FeatureFlagStringVariant {

    private static Client getClient() {
        return OpenFeatureAPI.getInstance().getClient(); // provider initialized in FeatureFlagBooleanGate
    }

    public String getUiVariant(String userId) {
        EvaluationContext ctx = new MutableContext(userId);
        String variant = getClient().getStringValue("ui-theme", "control", ctx);
        return switch (variant) {
            case "treatment-a" -> "new_design_a";
            case "treatment-b" -> "new_design_b";
            default -> "control_design";
        };
    }
}
