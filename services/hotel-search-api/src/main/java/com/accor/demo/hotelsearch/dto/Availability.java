package com.accor.demo.hotelsearch.dto;

import java.util.List;

public record Availability(
        long hotelId,
        boolean available,
        int roomsLeft,
        List<RoomOffer> offers
) {}
