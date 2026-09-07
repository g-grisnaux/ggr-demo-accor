import logging
from flask import request

# Pattern: SIEM — structured audit log for auth-relevant events
# Adapt: log fields relevant to your domain's security events
audit = logging.getLogger("audit")


def audit_log_after_request(response):
    audit.info(
        "request",
        extra={
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "remote": request.remote_addr,
        },
    )
    return response
