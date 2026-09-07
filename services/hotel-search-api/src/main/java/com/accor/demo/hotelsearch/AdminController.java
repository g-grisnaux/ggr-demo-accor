package com.accor.demo.hotelsearch;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Demo scenario controls. Not exposed through the ingress — reachable only from
 * inside the cluster (kubectl port-forward or an exec'd curl), so triggering a
 * failure stays a deliberate act.
 */
@RestController
public class AdminController {

    private static final Logger log = LoggerFactory.getLogger(AdminController.class);

    private final DemoControls controls;

    public AdminController(DemoControls controls) {
        this.controls = controls;
    }

    @GetMapping("/admin/scenario")
    public Map<String, Boolean> current() {
        return Map.of(
                "slow_search", controls.isSlowSearch(),
                "expensive_ranking", controls.isExpensiveRanking()
        );
    }

    @PostMapping("/admin/scenario")
    public Map<String, Boolean> update(
            @RequestParam(required = false) Boolean slowSearch,
            @RequestParam(required = false) Boolean expensiveRanking
    ) {
        if (slowSearch != null) {
            controls.setSlowSearch(slowSearch);
            log.warn("demo scenario changed slow_search={}", slowSearch);
        }
        if (expensiveRanking != null) {
            controls.setExpensiveRanking(expensiveRanking);
            log.warn("demo scenario changed expensive_ranking={}", expensiveRanking);
        }
        return current();
    }
}
