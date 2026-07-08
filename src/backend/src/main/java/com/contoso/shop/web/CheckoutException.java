package com.contoso.shop.web;

public class CheckoutException extends RuntimeException {
    public CheckoutException(String message) {
        super(message);
    }
}
