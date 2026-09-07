package com.accor.demo.hotelsearch;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok", "service", System.getenv().getOrDefault("DD_SERVICE", "hotel-search-api"));
    }
}
