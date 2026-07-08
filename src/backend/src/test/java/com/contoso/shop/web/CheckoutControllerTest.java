package com.contoso.shop.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(CheckoutController.class)
@Import(GlobalExceptionHandler.class)
class CheckoutControllerTest {

    @Autowired
    MockMvc mockMvc;

    @Test
    void checkoutAlwaysReturns500() throws Exception {
        String body = "{\"items\":[{\"id\":\"coffee-mug\",\"quantity\":2}]}";
        mockMvc.perform(post("/api/checkout")
                        .contentType("application/json")
                        .content(body))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").exists());
    }
}
