package com.contoso.shop.model;

import java.util.List;

public record CheckoutRequest(List<Item> items) {
    public record Item(String id, int quantity) {
    }
}
