-- Labels Table for Delhi Jewel
-- This table stores label generation requests

CREATE TABLE IF NOT EXISTS labels (
    id SERIAL PRIMARY KEY,
    product_name VARCHAR(500) NOT NULL,
    product_size VARCHAR(100),
    number_of_labels INTEGER NOT NULL DEFAULT 1,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'generated', 'printed', 'cancelled')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_labels_product_name ON labels(product_name);
CREATE INDEX IF NOT EXISTS idx_labels_status ON labels(status);
CREATE INDEX IF NOT EXISTS idx_labels_created_at ON labels(created_at DESC);

