package com.example.service;

import org.springframework.web.bind.annotation.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

// Pattern: Profiling — gradual memory allocation in a cache
// Adapt: use a domain-relevant cache concept
@RestController
public class MemoryLeakService {

    private final Map<String, byte[]> cache = new ConcurrentHashMap<>();

    @PostMapping("/api/cache")
    public Map<String, Object> addToCache(@RequestParam String key) {
        cache.put(key, new byte[1024 * 100]); // 100KB per entry
        return Map.of("cached", cache.size(), "key", key);
    }
}
