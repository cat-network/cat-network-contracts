# Cat Network — Hackathon Contracts

Binance Agent ID Hackathon, project awards entry. Contracts written, compiled
and tested 2026-11-18. **NOT deployed to mainnet yet.**

## Files

| File | What it is |
|---|---|
| `src/CatToken.sol` | $CAT ERC-20, 1B fixed supply, minimal hand-rolled (lean for gas) |
| `src/CatNFT.sol` | 5,555 NFT, Agent-ID gated WL + public mint, holder rewards, community pools |
| `src/GameBridge.sol` | 500M $CAT mining rewards, EIP-712 signed 1:1 game claims |
| `src/CatVesting.sol` | 100M $CAT team 30M + founder 70M, 12-mo cliff, 12 monthly releases |
| `script/Deploy.s.sol` | Deploy + distribute script (`FULL=true` deploys all four) |
| `test/CatNetwork.t.sol` | 22 tests, all passing on a BSC mainnet fork |
| `measure-gas.cjs` | Reproduces the exact deployment-gas measurement on local anvil |
| `DEPLOY.md` | Deployment plan, exact costs, and the deploy blocker |
| `FORM-ANSWERS.md` | Hackathon form answers ready to paste |

## Whitepaper alignment (whitepaper v1.0 wins over memory)

- NFT 5,555: WL 1,000 FREE (gas only) + 1,000 $CAT each; public 4,555 at
  0.01 BNB + 1,000 $CAT each. Every mint burns 1,000 $CAT.
- WL airdrop 10,000 $CAT per WL mint (9,000 to minter, 1,000 burned).
- $CAT 1B: mining 500M, NFT rewards 200M, LP 100M, community 100M
  (WL airdrop 10M / community rewards 60M / referral 20M / reserve 10M),
  team 30M, founder 70M.
- Mint revenue ~45.55 BNB splits 50/50 LP wallet / founder on `withdraw()`.
- Holder rewards: 200M / 5,555 = **36,003 $CAT per NFT**, one claim each.
  Remainder 3,335 $CAT stays locked in the NFT contract.

## Agent ID integration (hackathon requirement)

- Every mint requires owning an Agent ID (SPACE ID registry
  `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`).
- Each Agent ID claims ONE free WL mint (`usedAgentId` mapping).
- Public mints also require Agent ID ownership, so every minter is a
  verified on-chain identity (this is an addition for the hackathon;
  the whitepaper does not mention Agent ID).

## Tests — 22/22 pass (`forge test --fork-url bsc`)

- Token: supply/distribution, ERC-20 transfer/approve/transferFrom/burn.
- Real Agent ID on the fork: registry `ownerOf(keccak256("kdeni3256"))` is
  the agent wallet `0x94b08cb0454DbA9aFAE5A6DF947918EeAF2D1d16`.
- WL mint: airdrop/burn math (+9,000 / −1,000), double-mint reverts,
  non-WL reverts, non-Agent-ID reverts, inactive-phase reverts.
- Public mint: price, Agent ID, approval, burn math.
- Rewards: claim once, non-owner reverts, double-claim reverts.
- Withdraw 50/50 split, community pool caps.
- GameBridge: valid claim, replay reverts, wrong signer reverts.
- Vesting: cliff blocks release, 6 months = half, 24 months = full.
- Reentrancy: attacker code etched onto the real Agent address proves the
  `onERC721Received` callback cannot double-mint (no ReentrancyGuard by
  design; checks-effects-interactions only).

## Gas — measured from real deployment receipts on local anvil

| Item | gas |
|---|---|
| CatToken deploy | 964,411 |
| CatNFT deploy | 4,230,274 |
| transfer 300M CAT → NFT | 52,495 |
| **Phase 1 total** | **5,247,180** |
| GameBridge deploy | 1,423,498 |
| CatVesting deploy | 590,584 |
| transfers 500M + 100M | 105,002 |
| **Full total (4 contracts)** | **7,366,264** |

Live BSC gas price 2026-11-18: **0.05 gwei** (both RPCs agree).
Agent wallet: **0.0005985787 BNB**, nonce 207.

| | @ 0.05 gwei | @ 1 gwei |
|---|---|---|
| Phase 1 (token + NFT) | **0.0002623590 BNB** | 0.0052471800 BNB |
| Full (all four) | **0.0003683132 BNB** | 0.0073662640 BNB |

Wallet headroom at 0.05 gwei: 0.0003362197 BNB after phase 1,
0.0002302655 BNB after full. Breakeven gas price: phase 1 = 0.114 gwei,
full = 0.081 gwei. At 0.1 gwei the full deploy exceeds the wallet by
0.0001380477 BNB — deploy only while gas is ~0.05 gwei.

## Assumptions / open points (decisions Deni must confirm before mainnet)

1. **Team wallet = founder wallet = deployer** by default. Confirm a real
   separate team wallet before mainnet, or accept the deployer for both.
2. **Game signer = deployer** by default. Must be rotated to the game
   server key via `setSigner` before game claims go live.
3. Vesting = 12-month cliff + **12 monthly releases** (whitepaper says
   "equal monthly parts" without a count; 12 assumed).
4. **WL has no wallet addresses** — registrations hold X handles only.
   The site needs a wallet-collection step before a merkle root can be
   built and WL mint opened.
5. NFT metadata (images + JSON) not created yet; `baseURI` is empty until
   the IPFS upload. Minting works without it, marketplaces show no art.
6. Innovation Award needs ≥30 Agent ID addresses interacting during the
   submission period — that depends on real users, contracts can't fake it.
7. **baw cannot deploy contracts** (see DEPLOY.md). Deployment needs a
   wallet with a usable private key — Deni's MetaMask deployer wallet.

## Build / test / measure

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test --fork-url bsc
# gas measurement (needs local anvil on :8545):
anvil --port 8545
node measure-gas.cjs full
```
