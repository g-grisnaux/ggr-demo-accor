package com.accor.demo.hotelsearch;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

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

    /**
     * Artificial delay on the availability endpoints, in milliseconds.
     *
     * This is the lever for the booking-outage scenario. It matters that it sits
     * on availability rather than on search: booking-api checks availability
     * *before* it calls the payment partner, so a slow availability endpoint
     * fails bookings without the payment service ever being involved — while
     * payment remains the slowest span on a healthy trace, and therefore the
     * obvious suspect. The cause is two hops from the symptom.
     */
    private final AtomicInteger availabilityDelayMs = new AtomicInteger(0);

    public DemoControls(
            @Value("${HOTEL_SEARCH_SLOW_MODE:false}") boolean slowSearchDefault,
            @Value("${HOTEL_SEARCH_EXPENSIVE_RANKING:false}") boolean expensiveRankingDefault,
            @Value("${HOTEL_SEARCH_AVAILABILITY_DELAY_MS:0}") int availabilityDelayDefault
    ) {
        this.slowSearch.set(slowSearchDefault);
        this.expensiveRanking.set(expensiveRankingDefault);
        this.availabilityDelayMs.set(availabilityDelayDefault);
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

    public int getAvailabilityDelayMs() {
        return availabilityDelayMs.get();
    }

    public void setAvailabilityDelayMs(int value) {
        availabilityDelayMs.set(Math.max(0, value));
    }

    /** Applies the configured availability delay, if any. */
    public void applyAvailabilityDelay() {
        int delay = availabilityDelayMs.get();
        if (delay <= 0) {
            return;
        }
        try {
            Thread.sleep(delay);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
