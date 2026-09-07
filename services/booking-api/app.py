import logging
import os
import random
import string
from datetime import date, datetime

import psycopg
import requests
from datadog import DogStatsd
from ddtrace import tracer
from flask import Flask, jsonify, request
from psycopg.rows import dict_row
from pythonjsonlogger import jsonlogger

# --- JSON Logging Setup ---
logger = logging.getLogger()
handler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(
    fmt="%(asctime)s %(levelname)s %(name)s %(message)s",
    rename_fields={"asctime": "timestamp", "levelname": "level"},
)
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

app = Flask(__name__)

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://accor:accor@postgresql:5432/accor")
PAYMENT_URL = os.environ.get("PAYMENT_URL", "http://payment-api:8083")
HOTEL_SEARCH_URL = os.environ.get("HOTEL_SEARCH_URL", "http://hotel-search-api:8081")

statsd = DogStatsd(
    host=os.environ.get("DD_AGENT_HOST", "localhost"),
    port=8125,
    constant_tags=[
        f"env:{os.environ.get('DD_ENV', 'dev')}",
        f"service:{os.environ.get('DD_SERVICE', 'booking-api')}",
        f"version:{os.environ.get('DD_VERSION', '1.0.0')}",
    ],
)

MAX_NIGHTS = 30


def connect():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


def booking_reference():
    return "ALL" + "".join(random.choices(string.ascii_uppercase + string.digits, k=7))


def reject(error_code, message, status=400, **extra):
    """Business rejections carry a stable machine-readable code.

    The BFF maps these onto its public GraphQL error codes, so renaming one here
    is a breaking change for clients — hence the fixed vocabulary.
    """
    statsd.increment("booking.rejected", tags=[f"error_code:{error_code}"])
    logger.warning("booking rejected error_code=%s message=%s", error_code, message)
    payload = {"error_code": error_code, "message": message}
    payload.update(extra)
    return jsonify(payload), status


def validate_stay(check_in_raw, check_out_raw):
    """Returns (check_in, check_out, nights) or raises ValueError with a code."""
    try:
        check_in = date.fromisoformat(check_in_raw)
        check_out = date.fromisoformat(check_out_raw)
    except (TypeError, ValueError):
        raise ValueError("invalid_date_range")

    if check_out <= check_in:
        raise ValueError("invalid_date_range")
    if check_in < date.today():
        raise ValueError("past_check_in")
    if (check_out - check_in).days > MAX_NIGHTS:
        raise ValueError("invalid_date_range")

    return check_in, check_out, (check_out - check_in).days


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": os.environ.get("DD_SERVICE", "booking-api")})


@app.route("/bookings", methods=["POST"])
def create_booking():
    body = request.get_json(silent=True) or {}

    hotel_id = body.get("hotel_id")
    guest_id = body.get("guest_id")
    rate_code = body.get("rate_code")

    if not hotel_id or not guest_id or not rate_code:
        return reject("invalid_request", "hotel_id, guest_id and rate_code are required")

    try:
        check_in, check_out, nights = validate_stay(body.get("check_in"), body.get("check_out"))
    except ValueError as exc:
        code = str(exc)
        message = (
            "Check-in cannot be in the past"
            if code == "past_check_in"
            else f"Stay must be 1-{MAX_NIGHTS} nights with check-out after check-in"
        )
        return reject(code, message)

    guests = int(body.get("guests") or 2)

    span = tracer.current_span()
    if span:
        span.set_tag("booking.hotel_id", hotel_id)
        span.set_tag("booking.nights", nights)
        span.set_tag("booking.guests", guests)

    # Price and inventory both come from the rate owner. Trusting a price sent
    # by the client would be a way to book a suite for the price of a single.
    try:
        availability = requests.get(
            f"{HOTEL_SEARCH_URL}/hotels/{hotel_id}/availability",
            params={"checkIn": check_in.isoformat(), "checkOut": check_out.isoformat()},
            timeout=5,
        )
        availability.raise_for_status()
        avail = availability.json()
    except requests.RequestException as exc:
        logger.error("availability lookup failed hotel_id=%s error=%s", hotel_id, exc)
        statsd.increment("booking.upstream_error", tags=["upstream:hotel-search-api"])
        return reject("upstream_unavailable", "Could not confirm availability", status=503)

    if not avail.get("available"):
        return reject("no_availability", "No rooms left for this stay", status=409)

    offer = next((o for o in avail.get("offers", []) if o.get("rate_code") == rate_code), None)
    if offer is None:
        # The client is holding a rate that no longer exists — a stale price the
        # front should refresh rather than an availability problem.
        return reject("rate_expired", f"Rate {rate_code} is no longer available", status=409)

    total_price_cents = int(offer["total_price_cents"])
    currency = offer.get("currency", "EUR")
    reference = booking_reference()

    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO bookings (reference, status, hotel_id, guest_id, check_in, check_out,
                                      guests, rate_code, room_type, total_price_cents, currency)
                VALUES (%s, 'PENDING_PAYMENT', %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING booking_id, created_at
                """,
                (
                    reference,
                    hotel_id,
                    guest_id,
                    check_in,
                    check_out,
                    guests,
                    rate_code,
                    offer.get("room_type"),
                    total_price_cents,
                    currency,
                ),
            )
            row = cur.fetchone()
            booking_id = row["booking_id"]
            created_at = row["created_at"]
        conn.commit()

    # Authorize against the payment partner. This is the third hop of the trace:
    # graphql-bff -> booking-api -> payment-api.
    payment = None
    try:
        resp = requests.post(
            f"{PAYMENT_URL}/payments",
            json={
                "booking_id": booking_id,
                "amount_cents": total_price_cents,
                "currency": currency,
                "method": body.get("payment_method") or "VISA",
            },
            timeout=8,
        )
        payment = resp.json()
    except requests.RequestException as exc:
        logger.error("payment call failed booking_id=%s error=%s", booking_id, exc)
        statsd.increment("booking.upstream_error", tags=["upstream:payment-api"])
        _set_status(booking_id, "PAYMENT_FAILED")
        return reject("upstream_unavailable", "Payment service unreachable", status=503)

    if resp.status_code == 402:
        # A refused card leaves the booking behind in a terminal state rather
        # than deleting it — support needs to see the attempt.
        _set_status(booking_id, "PAYMENT_DECLINED")
        statsd.increment(
            "booking.rejected",
            tags=[f"error_code:payment_declined", f"decline_reason:{payment.get('decline_reason')}"],
        )
        logger.warning(
            "booking payment declined booking_id=%s reference=%s decline_reason=%s",
            booking_id,
            reference,
            payment.get("decline_reason"),
        )
        return (
            jsonify(
                {
                    "error_code": "payment_declined",
                    "message": payment.get("message", "Payment was declined"),
                    "decline_reason": payment.get("decline_reason"),
                    "booking_id": booking_id,
                    "reference": reference,
                }
            ),
            402,
        )

    if resp.status_code >= 400:
        _set_status(booking_id, "PAYMENT_FAILED")
        return reject("upstream_unavailable", "Payment could not be processed", status=503)

    _set_status(booking_id, "CONFIRMED")
    statsd.increment("booking.confirmed", tags=[f"currency:{currency}"])
    logger.info(
        "booking confirmed booking_id=%s reference=%s total_price_cents=%s",
        booking_id,
        reference,
        total_price_cents,
    )

    return (
        jsonify(
            {
                "booking_id": booking_id,
                "reference": reference,
                "status": "CONFIRMED",
                "hotel_id": hotel_id,
                "guest_id": guest_id,
                "check_in": check_in.isoformat(),
                "check_out": check_out.isoformat(),
                "guests": guests,
                "rate_code": rate_code,
                "room_type": offer.get("room_type"),
                "total_price_cents": total_price_cents,
                "currency": currency,
                "created_at": created_at.isoformat() if isinstance(created_at, datetime) else str(created_at),
                "payment": payment,
            }
        ),
        201,
    )


def _set_status(booking_id, status):
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE bookings SET status = %s WHERE booking_id = %s", (status, booking_id))
        conn.commit()


@app.route("/bookings/<int:booking_id>")
def get_booking(booking_id):
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT b.booking_id, b.reference, b.status, b.hotel_id, b.guest_id,
                       b.check_in, b.check_out, b.guests, b.rate_code, b.room_type,
                       b.total_price_cents, b.currency, b.created_at,
                       p.payment_id, p.status AS payment_status, p.amount_cents,
                       p.method, p.decline_reason
                FROM bookings b
                LEFT JOIN payments p ON p.booking_id = b.booking_id
                WHERE b.booking_id = %s
                ORDER BY p.created_at DESC
                LIMIT 1
                """,
                (booking_id,),
            )
            row = cur.fetchone()

    if row is None:
        return jsonify({"error_code": "booking_not_found", "message": "No such booking"}), 404

    return jsonify(_serialize(row))


@app.route("/bookings")
def list_bookings():
    guest_id = request.args.get("guestId")
    if not guest_id:
        return reject("invalid_request", "guestId is required")

    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT b.booking_id, b.reference, b.status, b.hotel_id, b.guest_id,
                       b.check_in, b.check_out, b.guests, b.rate_code, b.room_type,
                       b.total_price_cents, b.currency, b.created_at,
                       p.payment_id, p.status AS payment_status, p.amount_cents,
                       p.method, p.decline_reason
                FROM bookings b
                LEFT JOIN payments p ON p.booking_id = b.booking_id
                WHERE b.guest_id = %s
                ORDER BY b.created_at DESC
                LIMIT 25
                """,
                (guest_id,),
            )
            rows = cur.fetchall()

    return jsonify({"bookings": [_serialize(r) for r in rows]})


def _serialize(row):
    payment = None
    if row.get("payment_id"):
        payment = {
            "payment_id": row["payment_id"],
            "status": row["payment_status"],
            "amount_cents": row["amount_cents"],
            "currency": row["currency"],
            "method": row["method"],
            "decline_reason": row["decline_reason"],
        }
    return {
        "booking_id": row["booking_id"],
        "reference": row["reference"],
        "status": row["status"],
        "hotel_id": row["hotel_id"],
        "guest_id": row["guest_id"],
        "check_in": row["check_in"].isoformat(),
        "check_out": row["check_out"].isoformat(),
        "guests": row["guests"],
        "rate_code": row["rate_code"],
        "room_type": row["room_type"],
        "total_price_cents": row["total_price_cents"],
        "currency": row["currency"],
        "created_at": row["created_at"].isoformat(),
        "payment": payment,
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8082"))
    app.run(host="0.0.0.0", port=port)
