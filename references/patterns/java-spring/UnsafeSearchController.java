package com.example.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

// Pattern: Code Security — SQL injection via string concatenation
// WARNING: intentionally vulnerable for IAST demo
// Adapt: replace table/column with domain entity
@RestController
public class UnsafeSearchController {

    private final JdbcTemplate jdbc;

    public UnsafeSearchController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/api/search")
    public List<Map<String, Object>> search(@RequestParam String q) {
        String sql = "SELECT * FROM items WHERE name LIKE '%" + q + "%'";
        return jdbc.queryForList(sql);
    }
}
