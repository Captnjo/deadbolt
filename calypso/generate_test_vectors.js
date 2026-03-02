#!/usr/bin/env node
/**
 * Generate transaction serialization test vectors for Swift byte-compatibility testing.
 * Uses the same @solana/web3.js that the CLI uses.
 *
 * Outputs JSON with hex-encoded bytes for each test case.
 */
const web3 = require("@solana/web3.js");

// Deterministic keypair from a known seed (32 bytes of 0x01)
const seed = Buffer.alloc(32, 0x01);
const feePayer = web3.Keypair.fromSeed(seed);

// Deterministic recipient (32 bytes of 0x02)
const recipientBytes = Buffer.alloc(32, 0x02);
const recipient = new web3.PublicKey(recipientBytes);

// Deterministic blockhash (32 bytes of 0xAA, encoded as Base58)
const blockhashBytes = Buffer.alloc(32, 0xAA);
const bs58 = require("bs58");
const blockhash = bs58.encode(blockhashBytes);

console.log("=== Test Vector Metadata ===");
console.log("Fee payer pubkey:", feePayer.publicKey.toBase58());
console.log("Fee payer pubkey hex:", Buffer.from(feePayer.publicKey.toBytes()).toString("hex"));
console.log("Recipient hex:", recipientBytes.toString("hex"));
console.log("Blockhash:", blockhash);
console.log("");

// --- Vector 1: Simple SOL transfer ---
{
  const tx = new web3.Transaction();
  tx.recentBlockhash = blockhash;
  tx.feePayer = feePayer.publicKey;
  tx.add(
    web3.SystemProgram.transfer({
      fromPubkey: feePayer.publicKey,
      toPubkey: recipient,
      lamports: 1_000_000,
    })
  );
  tx.sign(feePayer);
  const serialized = tx.serialize();

  console.log("=== Vector 1: Simple SOL Transfer (1_000_000 lamports) ===");
  console.log("Full tx hex:", serialized.toString("hex"));
  console.log("Full tx length:", serialized.length);

  // Also output just the message (unsigned) for message-level comparison
  const msg = tx.serializeMessage();
  console.log("Message hex:", msg.toString("hex"));
  console.log("Message length:", msg.length);
  console.log("Signature hex:", Buffer.from(tx.signature).toString("hex"));
  console.log("");
}

// --- Vector 2: SOL transfer + ComputeBudget (limit + price) ---
{
  const tx = new web3.Transaction();
  tx.recentBlockhash = blockhash;
  tx.feePayer = feePayer.publicKey;
  tx.add(
    web3.ComputeBudgetProgram.setComputeUnitLimit({ units: 200_000 }),
    web3.ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 50_000 }),
    web3.SystemProgram.transfer({
      fromPubkey: feePayer.publicKey,
      toPubkey: recipient,
      lamports: 1_000_000,
    })
  );
  tx.sign(feePayer);
  const serialized = tx.serialize();

  console.log("=== Vector 2: SOL Transfer + ComputeBudget ===");
  console.log("Full tx hex:", serialized.toString("hex"));
  console.log("Full tx length:", serialized.length);
  const msg = tx.serializeMessage();
  console.log("Message hex:", msg.toString("hex"));
  console.log("Message length:", msg.length);
  console.log("");
}

// --- Vector 3: SOL transfer + ComputeBudget + Jito tip ---
{
  const tipAccount = new web3.PublicKey("96gYZGLnJYVFmbjzopPSU6QiEV5fGqZNyN9nmNhvrZU5");

  const tx = new web3.Transaction();
  tx.recentBlockhash = blockhash;
  tx.feePayer = feePayer.publicKey;
  tx.add(
    web3.ComputeBudgetProgram.setComputeUnitLimit({ units: 200_000 }),
    web3.ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 50_000 }),
    web3.SystemProgram.transfer({
      fromPubkey: feePayer.publicKey,
      toPubkey: recipient,
      lamports: 1_000_000,
    }),
    web3.SystemProgram.transfer({
      fromPubkey: feePayer.publicKey,
      toPubkey: tipAccount,
      lamports: 840_000,
    })
  );
  tx.sign(feePayer);
  const serialized = tx.serialize();

  console.log("=== Vector 3: SOL Transfer + ComputeBudget + Jito Tip ===");
  console.log("Tip account:", tipAccount.toBase58());
  console.log("Full tx hex:", serialized.toString("hex"));
  console.log("Full tx length:", serialized.length);
  const msg = tx.serializeMessage();
  console.log("Message hex:", msg.toString("hex"));
  console.log("Message length:", msg.length);
  console.log("");
}

// --- Output as JSON for easy parsing ---
{
  const vectors = [];

  // Vector 1
  {
    const tx = new web3.Transaction();
    tx.recentBlockhash = blockhash;
    tx.feePayer = feePayer.publicKey;
    tx.add(web3.SystemProgram.transfer({ fromPubkey: feePayer.publicKey, toPubkey: recipient, lamports: 1_000_000 }));
    tx.sign(feePayer);
    vectors.push({
      name: "simple_sol_transfer",
      message_hex: tx.serializeMessage().toString("hex"),
      tx_hex: tx.serialize().toString("hex"),
    });
  }

  // Vector 2
  {
    const tx = new web3.Transaction();
    tx.recentBlockhash = blockhash;
    tx.feePayer = feePayer.publicKey;
    tx.add(
      web3.ComputeBudgetProgram.setComputeUnitLimit({ units: 200_000 }),
      web3.ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 50_000 }),
      web3.SystemProgram.transfer({ fromPubkey: feePayer.publicKey, toPubkey: recipient, lamports: 1_000_000 })
    );
    tx.sign(feePayer);
    vectors.push({
      name: "sol_transfer_with_compute_budget",
      message_hex: tx.serializeMessage().toString("hex"),
      tx_hex: tx.serialize().toString("hex"),
    });
  }

  // Vector 3
  {
    const tipAccount = new web3.PublicKey("96gYZGLnJYVFmbjzopPSU6QiEV5fGqZNyN9nmNhvrZU5");
    const tx = new web3.Transaction();
    tx.recentBlockhash = blockhash;
    tx.feePayer = feePayer.publicKey;
    tx.add(
      web3.ComputeBudgetProgram.setComputeUnitLimit({ units: 200_000 }),
      web3.ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 50_000 }),
      web3.SystemProgram.transfer({ fromPubkey: feePayer.publicKey, toPubkey: recipient, lamports: 1_000_000 }),
      web3.SystemProgram.transfer({ fromPubkey: feePayer.publicKey, toPubkey: tipAccount, lamports: 840_000 })
    );
    tx.sign(feePayer);
    vectors.push({
      name: "sol_transfer_with_compute_budget_and_tip",
      message_hex: tx.serializeMessage().toString("hex"),
      tx_hex: tx.serialize().toString("hex"),
    });
  }

  console.log("=== JSON VECTORS ===");
  console.log(JSON.stringify({
    fee_payer_seed_hex: seed.toString("hex"),
    fee_payer_pubkey: feePayer.publicKey.toBase58(),
    fee_payer_pubkey_hex: Buffer.from(feePayer.publicKey.toBytes()).toString("hex"),
    recipient_hex: recipientBytes.toString("hex"),
    blockhash,
    blockhash_hex: blockhashBytes.toString("hex"),
    vectors,
  }, null, 2));
}
