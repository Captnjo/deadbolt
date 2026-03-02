const web3 = require("@solana/web3.js");
const axios = require("axios");
const bs58 = require("bs58");
const fs = require('fs').promises;
const splToken = require("@solana/spl-token");
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

async function createPaymentTx(amountToken, tokenMintAddress, tokenDecimals, destinationAddress, keypairPath) {
  const lamportsPerSol = web3.LAMPORTS_PER_SOL;

  let fromPublicKey, signTransaction, cleanup;

  if (isHardwarePort(keypairPath)) {
    const signer = await hwSigner.connect(keypairPath);
    fromPublicKey = new web3.PublicKey(signer.publicKeyBytes);
    signTransaction = async (tx) => {
      const msgBytes = tx.message.serialize();
      const sig = await signer.sign(msgBytes);
      tx.addSignature(fromPublicKey, sig);
    };
    cleanup = () => signer.close();
  } else {
    const keypairData = await fs.readFile(keypairPath, { encoding: 'utf8' });
    const secretKey = Uint8Array.from(JSON.parse(keypairData));
    const fromAccount = web3.Keypair.fromSecretKey(secretKey);
    fromPublicKey = fromAccount.publicKey;
    signTransaction = async (tx) => { tx.sign([fromAccount]); };
    cleanup = () => {};
  }

  const toAccount = new web3.PublicKey(destinationAddress);
  const blockhash = await connection.getLatestBlockhash();
  // Ensure amountToken and tokenDecimals are treated as integers
  amountToken = parseInt(amountToken, 10);
  tokenDecimals = parseInt(tokenDecimals, 10);
  // Determine units based on amountToken and tokenDecimals
  const computeUnits = (amountToken === 1 && tokenDecimals === 0) ? 39900 : 9900;
  const config = {
    compute: computeUnits,
    microLamports: 100000,
  };
  const computePriceIx = web3.ComputeBudgetProgram.setComputeUnitPrice({
    microLamports: config.microLamports,
  });
  const computeLimitIx = web3.ComputeBudgetProgram.setComputeUnitLimit({
    units: config.compute,
  });

  let instructions = [
    computePriceIx,
    computeLimitIx,
  ]

  // SPL Token transfer
  const tokenMint = new web3.PublicKey(tokenMintAddress);
  //Get the associated token accounts for sender and receiver
  const fromAssociatedTokenAccountPubkey = await splToken.getAssociatedTokenAddress(tokenMint, fromPublicKey);
  const toAssociatedTokenAccountPubkey = await splToken.getAssociatedTokenAddress(tokenMint,toAccount);

  // Check if the account already exists
  const accountInfo = await connection.getAccountInfo(toAssociatedTokenAccountPubkey);
  if (!accountInfo) {
    // The account does not exist, so create the instruction to initialize it
    instructions.push(
      splToken.createAssociatedTokenAccountInstruction(
        fromPublicKey, // Payer of the transaction
        toAssociatedTokenAccountPubkey,
        toAccount,
        tokenMint,
      ),
    );
  }

  const amount = amountToken * Math.pow(10, tokenDecimals);

  instructions.push(
    splToken.createTransferInstruction(
      fromAssociatedTokenAccountPubkey,
      toAssociatedTokenAccountPubkey,
      fromPublicKey,
      amount,
      [],
      splToken.TOKEN_PROGRAM_ID
    )
  );

  // Adding tipping and Jito here
  instructions.push(
    web3.SystemProgram.transfer({
      fromPubkey: fromPublicKey,
      toPubkey: new web3.PublicKey("juLesoSmdTcRtzjCzYzRoHrnF8GhVu6KCV7uxq7nJGp"), // Deadbolt tip account
      lamports: 210_000, // tip
    }),
    web3.SystemProgram.transfer({
      fromPubkey: fromPublicKey,
      toPubkey: new web3.PublicKey("DttWaMuVvTiduZRnguLF7jNxTgiMBZ1hyAumKUiL2KRL"), // Jito tip account
      lamports: 210_000, // tip
    }),
  );

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

// Assuming the command line arguments are in the order:
// <amountToken> <tokenMintAddress> <destinationAddress> <keypairPath>
const args = process.argv.slice(2);
if (args.length < 5) {
  console.log("Usage: node scriptName.js <amountToken> <tokenMintAddress> <tokenDecimals> <destinationAddress> <keypairPath>");
  process.exit(1);
}

const amountToken = parseFloat(args[0]);
const tokenMintAddress = args[1];
const tokenDecimals = args[2];
const destinationAddress = args[3];
const keypairPath = args[4];

// Validate amountToken
if (isNaN(amountToken) || amountToken <= 0) {
  console.error("Invalid token amount. Please enter a positive number.");
  process.exit(1);
}

// Validate tokenMintAddress
if (!web3.PublicKey.isOnCurve(tokenMintAddress)) {
  console.error("Invalid token mint address.");
  process.exit(1);
}

// Validate destinationAddress
if (!web3.PublicKey.isOnCurve(destinationAddress)) {
  console.error("Invalid destination address.");
  process.exit(1);
}

// Run the function and catch any errors
createPaymentTx(amountToken, tokenMintAddress, tokenDecimals, destinationAddress, keypairPath).catch(console.error);

