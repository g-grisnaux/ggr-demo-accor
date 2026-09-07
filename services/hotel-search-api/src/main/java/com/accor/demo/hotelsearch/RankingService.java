package com.accor.demo.hotelsearch;

import com.accor.demo.hotelsearch.dto.Hotel;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.List;

/**
 * Relevance ranking applied on top of the SQL ordering.
 *
 * The expensive variant is the profiling scenario: a per-hotel score recomputed
 * against every other hotel in the result set, with the population statistics
 * rebuilt from scratch on every pass. It is pure CPU with no I/O, so it shows up
 * in the flame graph as one dominant frame inside hotel-search-api — the kind of
 * thing an endpoint latency metric can see but cannot explain.
 *
 * The arithmetic deliberately uses a square root per element. A plain weighted
 * sum gets factored out of the loop by the JIT, which made an earlier version of
 * this scenario collapse to a few milliseconds.
 */
@Service
public class RankingService {

    private final DemoControls controls;
    private final int passes;

    public RankingService(DemoControls controls, @Value("${HOTEL_SEARCH_RANKING_PASSES:60000}") int passes) {
        this.controls = controls;
        this.passes = passes;
    }

    public List<Hotel> rank(List<Hotel> hotels) {
        if (!controls.isExpensiveRanking()) {
            return hotels.stream()
                    .sorted(Comparator.comparingDouble(Hotel::guestRating).reversed())
                    .toList();
        }
        return hotels.stream()
                .sorted(Comparator.comparingDouble((Hotel h) -> relevanceScore(h, hotels)).reversed())
                .toList();
    }

    private double relevanceScore(Hotel hotel, List<Hotel> population) {
        double score = hotel.guestRating() * 10 + hotel.starRating();
        int size = Math.max(1, population.size());

        for (int pass = 1; pass <= passes; pass++) {
            double decay = 1.0 + (pass % 97) / 97.0;

            double mean = 0;
            for (Hotel other : population) {
                mean += Math.sqrt(other.guestRating() * decay + (pass % 13));
            }
            mean /= size;

            double variance = 0;
            for (Hotel other : population) {
                double delta = Math.sqrt(other.guestRating() * decay + (pass % 13)) - mean;
                variance += delta * delta;
            }
            variance /= size;

            double stdDev = Math.sqrt(variance);
            if (stdDev > 0) {
                score += (Math.sqrt(hotel.guestRating() * decay) - mean) / stdDev / passes;
            }
        }
        return score;
    }
}
