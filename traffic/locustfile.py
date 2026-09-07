"""Load generator for the ALL booking BFF.

Everything goes through the public GraphQL endpoint, the way a real client would.
Traffic is deliberately mixed: several client platforms and versions, a realistic
proportion of business rejections, and one cohort still requesting a deprecated
field — that mix is what makes the operation, field-usage and error-code
dashboards look like production rather than a synthetic loop.
"""

import random
from datetime import date, timedelta

from locust import HttpUser, between, task

CITIES = ["Paris", "Lyon", "Marseille", "Nice", "London", "Amsterdam", "Berlin", "Madrid"]

# Weighted so no single client dominates, and so the deprecated-field cohort is
# a visible minority rather than noise.
CLIENTS = [
    ("all-web", "3.4.0", 40),
    ("all-ios", "6.2.0", 25),
    ("all-ios", "6.1.0", 15),
    ("all-android", "5.9.0", 20),
]

SEARCH_QUERY = """
query SearchHotels($city: String!, $checkIn: String!, $checkOut: String!, $guests: Int) {
  searchHotels(city: $city, checkIn: $checkIn, checkOut: $checkOut, guests: $guests) {
    nights
    resultCount
    hotels {
      id
      name
      brand
      starRating
      guestRating
      availability { available roomsLeft offers { rateCode roomType totalPrice currency } }
    }
  }
}
"""

# Same operation, but requesting the deprecated thumbnailUrl. Older mobile builds
# still do this; field-usage metrics are how the team learns when it is safe to
# remove.
SEARCH_QUERY_LEGACY = """
query SearchHotelsLegacy($city: String!, $checkIn: String!, $checkOut: String!) {
  searchHotels(city: $city, checkIn: $checkIn, checkOut: $checkOut) {
    resultCount
    hotels { id name thumbnailUrl availability { available offers { rateCode totalPrice } } }
  }
}
"""

CREATE_BOOKING = """
mutation CreateBooking($input: CreateBookingInput!) {
  createBooking(input: $input) {
    id reference status totalPrice currency
    payment { status method }
  }
}
"""

MY_BOOKINGS = """
query MyBookings($guestId: ID!) {
  bookings(guestId: $guestId) { id reference status totalPrice currency }
}
"""


def stay(offset_days=None, nights=None):
    start = date.today() + timedelta(days=offset_days or random.randint(2, 30))
    end = start + timedelta(days=nights or random.randint(1, 5))
    return start.isoformat(), end.isoformat()


class BookingUser(HttpUser):
    wait_time = between(1, 4)

    def on_start(self):
        names, versions, weights = zip(*[(c, v, w) for c, v, w in CLIENTS])
        index = random.choices(range(len(CLIENTS)), weights=weights, k=1)[0]
        self.client_name, self.client_version, _ = CLIENTS[index]
        self.guest_id = f"guest-{random.randint(1000, 9999)}"
        self.last_offer = None

    def headers(self):
        return {
            "content-type": "application/json",
            "x-client-name": self.client_name,
            "x-client-version": self.client_version,
            "x-guest-id": self.guest_id,
        }

    def gql(self, name, query, variables, expect_errors=False):
        with self.client.post(
            "/graphql",
            json={"operationName": name, "query": query, "variables": variables},
            headers=self.headers(),
            name=f"graphql {name}",
            catch_response=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
                return None

            body = resp.json()
            errors = body.get("errors") or []
            if errors and not expect_errors:
                code = (errors[0].get("extensions") or {}).get("code", "UNKNOWN")
                kind = (errors[0].get("extensions") or {}).get("kind", "SERVER")
                # A business rejection is a valid response, not a failed request.
                # Counting it as a Locust failure would make the load report
                # useless for spotting real outages.
                if kind == "BUSINESS":
                    resp.success()
                else:
                    resp.failure(f"{kind}:{code}")
                return None

            resp.success()
            return body.get("data")

    @task(50)
    def search(self):
        check_in, check_out = stay()
        data = self.gql(
            "SearchHotels",
            SEARCH_QUERY,
            {"city": random.choice(CITIES), "checkIn": check_in, "checkOut": check_out, "guests": random.randint(1, 4)},
        )
        if not data:
            return

        # Remember a bookable rate so the booking task exercises a real path
        # instead of guessing a rate code.
        for hotel in data["searchHotels"]["hotels"]:
            availability = hotel.get("availability") or {}
            if availability.get("available") and availability.get("offers"):
                self.last_offer = {
                    "hotelId": hotel["id"],
                    "rateCode": availability["offers"][0]["rateCode"],
                    "roomType": availability["offers"][0].get("roomType"),
                    "checkIn": check_in,
                    "checkOut": check_out,
                }
                break

    @task(12)
    def search_legacy_client(self):
        check_in, check_out = stay()
        self.gql(
            "SearchHotelsLegacy",
            SEARCH_QUERY_LEGACY,
            {"city": random.choice(CITIES), "checkIn": check_in, "checkOut": check_out},
        )

    @task(18)
    def book(self):
        if not self.last_offer:
            self.search()
            if not self.last_offer:
                return

        offer = self.last_offer
        self.gql(
            "CreateBooking",
            CREATE_BOOKING,
            {
                "input": {
                    "hotelId": offer["hotelId"],
                    "guestId": self.guest_id,
                    "checkIn": offer["checkIn"],
                    "checkOut": offer["checkOut"],
                    "guests": 2,
                    "rateCode": offer["rateCode"],
                    "roomType": offer["roomType"],
                    "paymentMethod": random.choice(["VISA", "MASTERCARD", "AMEX"]),
                }
            },
            expect_errors=True,
        )
        # The rate is consumed; force a fresh search next time round.
        self.last_offer = None

    @task(8)
    def my_bookings(self):
        self.gql("MyBookings", MY_BOOKINGS, {"guestId": self.guest_id})

    @task(6)
    def invalid_dates(self):
        """Real clients send reversed dates. Feeds the INVALID_DATE baseline."""
        check_in, check_out = stay()
        self.gql(
            "SearchHotels",
            SEARCH_QUERY,
            {"city": random.choice(CITIES), "checkIn": check_out, "checkOut": check_in, "guests": 2},
            expect_errors=True,
        )

    @task(3)
    def stay_too_long(self):
        """Over the 30-night limit — the other INVALID_DATE branch."""
        check_in, check_out = stay(offset_days=5, nights=45)
        self.gql(
            "SearchHotels",
            SEARCH_QUERY,
            {"city": random.choice(CITIES), "checkIn": check_in, "checkOut": check_out, "guests": 2},
            expect_errors=True,
        )
