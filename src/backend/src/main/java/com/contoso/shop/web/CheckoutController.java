package com.contoso.shop.web;

import com.contoso.shop.model.CheckoutRequest;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/checkout")
public class CheckoutController {

    @PostMapping
    public void pay(@RequestBody(required = false) CheckoutRequest request) {
        int itemCount = request == null || request.items() == null ? 0 : request.items().size();
        throw new CheckoutException("Payment processing failed for basket with " + itemCount + " item(s).");
    }
}
