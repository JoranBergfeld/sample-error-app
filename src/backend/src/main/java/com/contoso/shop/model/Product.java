package com.contoso.shop.model;

public record Product(String id, String name, String description, int priceCents, String emoji) {
}
