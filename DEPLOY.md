# Deployment plan — Cat Network (NOT executed yet)

Status 2026-11-18 ~20:15 WIB: contracts compiled + tested, gas measured,
**deployment NOT executed**. Waiting for Deni's go-ahead.

## Exact cost (measured from real deployment receipts on local anvil)

Live BSC gas price: **0.05 gwei** (bsc-dataseed.binance.org and
bsc.publicnode.com agree, 2026-11-18). Agent wallet
`0x94b08cb0454DbA9aFAE5A6DF947918EeAF2D1d16` holds **0.0005985787 BNB**,
nonce 207.

| Step | gas | cost @ 0.05 gwei |
|---|---|---|
| 1. Deploy CatToken | 964,411 | 0.0000482206 BNB |
| 2. Deploy CatNFT | 4,230,274 | 0.0002115137 BNB |
| 3. Transfer 300M CAT → CatNFT | 52,495 | 0.0000026248 BNB |
| **Phase 1 total** | **5,247,180** | **0.0002623590 BNB** |
| 4. Deploy GameBridge | 1,423,498 | 0.0000711749 BNB |
| 5. Deploy CatVesting | 590,584 | 0.0000295292 BNB |
| 6. Transfers 500M → Bridge, 100M → Vesting | 105,002 | 0.0000052501 BNB |
| **Full total (all four)** | **7,366,264** | **0.0003683132 BNB** |

At 1 gwei: phase 1 = 0.0052471800 BNB, full = 0.0073662640 BNB — both far
above the wallet. **Deploy only while gas is ~0.05 gwei.**
Breakeven gas price vs the wallet: phase 1 = 0.114 gwei, full = 0.081 gwei.

Headroom after deploy at 0.05 gwei: 0.0003362197 BNB (phase 1) or
0.0002302655 BNB (full) — enough for the post-deploy admin txs
(`setMerkleRoot`, `setWlActive`, `setBaseURI`, ~200k gas ≈ 0.00001 BNB).

Recommendation: deploy **FULL (all four)** in one run. It costs
0.0003683132 BNB, fits the wallet with headroom, and avoids a second
deployment round later (bridge + vesting would cost another ~2.1M gas
then, at whatever gas price applies).

## BLOCKER — baw cannot deploy contracts

Checked 2026-11-18: `baw --help` has no deploy subcommand, and
`baw contract-call preview` requires `--to` (an existing contract).
The agent wallet therefore has **no deployment path through baw**,
even though it holds the 0.0006 BNB gas money.

Deployment must be done from a wallet with a usable private key:

- **Option A (recommended): Deni's MetaMask deployer wallet.**
  Run the forge script from this repo (see below). Gas is paid from
  MetaMask, NOT from the agent wallet — the agent wallet's 0.0006 BNB
  then stays untouched. Deployer becomes the MetaMask address (owner of
  all contracts, LP-seed holder, team/founder placeholder).
- **Option B:** if a deployment route for the agent wallet is arranged
  later, the deployer is the agent wallet (nonce 207) and gas comes from
  its 0.0005985787 BNB. The script already defaults every role to the
  deployer.

Either way, confirm before deploying:
1. Real team wallet address (or accept deployer = team = founder).
2. Game-server signer key for GameBridge (or accept deployer, rotate later
   with `setSigner`).
3. Gas price is ~0.05 gwei at deploy time (re-check `eth_gasPrice`).

## Deploy commands (MetaMask / forge route)

```bash
cd ~/workspace/goals/cat-network-nft-and-token-project/hidden_files/hackathon-contracts
export PATH="$HOME/.foundry/bin:$PATH"
# dry-run simulation against BSC mainnet state (no broadcast, no spend):
FULL=true forge script script/Deploy.s.sol --fork-url bsc
# real deploy (FULL=true = all four contracts):
FULL=true forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.binance.org \
  --private-key <DEPLOYER_KEY> --broadcast --gas-price 50000000
# ^ gas-price 50000000 wei = 0.05 gwei. Do NOT deploy above ~0.08 gwei.
```

Env overrides (all default to the deployer):
`TEAM_WALLET`, `FOUNDER_WALLET`, `LP_WALLET`, `GAME_SIGNER`.

## After deployment (before the hackathon form can be submitted)

1. Record the four contract addresses + tx hashes (they do not exist yet —
   do not invent them).
2. Verify source on BscScan for all four (required: verified + open source).
   Compiler: solc bundled with forge 1.9.0, optimizer on, 200 runs
   (foundry defaults); constructor args from the deploy log.
3. Post-deploy admin txs (owner = deployer): `setBaseURI` (after the IPFS
   metadata upload), `setMerkleRoot` (after WL wallets are collected),
   `setWlActive(true)` when the mint opens.
4. Wire the addresses into `~/workspace/cat-network-site-v2/` mint page.
5. Submit the hackathon form (see FORM-ANSWERS.md) with the BscScan links.

## What still blocks the mint itself (not the deployment)

- WL wallets: registrations hold X handles only. The site needs a
  wallet-collection step before a merkle root can be built.
- NFT metadata: images + JSON not created; IPFS upload + `setBaseURI` needed
  before marketplaces show art.
- ≥30 Agent ID addresses must interact during the submission period
  (Innovation Award eligibility) — needs real users minting.
