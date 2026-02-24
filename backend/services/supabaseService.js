/**
 * Supabase Service - Web2 Read Cache
 * Ownership updates originate ONLY from blockchain events
 */

const { createClient } = require('@supabase/supabase-js');

let supabase;

function getSupabase() {
  if (!supabase) {
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY;
    if (!url || !key) {
      throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY required');
    }
    supabase = createClient(url, key);
  }
  return supabase;
}

async function upsertLandMetadata(landRecord) {
  const client = getSupabase();
  const { error } = await client
    .from('land_metadata')
    .upsert({
      property_id: landRecord.propertyId,
      owner_id: landRecord.ownerId,
      survey_number: landRecord.surveyNumber,
      subdivision_number: landRecord.subdivisionNumber,
      area: landRecord.area,
      application_status: landRecord.officerApproval || 'PENDING',
      updated_at: new Date().toISOString()
    }, { onConflict: 'property_id' });
  return { error };
}

async function getLandMetadata(propertyId) {
  const client = getSupabase();
  const { data, error } = await client
    .from('land_metadata')
    .select('*')
    .eq('property_id', propertyId)
    .single();
  return { data, error };
}

module.exports = { getSupabase, upsertLandMetadata, getLandMetadata };
