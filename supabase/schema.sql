-- Land Registry Supabase Schema
-- Read cache only - ownership updates from blockchain events

CREATE TABLE IF NOT EXISTS land_metadata (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  property_id TEXT UNIQUE NOT NULL,
  owner_id TEXT NOT NULL,
  owner_name TEXT,
  address TEXT,
  survey_number TEXT NOT NULL,
  subdivision_number TEXT,
  area DECIMAL(12,2),
  application_status TEXT DEFAULT 'PENDING',
  document_hash TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_land_metadata_property_id ON land_metadata(property_id);
CREATE INDEX IF NOT EXISTS idx_land_metadata_survey ON land_metadata(survey_number, subdivision_number);
CREATE INDEX IF NOT EXISTS idx_land_metadata_owner ON land_metadata(owner_id);
CREATE INDEX IF NOT EXISTS idx_land_metadata_status ON land_metadata(application_status);
