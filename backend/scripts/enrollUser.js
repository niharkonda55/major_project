#!/usr/bin/env node
/**
 * Enroll a user into the Fabric wallet
 * Usage: node scripts/enrollUser.js <org> <userId> <userSecret>
 * Example: node scripts/enrollUser.js revenuedept vro1 vro1pw
 */

require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { enrollUser } = require('../services/enrollService');

async function main() {
  const [org, userId, userSecret] = process.argv.slice(2);
  if (!org || !userId || !userSecret) {
    console.error('Usage: node enrollUser.js <org> <userId> <userSecret>');
    console.error('Example: node enrollUser.js revenuedept vro1 vro1pw');
    process.exit(1);
  }
  const result = await enrollUser(org, userId, userSecret);
  console.log(result);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
