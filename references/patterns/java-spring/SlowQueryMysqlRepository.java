package com.example.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Map;

// Pattern: DBM slow query — artificial delay via MySQL SLEEP
// Adapt: replace 'your_table' with a domain entity table
@Repository
public class SlowQueryMysqlRepository {

    private final JdbcTemplate jdbc;

    public SlowQueryMysqlRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> findAllSlow() {
        return jdbc.queryForList(
            "SELECT *, SLEEP(0.3) FROM your_table ORDER BY created_at DESC LIMIT 50"
        );
    }
}
