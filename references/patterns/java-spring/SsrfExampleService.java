package com.example.service;

import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

// Pattern: Code Security — SSRF via unvalidated URL parameter
// WARNING: intentionally vulnerable for IAST demo
// Adapt: use a domain-appropriate endpoint name
@RestController
public class SsrfExampleService {

    @GetMapping("/api/fetch-url")
    public String fetchUrl(@RequestParam String url) {
        return new RestTemplate().getForObject(url, String.class);
    }
}
