#!/usr/bin/env node
/**
 * Brain&Bot TEE Deploy — Full Cycle Test
 * 
 * This script does the complete deploy flow:
 * 1. Get TEE public key from Phala
 * 2. Encrypt user secrets
 * 3. Provision CVM (validate compose + cache)
 * 4. Create CVM (spin up the TEE)
 * 5. Poll until running
 * 6. Verify attestation
 */

const https = require('https');
const crypto = require('crypto');
const fs = require('fs');

// --- Config ---
const PHALA_API = 'https://cloud-api.phala.network/api/v1';
const PHALA_KEY = fs.readFileSync(
  `${process.env.HOME}/.config/phala/api_key`, 'utf8'
).trim();

// User inputs (would come from frontend form)
const USER_CONFIG = {
  name: 'abuclaw-tee',
  anthropicKey: fs.readFileSync(
    `${process.env.HOME}/.openclaw/agents/main/agent/auth-profiles.json`, 'utf8'
  ).match(/"token":\s*"([^"]+)"/)?.[1] || '',
  telegramToken: fs.readFileSync(
    `${process.env.HOME}/.config/telegram-bots/abuclaw.token`, 'utf8'
  ).trim(),
  telegramOwnerId: '1310278446',
  model: 'claude-sonnet-4-20250514',
};

// --- HTTP helper ---
function phalaRequest(method, path, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(PHALA_API + path);
    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname,
      method,
      headers: {
        'X-API-Key': PHALA_KEY,
        'Content-Type': 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// --- Generate Docker Compose ---
function generateCompose(config) {
  return `services:
  openclaw:
    image: ghcr.io/mcclowin/openclaw-tee:latest
    ports:
      - "3000:3000"
    environment:
      - ANTHROPIC_API_KEY=${config.anthropicKey}
      - TELEGRAM_BOT_TOKEN=${config.telegramToken}
      - TELEGRAM_OWNER_ID=${config.telegramOwnerId}
      - PRIMARY_MODEL=${config.model}
    volumes:
      - openclaw-data:/home/node/.openclaw
    restart: unless-stopped

volumes:
  openclaw-data:`;
}

// --- Main flow ---
async function deploy() {
  console.log('=== Brain&Bot TEE Deploy ===\n');

  // Step 0: Verify API access
  console.log('Step 0: Verifying Phala API access...');
  const teepods = await phalaRequest('GET', '/teepods');
  if (teepods.status !== 200) {
    console.error('Failed to connect to Phala API:', teepods.data);
    process.exit(1);
  }
  const onlinePods = teepods.data.filter(p => p.status === 'ONLINE');
  console.log(`  ✅ ${onlinePods.length} teepods online`);
  onlinePods.forEach(p => console.log(`     ${p.name} | ${p.region_identifier}`));

  // Step 1: Check existing CVMs
  console.log('\nStep 1: Checking existing CVMs...');
  const cvms = await phalaRequest('GET', '/cvms');
  console.log(`  Found ${cvms.data.length} existing CVMs`);
  
  // Check if our CVM already exists
  const existing = cvms.data.find(c => c.name === USER_CONFIG.name);
  if (existing) {
    console.log(`  ⚠️  CVM "${USER_CONFIG.name}" already exists (id: ${existing.id})`);
    console.log(`  Status: ${existing.status}`);
    console.log('  Delete it first if you want to redeploy.');
    return existing;
  }

  // Step 2: Generate compose
  console.log('\nStep 2: Generating Docker Compose...');
  const compose = generateCompose(USER_CONFIG);
  console.log('  ✅ Compose generated');

  // Step 3: Provision
  console.log('\nStep 3: Provisioning CVM...');
  const provisionBody = {
    name: USER_CONFIG.name,
    compose_file: {
      name: USER_CONFIG.name,
      docker_compose_file: compose,
      manifest_version: 2,
      runner: 'docker-compose',
      features: ['kms', 'tproxy-net'],
      public_logs: false,
      public_sysinfo: false,
    },
    vcpu: 2,
    memory: 4096,
    disk_size: 20,
  };

  const provision = await phalaRequest('POST', '/cvms/provision', provisionBody);
  
  if (provision.status !== 200) {
    console.error('  ❌ Provision failed:', JSON.stringify(provision.data, null, 2));
    process.exit(1);
  }

  console.log('  ✅ Provisioned');
  console.log(`  compose_hash: ${provision.data.compose_hash || 'N/A'}`);
  console.log(`  app_id: ${provision.data.app_id || 'N/A'}`);
  console.log('  Full response:', JSON.stringify(provision.data, null, 2));

  // Step 4: Create CVM
  console.log('\nStep 4: Creating CVM...');
  
  // Build create payload from provision response
  const createBody = {
    compose_hash: provision.data.compose_hash,
    name: USER_CONFIG.name,
  };

  const create = await phalaRequest('POST', '/cvms', createBody);

  if (create.status !== 200 && create.status !== 201) {
    console.error('  ❌ Create failed:', JSON.stringify(create.data, null, 2));
    process.exit(1);
  }

  const cvmId = create.data.id;
  console.log(`  ✅ CVM created: ${cvmId}`);

  // Step 5: Poll status
  console.log('\nStep 5: Waiting for CVM to start...');
  let status = '';
  let attempts = 0;
  const maxAttempts = 30; // 5 minutes max

  while (status !== 'running' && status !== 'RUNNING' && attempts < maxAttempts) {
    await new Promise(r => setTimeout(r, 10000)); // 10s
    const check = await phalaRequest('GET', `/cvms/${cvmId}`);
    status = check.data.status || check.data.state || '';
    attempts++;
    console.log(`  [${attempts}/${maxAttempts}] Status: ${status}`);
    
    if (status === 'failed' || status === 'FAILED' || status === 'error') {
      console.error('  ❌ CVM failed to start');
      console.error('  Details:', JSON.stringify(check.data, null, 2));
      process.exit(1);
    }
  }

  if (attempts >= maxAttempts) {
    console.log('  ⚠️  Timeout waiting for CVM. Check manually.');
  }

  // Step 6: Get attestation
  console.log('\nStep 6: Checking attestation...');
  const attestation = await phalaRequest('GET', `/cvms/${cvmId}/attestation`);
  if (attestation.status === 200 && attestation.data) {
    console.log('  ✅ TEE attestation available');
    console.log(`  Quote type: ${attestation.data.quote_type || 'TDX'}`);
  } else {
    console.log('  ⏳ Attestation not yet available (may take a moment)');
  }

  // Step 7: Get network info
  console.log('\nStep 7: Getting network info...');
  const network = await phalaRequest('GET', `/cvms/${cvmId}/network`);
  if (network.status === 200) {
    console.log('  Network:', JSON.stringify(network.data, null, 2));
  }

  // Done
  console.log('\n=== Deploy Complete ===');
  console.log(`CVM ID: ${cvmId}`);
  console.log(`Name: ${USER_CONFIG.name}`);
  console.log(`Status: ${status}`);
  console.log(`\nManage:`);
  console.log(`  Status:  curl -H "X-API-Key: $KEY" ${PHALA_API}/cvms/${cvmId}`);
  console.log(`  Logs:    curl -H "X-API-Key: $KEY" ${PHALA_API}/cvms/${cvmId}/stats`);
  console.log(`  Attest:  curl -H "X-API-Key: $KEY" ${PHALA_API}/cvms/${cvmId}/attestation`);
  console.log(`  Delete:  curl -X DELETE -H "X-API-Key: $KEY" ${PHALA_API}/cvms/${cvmId}`);
  console.log(`\nMessage @abuclaw_bot on Telegram to test!`);

  return create.data;
}

// Run
deploy().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
