// Public GraphQL schema — the single entry point for web and mobile clients.
// Downstream REST APIs are owned by other teams and never exposed directly.
const typeDefs = /* GraphQL */ `
  type Hotel {
    id: ID!
    name: String!
    brand: String
    city: String!
    country: String
    starRating: Int
    guestRating: Float
    address: String
    amenities: [String!]!

    "Availability for the stay carried by the enclosing search."
    availability: Availability

    thumbnailUrl: String @deprecated(reason: "Use media.heroImage — removed once iOS 6.2 adoption passes 95%")
  }

  type Availability {
    hotelId: ID!
    available: Boolean!
    roomsLeft: Int!
    offers: [RoomOffer!]!
  }

  type RoomOffer {
    rateCode: String!
    roomType: String!
    boardType: String
    pricePerNight: Float
    totalPrice: Float
    currency: String!
    refundable: Boolean!
    loyaltyPointsEarned: Int!
  }

  type Payment {
    id: ID!
    status: String!
    amount: Float
    currency: String!
    method: String
    declineReason: String
  }

  type Booking {
    id: ID!
    reference: String!
    status: String!
    hotelId: ID!
    guestId: ID!
    checkIn: String!
    checkOut: String!
    guests: Int!
    roomType: String
    totalPrice: Float
    currency: String!
    createdAt: String
    payment: Payment

    "Resolved from hotel-search-api — the join the clients used to do themselves."
    hotel: Hotel
  }

  type SearchResult {
    nights: Int!
    resultCount: Int!
    hotels: [Hotel!]!
  }

  input CreateBookingInput {
    hotelId: ID!
    guestId: ID!
    checkIn: String!
    checkOut: String!
    guests: Int!
    rateCode: String!
    roomType: String
    paymentMethod: String!
  }

  type Query {
    searchHotels(city: String!, checkIn: String!, checkOut: String!, guests: Int = 2): SearchResult!
    hotel(id: ID!): Hotel
    booking(id: ID!): Booking
    bookings(guestId: ID!): [Booking!]!
  }

  type Mutation {
    createBooking(input: CreateBookingInput!): Booking!
  }
`;

module.exports = { typeDefs };
