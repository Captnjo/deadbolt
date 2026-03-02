const web3 = require("@solana/web3.js");
const axios = require("axios");
const bs58 = require("bs58");
const fs = require('fs').promises;
const hwSigner = require('./hw_signer');

const connection = new web3.Connection("https://mainnet.helius-rpc.com/?api-key=API");

function isHardwarePort(path) { return path.startsWith('/dev/'); }

async function sendTransactionJito(serializedTransaction) {
  const encodedTx = bs58.encode(serializedTransaction);
  const jitoURL = "https://mainnet.block-engine.jito.wtf/api/v1/transactions";
  const payload = {
    jsonrpc: "2.0",
    id: 1,
    method: "sendTransaction",
    params: [encodedTx],
  };

  try {
    const response = await axios.post(jitoURL, payload, {
      headers: { "Content-Type": "application/json" },
    });
    return response.data.result;
  } catch (error) {
    console.error("Error:", error);
    throw new Error("cannot send!");
  }
}

async function createPaymentTx(amountSol, destinationAddress, keypairPath) {
  const lamportsPerSol = web3.LAMPORTS_PER_SOL;
  const amountLamports = amountSol * lamportsPerSol;

  let fromPublicKey, signTransaction, cleanup;

  if (isHardwarePort(keypairPath)) {
    // Hardware signer mode
    const signer = await hwSigner.connect(keypairPath);
    fromPublicKey = new web3.PublicKey(signer.publicKeyBytes);
    signTransaction = async (tx) => {
      const msgBytes = tx.message.serialize();
      const sig = await signer.sign(msgBytes);
      tx.addSignature(fromPublicKey, sig);
    };
    cleanup = () => signer.close();
  } else {
    // File-based keypair mode
    const keypairData = await fs.readFile(keypairPath, { encoding: 'utf8' });
    const secretKey = Uint8Array.from(JSON.parse(keypairData));
    const fromAccount = web3.Keypair.fromSecretKey(secretKey);
    fromPublicKey = fromAccount.publicKey;
    signTransaction = async (tx) => { tx.sign([fromAccount]); };
    cleanup = () => {};
  }

  const toAccount = new web3.PublicKey(destinationAddress);

  const blockhash = await connection.getLatestBlockhash();

  const config = {
    units: 10000,
    microLamports: 100000,
  };
  const computePriceIx = web3.ComputeBudgetProgram.setComputeUnitPrice({
    microLamports: config.microLamports,
  });
  const computeLimitIx = web3.ComputeBudgetProgram.setComputeUnitLimit({
    units: config.units,
  });
  const instructions = [
    computePriceIx,
    computeLimitIx,
    web3.SystemProgram.transfer({
      fromPubkey: fromPublicKey,
      toPubkey: toAccount,
      lamports: amountLamports,
    }),
    web3.SystemProgram.transfer({
      fromPubkey: fromPublicKey,
      toPubkey: new web3.PublicKey("juLesoSmdTcRtzjCzYzRoHrnF8GhVu6KCV7uxq7nJGp"), // Deadbolt tip account
      lamports: 420_000, // tip
    }),
    web3.SystemProgram.transfer({
      fromPubkey: fromPublicKey,
      toPubkey: new web3.PublicKey("DttWaMuVvTiduZRnguLF7jNxTgiMBZ1hyAumKUiL2KRL"), // Jito tip account
      lamports: 420_000, // tip
    }),
  ];
  const messageV0 = new web3.TransactionMessage({
    payerKey: fromPublicKey,
    recentBlockhash: blockhash.blockhash,
    instructions,
  }).compileToV0Message();

  const transaction = new web3.VersionedTransaction(messageV0);
  await signTransaction(transaction);
  const rawTransaction = transaction.serialize();

  cleanup();
  const txid = await sendTransactionJito(rawTransaction);
  console.log(`${txid}`);
  return txid;
}

// Process command line arguments to include keypairPath
const args = process.argv.slice(2);
if (args.length < 3) {
  console.log("Usage: node hermes.js <amount in SOL> <destination address> <keypair path>");
  process.exit(1);
}

const amountSol = parseFloat(args[0]);
const destinationAddress = args[1];
const keypairPath = args[2];

// Validate amount and destination address
if (isNaN(amountSol) || amountSol <= 0) {
  console.error("Invalid amount. Please enter a positive number.");
  process.exit(1);
}

if (!web3.PublicKey.isOnCurve(destinationAddress)) {
  console.error("Invalid destination address.");
  process.exit(1);
}

// Run the function and catch any errors
createPaymentTx(amountSol, destinationAddress, keypairPath).catch(console.error);
