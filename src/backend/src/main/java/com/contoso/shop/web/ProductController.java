package com.contoso.shop.web;

import com.contoso.shop.model.Product;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private static final List<Product> CATALOG = List.of(
            new Product("coffee-mug", "Ceramic Coffee Mug", "A sturdy 350ml mug.", 1299, "☕"),
            new Product("notebook", "Dotted Notebook", "A5 dotted, 120gsm paper.", 1899, "📓"),
            new Product("pen-set", "Gel Pen Set", "Pack of 5 smooth gel pens.", 799, "🖊️"),
            new Product("desk-lamp", "LED Desk Lamp", "Dimmable, warm/cool light.", 3499, "💡"),
            new Product("headphones", "Wireless Headphones", "Over-ear, 30h battery.", 8999, "🎧"),
            new Product("water-bottle", "Insulated Bottle", "Keeps drinks cold 24h.", 2499, "🍶")
    );

    @GetMapping
    public List<Product> list() {
        return CATALOG;
    }
}
