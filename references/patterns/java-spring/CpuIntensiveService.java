package com.example.service;

import org.springframework.web.bind.annotation.*;
import java.util.*;

// Pattern: Profiling — CPU-intensive nested loop
// Adapt: replace with domain-relevant aggregation logic
@RestController
public class CpuIntensiveService {

    @GetMapping("/api/aggregate")
    public Map<String, Object> aggregate() {
        Map<String, Long> counts = new HashMap<>();
        for (int i = 0; i < 100; i++) {
            counts.clear();
            for (int j = 0; j < 10000; j++) {
                String key = "bucket-" + (j % 50);
                counts.merge(key, 1L, Long::sum);
            }
        }
        return Map.of("buckets", counts.size(), "iterations", 100 * 10000);
    }
}
