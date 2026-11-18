// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CatToken} from "../src/CatToken.sol";
import {GameBridge} from "../src/GameBridge.sol";
import {CatVesting} from "../src/CatVesting.sol";
import {CatNFT} from "../src/CatNFT.sol";

/// @notice Deploys the Cat Network system and distributes the 1B $CAT.
/// NEVER run with --broadcast on mainnet until Deni funds the deployer wallet.
/// Dry-run on a fork first: forge script script/Deploy.s.sol --fork-url <bsc rpc>
/// @dev Phase 1 (hackathon entry, must fit the ~0.0003 BNB budget): CatToken
/// + CatNFT only. Phase 2 (after the wallet is funded): GameBridge + CatVesting.
/// Run with FULL=true to deploy everything at once.
/// Wallets are read from env (TEAM_WALLET, FOUNDER_WALLET, LP_WALLET,
/// GAME_SIGNER) and default to the deployer when unset. BEFORE mainnet deploy,
/// Deni must confirm the real team wallet and the game-server signer key.
/// Until then every role points at the deployer (the agent wallet).
contract Deploy is Script {
    function run() external {
        bool full = vm.envOr("FULL", false);
        address deployer = msg.sender;
        address team = vm.envOr("TEAM_WALLET", deployer);
        address founder = vm.envOr("FOUNDER_WALLET", deployer);
        address lp = vm.envOr("LP_WALLET", deployer);
        address gameSigner = vm.envOr("GAME_SIGNER", deployer);

        vm.startBroadcast();

        CatToken cat = new CatToken();
        console.log("CatToken:", address(cat));

        CatNFT nft = new CatNFT(cat, lp, founder);
        console.log("CatNFT:", address(nft));

        // Phase 1 distribution: 300M to the NFT contract (200M holder rewards
        // + 100M community pools), deployer keeps 700M until phase 2.
        require(cat.transfer(address(nft), 300_000_000 ether), "nft");

        if (full) {
            GameBridge bridge = new GameBridge(IERC20(address(cat)), gameSigner);
            console.log("GameBridge:", address(bridge));

            CatVesting vesting = new CatVesting(IERC20(address(cat)), team, founder);
            console.log("CatVesting:", address(vesting));

            require(cat.transfer(address(bridge), 500_000_000 ether), "bridge");
            require(cat.transfer(address(vesting), 100_000_000 ether), "vesting");
            require(cat.balanceOf(deployer) == 100_000_000 ether, "owner lp share");
        } else {
            require(cat.balanceOf(deployer) == 700_000_000 ether, "owner phase1");
        }

        vm.stopBroadcast();

        console.log("--- allocation check ---");
        console.log("nft (rewards+community):", cat.balanceOf(address(nft)) / 1 ether, "M");
        console.log("owner:", cat.balanceOf(deployer) / 1 ether, "M");
        console.log("totalSupply:", cat.totalSupply() / 1 ether, "M");
    }
}
