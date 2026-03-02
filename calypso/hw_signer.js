// hw_signer.js - Bridge between Node.js wallet scripts and ESP32 hardware signer
// Usage: const signer = require('./hw_signer');
//        const { publicKey, sign } = await signer.connect('/dev/cu.usbmodem101');

const { SerialPort } = require('serialport');
const { ReadlineParser } = require('@serialport/parser-readline');

const BAUD = 115200;
const RESPONSE_TIMEOUT = 5000;   // 5s for non-signing commands
const SIGN_TIMEOUT = 35000;      // 35s for signing (user has 30s on device)

function connect(portPath) {
  return new Promise((resolve, reject) => {
    const port = new SerialPort({ path: portPath, baudRate: BAUD });
    const parser = port.pipe(new ReadlineParser({ delimiter: '\n' }));

    let responseCallbacks = [];

    parser.on('data', (line) => {
      line = line.trim();
      // Only parse JSON lines
      if (!line.startsWith('{')) return;
      try {
        const msg = JSON.parse(line);
        // Pass to all waiting callbacks
        for (const cb of responseCallbacks) {
          cb(msg);
        }
      } catch (e) {
        // ignore non-JSON
      }
    });

    function sendCommand(cmd, timeout = RESPONSE_TIMEOUT) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          responseCallbacks = responseCallbacks.filter(c => c !== handler);
          reject(new Error(`Timeout waiting for response to ${JSON.stringify(cmd)}`));
        }, timeout);

        function handler(msg) {
          // For sign commands, wait for final "signed" or "error", skip "pending"
          if (cmd.cmd === 'sign' && msg.status === 'pending') {
            process.stderr.write(`[ESP32] ${msg.msg} (${msg.bytes} bytes) - press BOOT button...\n`);
            return; // keep waiting
          }
          clearTimeout(timer);
          responseCallbacks = responseCallbacks.filter(c => c !== handler);
          resolve(msg);
        }

        responseCallbacks.push(handler);
        port.write(JSON.stringify(cmd) + '\n');
      });
    }

    port.on('open', async () => {
      // Wait for device boot
      await new Promise(r => setTimeout(r, 1000));

      try {
        // Ping to verify connection
        const pong = await sendCommand({ cmd: 'ping' });
        if (pong.status !== 'ok') throw new Error('Ping failed');

        // Get public key
        const keyResp = await sendCommand({ cmd: 'pubkey' });
        if (keyResp.status !== 'ok') throw new Error('Failed to get pubkey');

        const pubkeyBytes = Buffer.from(keyResp.pubkey, 'hex');

        resolve({
          publicKeyBytes: pubkeyBytes,
          address: keyResp.address,

          // Sign arbitrary message bytes, returns 64-byte signature
          sign: async (messageBytes) => {
            const hexPayload = Buffer.from(messageBytes).toString('hex');
            const resp = await sendCommand(
              { cmd: 'sign', payload: hexPayload },
              SIGN_TIMEOUT
            );
            if (resp.status === 'signed') {
              return Buffer.from(resp.signature, 'hex');
            } else {
              throw new Error(`Signing failed: ${resp.msg || resp.status}`);
            }
          },

          close: () => {
            port.close();
          }
        });
      } catch (e) {
        port.close();
        reject(e);
      }
    });

    port.on('error', reject);
  });
}

module.exports = { connect };
