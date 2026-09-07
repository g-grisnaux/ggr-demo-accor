package com.example.service;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.io.IOException;

// Pattern: SIEM — structured audit log for auth-relevant events
// Adapt: log fields relevant to your domain's security events
public class AuditLogFilter implements Filter {

    private static final Logger audit = LoggerFactory.getLogger("audit");

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {
        HttpServletRequest httpReq = (HttpServletRequest) req;
        chain.doFilter(req, res);
        int status = ((HttpServletResponse) res).getStatus();
        audit.info("request", new Object[]{
            "method", httpReq.getMethod(),
            "path", httpReq.getRequestURI(),
            "status", status,
            "remote", httpReq.getRemoteAddr()
        });
    }
}
