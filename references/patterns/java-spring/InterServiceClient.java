package com.example.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

// Pattern: Cross-service HTTP call — tracing headers propagated
// automatically by dd-java-agent. Adapt: inject the target
// service URL via environment variable.
@Component
public class InterServiceClient {

    private final RestTemplate rest = new RestTemplate();

    @Value("${TARGET_SERVICE_URL:http://localhost:8080}")
    private String targetUrl;

    public String call(String path) {
        return rest.getForObject(targetUrl + path, String.class);
    }
}
