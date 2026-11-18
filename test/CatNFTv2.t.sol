// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CatToken} from "../src/CatToken.sol";
import {CatNFTv2} from "../src/CatNFTv2.sol";

/// @notice v2 (2026-11-19): public mint is open to EVERY wallet, no Agent ID.
/// Proves a stranger with no Agent ID can mint, and claimReward still pays.
contract CatNFTv2Test is Test {
    CatToken public cat;
    CatNFTv2 public nft;

    address public stranger = address(0x3333);

    function setUp() public {
        vm.createSelectFork("bsc");
        cat = new CatToken();
        nft = new CatNFTv2(cat, address(this), address(this));
        // Fund the NFT contract with 100M CAT for holder rewards (Deni's
        // regular wallet holds 100M; the v1 contract keeps its own 300M).
        require(cat.transfer(address(nft), 100_000_000 ether));
        nft.setPublicActive(true);
        vm.deal(stranger, 1 ether);
    }

    function testStrangerWithNoAgentIdCanMint() public {
        // Stranger owns no Agent ID at all.
        require(cat.balanceOf(stranger) == 0);
        require(cat.transfer(stranger, 1_000 ether));
        vm.startPrank(stranger);
        cat.approve(address(nft), 1_000 ether);
        nft.mintPublic{value: 0.01 ether}();
        vm.stopPrank();

        assertEq(nft.ownerOf(1), stranger);
        assertEq(nft.publicMinted(), 1);
        // 1,000 CAT burned from the minter.
        assertEq(cat.balanceOf(stranger), 0);
    }

    function testClaimRewardPays36003() public {
        require(cat.transfer(stranger, 1_000 ether));
        vm.startPrank(stranger);
        cat.approve(address(nft), 1_000 ether);
        nft.mintPublic{value: 0.01 ether}();
        nft.claimReward(1);
        vm.stopPrank();
        assertEq(cat.balanceOf(stranger), 36_003 ether);
    }

    function testWrongPaymentReverts() public {
        require(cat.transfer(stranger, 1_000 ether));
        vm.startPrank(stranger);
        cat.approve(address(nft), 1_000 ether);
        vm.expectRevert(CatNFTv2.WrongPayment.selector);
        nft.mintPublic{value: 0.005 ether}();
        vm.stopPrank();
    }

    function testNoCatApprovalReverts() public {
        // Stranger holds 1,000 CAT but never approved: burnFrom must fail.
        require(cat.transfer(stranger, 1_000 ether));
        vm.startPrank(stranger);
        vm.expectRevert();
        nft.mintPublic{value: 0.01 ether}();
        vm.stopPrank();
    }
}
