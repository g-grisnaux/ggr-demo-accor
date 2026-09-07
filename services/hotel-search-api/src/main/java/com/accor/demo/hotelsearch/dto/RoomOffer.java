package com.accor.demo.hotelsearch.dto;

public record RoomOffer(
        String rateCode,
        String roomType,
        String boardType,
        long pricePerNightCents,
        long totalPriceCents,
        String currency,
        boolean refundable,
        int loyaltyPointsEarned
) {}
