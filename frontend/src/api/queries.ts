export interface RoomOffer {
  rateCode: string;
  roomType: string;
  boardType: string | null;
  pricePerNight: number | null;
  totalPrice: number | null;
  currency: string;
  refundable: boolean;
  loyaltyPointsEarned: number;
}

export interface Availability {
  available: boolean;
  roomsLeft: number;
  offers: RoomOffer[];
}

export interface Hotel {
  id: string;
  name: string;
  brand: string | null;
  city: string;
  starRating: number | null;
  guestRating: number | null;
  amenities: string[];
  availability: Availability | null;
}

export interface SearchResult {
  nights: number;
  resultCount: number;
  hotels: Hotel[];
}

export interface Booking {
  id: string;
  reference: string;
  status: string;
  totalPrice: number | null;
  currency: string;
  checkIn: string;
  checkOut: string;
  payment: { status: string; method: string | null } | null;
  hotel: { name: string; city: string } | null;
}

// Availability is requested as a nested field on purpose: it is what makes the
// dataloader-versus-N+1 difference visible in a trace.
export const SEARCH_HOTELS = /* GraphQL */ `
  query SearchHotels($city: String!, $checkIn: String!, $checkOut: String!, $guests: Int) {
    searchHotels(city: $city, checkIn: $checkIn, checkOut: $checkOut, guests: $guests) {
      nights
      resultCount
      hotels {
        id
        name
        brand
        city
        starRating
        guestRating
        amenities
        availability {
          available
          roomsLeft
          offers {
            rateCode
            roomType
            boardType
            pricePerNight
            totalPrice
            currency
            refundable
            loyaltyPointsEarned
          }
        }
      }
    }
  }
`;

export const CREATE_BOOKING = /* GraphQL */ `
  mutation CreateBooking($input: CreateBookingInput!) {
    createBooking(input: $input) {
      id
      reference
      status
      totalPrice
      currency
      checkIn
      checkOut
      payment {
        status
        method
      }
      hotel {
        name
        city
      }
    }
  }
`;

export const MY_BOOKINGS = /* GraphQL */ `
  query MyBookings($guestId: ID!) {
    bookings(guestId: $guestId) {
      id
      reference
      status
      totalPrice
      currency
      checkIn
      checkOut
      payment {
        status
        method
      }
      hotel {
        name
        city
      }
    }
  }
`;
