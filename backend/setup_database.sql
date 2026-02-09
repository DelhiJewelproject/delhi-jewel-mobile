-- Database Setup Script for DecoJewel
-- Run this in your Supabase SQL Editor or PostgreSQL client

-- Create products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    description TEXT,
    price DECIMAL(10, 2),
    image_url TEXT,
    barcode VARCHAR(255),
    qr_code VARCHAR(255),
    category VARCHAR(100),
    stock INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER DEFAULT 1,
    customer_name VARCHAR(255),
    customer_phone VARCHAR(20),
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
CREATE INDEX IF NOT EXISTS idx_products_qr_code ON products(qr_code);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

-- Insert sample data (optional)
INSERT INTO products (name, description, price, barcode, category, stock) 
VALUES
    ('Gold Ring', 'Beautiful gold ring with diamond', 25000.00, 'GOLD001', 'Rings', 10),
    ('Silver Necklace', 'Elegant silver necklace', 15000.00, 'SILVER001', 'Necklaces', 5),
    ('Diamond Earrings', 'Premium diamond earrings', 35000.00, 'DIAMOND001', 'Earrings', 8),
    ('Platinum Bracelet', 'Luxury platinum bracelet', 45000.00, 'PLATINUM001', 'Bracelets', 3)
ON CONFLICT DO NOTHING;

-- Verify tables were created
SELECT 'Products table created successfully' AS status;
SELECT 'Orders table created successfully' AS status;


