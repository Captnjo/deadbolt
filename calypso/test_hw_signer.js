#!/usr/bin/env node
// Quick test for ESP32 hardware signer
// Usage: node test_hw_signer.js [port]
// Default port: /dev/cu.usbmodem101

const hwSigner = require('./hw_signer');
const port = process.argv[2] || '/dev/cu.usbmodem101';

(async () => {
  try {
    console.log(`Connecting to ESP32 on ${port}...`);
    const signer = await hwSigner.connect(port);
    console.log('Connected!');
    console.log('  Address:', signer.address);
    console.log('  Pubkey:', signer.publicKeyBytes.toString('hex'));

    console.log('\nSending test message to sign (32 bytes)...');
    console.log('>>> PRESS THE BOOT BUTTON on your ESP32 <<<');
    console.log('    (LED will pulse - you have 30 seconds)\n');

    const testMsg = Buffer.alloc(32, 0xAB);
    const sig = await signer.sign(testMsg);

    console.log('Signature received! (' + sig.length + ' bytes)');
    console.log('Sig:', sig.toString('hex'));
    console.log('\nHardware signer is WORKING!');

    signer.close();
  } catch (e) {
    console.error('\nFailed:', e.message);
    if (e.message.includes('rejected')) {
      console.error('You need to press the BOOT button within 30 seconds.');
    }
  }
  process.exit(0);
})();
