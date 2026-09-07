package com.example.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

// Pattern: DBM N+1 — one query per parent row (MySQL)
// Adapt: replace table/column names with domain entities
@RestController
public class NplusOneMysqlController {

    private final JdbcTemplate jdbc;

    public NplusOneMysqlController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/api/mysql/items-with-details")
    public List<Map<String, Object>> itemsWithDetails() {
        List<Map<String, Object>> parents = jdbc.queryForList("SELECT * FROM parents");
        for (Map<String, Object> parent : parents) {
            parent.put("children", jdbc.queryForList(
                "SELECT * FROM children WHERE parent_id = ?", parent.get("id")
            ));
        }
        return parents;
    }
}
