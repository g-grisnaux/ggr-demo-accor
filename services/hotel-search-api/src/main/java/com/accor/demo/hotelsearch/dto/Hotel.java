package com.accor.demo.hotelsearch.dto;

import java.util.List;

// REST DTOs are serialized in snake_case (see application.properties) because
// that is the contract the BFF's mappers already expect from the other teams'
// APIs.
public record Hotel(
        long hotelId,
        String name,
        String brand,
        String city,
        String country,
        int starRating,
        double guestRating,
        String address,
        List<String> amenities,
        String thumbnailUrl
) {}
