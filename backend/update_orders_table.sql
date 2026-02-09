-- Update or create professional Orders Table for DecoJewel
-- This script will add missing columns if table exists, or create new table

-- Check if table exists and create/update accordingly
DO $$
BEGIN
    -- Create table if it doesn't exist
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'orders') THEN
        CREATE TABLE orders (
            id SERIAL PRIMARY KEY,
            order_number VARCHAR(50) UNIQUE NOT NULL,
            product_id INTEGER REFERENCES product_catalog(id) ON DELETE SET NULL,
            product_external_id INTEGER,
            product_name VARCHAR(500),
            size_id INTEGER,
            size_text VARCHAR(100),
            quantity INTEGER NOT NULL DEFAULT 1,
            unit_price DECIMAL(12, 2),
            total_price DECIMAL(12, 2) NOT NULL,
            customer_name VARCHAR(255) NOT NULL,
            customer_phone VARCHAR(20),
            customer_email VARCHAR(255),
            customer_address TEXT,
            order_status VARCHAR(50) DEFAULT 'pending' CHECK (order_status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')),
            payment_status VARCHAR(50) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'partial', 'paid', 'refunded')),
            payment_method VARCHAR(50),
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            created_by VARCHAR(100)
        );
    ELSE
        -- Add missing columns if table exists
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_number VARCHAR(50);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS product_external_id INTEGER;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS product_name VARCHAR(500);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS size_id INTEGER;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS size_text VARCHAR(100);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS unit_price DECIMAL(12, 2);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_price DECIMAL(12, 2);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_email VARCHAR(255);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_address TEXT;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'pending';
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50);
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS notes TEXT;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS created_by VARCHAR(100);
        
        -- Rename status to order_status if needed
        DO $$
        BEGIN
            IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'status') 
               AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'order_status') THEN
                ALTER TABLE orders RENAME COLUMN status TO order_status;
            END IF;
        END $$;
        
        -- Make order_number unique if not already
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_order_number_key') THEN
                ALTER TABLE orders ADD CONSTRAINT orders_order_number_key UNIQUE (order_number);
            END IF;
        END $$;
    END IF;
END $$;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_phone ON orders(customer_phone);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(order_status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_customer_name ON orders(customer_name);

-- Create function to generate order number
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS VARCHAR(50) AS $$
DECLARE
    new_order_number VARCHAR(50);
    order_count INTEGER;
BEGIN
    -- Get count of orders today
    SELECT COUNT(*) INTO order_count
    FROM orders
    WHERE DATE(created_at) = CURRENT_DATE;
    
    -- Format: DJ-YYYYMMDD-XXXX (e.g., DJ-20250112-0001)
    new_order_number := 'DJ-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || 
                       LPAD((order_count + 1)::TEXT, 4, '0');
    
    RETURN new_order_number;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_orders_updated_at ON orders;
CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


