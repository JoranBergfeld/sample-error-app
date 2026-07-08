package com.contoso.shop.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(CheckoutException.class)
    public ResponseEntity<Map<String, String>> handleCheckout(CheckoutException ex) {
        // Logged at ERROR so the Application Insights Java agent records an exception,
        // and the 500 response is recorded as a failed request (resultCode >= 500).
        log.error("Checkout failed", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Payment failed. Please try again later."));
    }
}
