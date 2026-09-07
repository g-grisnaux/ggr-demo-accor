package com.accor.demo.hotelsearch;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Runtime switches for the demo scenarios. They start from environment
 * variables so a scenario can be baked into a deployment, and can be flipped
 * live from /admin so a failure can be triggered mid-presentation without a
 * redeploy.
 */
@Component
public class DemoControls {

    private final AtomicBoolean slowSearch = new AtomicBoolean(false);
    private final AtomicBoolean expensiveRanking = new AtomicBoolean(false);

    public DemoControls(
            @Value("${HOTEL_SEARCH_SLOW_MODE:false}") boolean slowSearchDefault,
            @Value("${HOTEL_SEARCH_EXPENSIVE_RANKING:false}") boolean expensiveRankingDefault
    ) {
        this.slowSearch.set(slowSearchDefault);
        this.expensiveRanking.set(expensiveRankingDefault);
    }

    public boolean isSlowSearch() {
        return slowSearch.get();
    }

    public void setSlowSearch(boolean value) {
        slowSearch.set(value);
    }

    public boolean isExpensiveRanking() {
        return expensiveRanking.get();
    }

    public void setExpensiveRanking(boolean value) {
        expensiveRanking.set(value);
    }
}
