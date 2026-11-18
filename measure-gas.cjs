// Deploy all contracts to a local anvil (fork or not) and print exact gasUsed.
// Usage: node measure-gas.cjs [full]
// Reads artifacts from ./out/*.sol/*.json
const { ethers } = require('/home/hatch/workspace/flaggies-tools/node_modules/ethers');
const fs = require('node:fs');

const RPC = 'http://127.0.0.1:8545';
const PK = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'; // anvil account 0 (from anvil startup log)
const full = process.argv[2] === 'full';

function artifact(name) {
  const p = `./out/${name}.sol/${name}.json`;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

const provider = new ethers.JsonRpcProvider(RPC);
const wallet = new ethers.Wallet(PK, provider);
console.log('deployer:', wallet.address);

let nonce = null;
async function nextNonce() {
  if (nonce === null) nonce = await wallet.getNonce();
  return nonce++;
}

async function deploy(name, args, label) {
  const art = artifact(name);
  const factory = new ethers.ContractFactory(art.abi, art.bytecode, wallet);
  const contract = await factory.deploy(...args, { nonce: await nextNonce() });
  const receipt = await contract.deploymentTransaction().wait();
  console.log(`${label}: ${contract.target} gasUsed=${receipt.gasUsed}`);
  return { contract, gasUsed: receipt.gasUsed };
}

async function send(label, txPromise) {
  const tx = await txPromise;
  const receipt = await tx.wait();
  console.log(`${label}: gasUsed=${receipt.gasUsed}`);
  return receipt.gasUsed;
}

(async () => {
let total = 0n;
const cat = await deploy('CatToken', [], 'CatToken');
total += cat.gasUsed;

const nft = await deploy('CatNFT', [cat.contract.target, wallet.address, wallet.address], 'CatNFT');
total += nft.gasUsed;

// phase-1 distribution: 300M CAT -> NFT
let g = await send('transfer 300M CAT -> NFT', cat.contract.transfer(nft.contract.target, ethers.parseEther('300000000'), { nonce: await nextNonce() }));
total += g;
console.log(`PHASE1 TOTAL gas=${total}`);

if (full) {
  const bridge = await deploy('GameBridge', [cat.contract.target, wallet.address], 'GameBridge');
  total += bridge.gasUsed;
  const vesting = await deploy('CatVesting', [cat.contract.target, wallet.address, wallet.address], 'CatVesting');
  total += vesting.gasUsed;
  g = await send('transfer 500M CAT -> Bridge', cat.contract.transfer(bridge.contract.target, ethers.parseEther('500000000'), { nonce: await nextNonce() }));
  total += g;
  g = await send('transfer 100M CAT -> Vesting', cat.contract.transfer(vesting.contract.target, ethers.parseEther('100000000'), { nonce: await nextNonce() }));
  total += g;
  console.log(`FULL TOTAL gas=${total}`);
}

// sanity: balances
console.log('NFT CAT balance:', ethers.formatEther(await cat.contract.balanceOf(nft.contract.target)));
console.log('deployer CAT balance:', ethers.formatEther(await cat.contract.balanceOf(wallet.address)));
console.log('totalSupply:', ethers.formatEther(await cat.contract.totalSupply()));
})().catch(e => { console.error(e); process.exit(1); });
