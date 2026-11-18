// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {CatToken} from "../src/CatToken.sol";
import {CatNFT} from "../src/CatNFT.sol";
import {GameBridge} from "../src/GameBridge.sol";
import {CatVesting} from "../src/CatVesting.sol";

/// @notice Attacker contract used to prove the no-ReentrancyGuard design is
/// safe: it tries to re-enter mintWL from the onERC721Received callback
/// that _safeMint triggers. State is already updated, so it must fail.
contract ReenterAttacker {
    CatNFT public nft;
    bytes32[] public proof;
    uint256 public agentId;
    bool public reentered;
    bool public reentrySucceeded;

    constructor(CatNFT _nft) {
        nft = _nft;
    }

    function setProof(bytes32[] calldata _proof, uint256 _agentId) external {
        proof = _proof;
        agentId = _agentId;
    }

    function attack() external {
        nft.mintWL(proof, agentId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (!reentered) {
            reentered = true;
            try nft.mintWL(proof, agentId) {
                reentrySucceeded = true;
            } catch {}
        }
        return this.onERC721Received.selector;
    }
}

contract CatNetworkTest is Test {
    CatToken public cat;
    CatNFT public nft;
    GameBridge public bridge;
    CatVesting public vesting;

    address public constant AGENT = 0x94b08cb0454DbA9aFAE5A6DF947918EeAF2D1d16;
    uint256 public constant AGENT_ID =
        0x28cc79ba525c0b18bc364165d5b00eb378302c11d11e3bc2aaf84a4dafaf234a; // keccak256("kdeni3256")

    address public user2 = address(0x2222);
    address public stranger = address(0x3333);

    uint256 public signerPk = 0xA11CE;
    address public signer;

    bytes32 public merkleRoot;
    bytes32[] public agentProof;
    bytes32[] public user2Proof;

    function setUp() public {
        vm.createSelectFork("bsc");
        signer = vm.addr(signerPk);

        cat = new CatToken();
        nft = new CatNFT(cat, address(this), address(this));
        bridge = new GameBridge(IERC20(address(cat)), signer);
        vesting = new CatVesting(IERC20(address(cat)), address(this), address(this));

        // Distribute exactly per whitepaper section 5.
        require(cat.transfer(address(nft), 300_000_000 ether));
        require(cat.transfer(address(bridge), 500_000_000 ether));
        require(cat.transfer(address(vesting), 100_000_000 ether));
        // this contract keeps 100M (LP seed).

        // 2-leaf whitelist: AGENT + user2.
        bytes32 leafAgent = keccak256(abi.encodePacked(AGENT));
        bytes32 leafUser2 = keccak256(abi.encodePacked(user2));
        merkleRoot = leafAgent < leafUser2
            ? keccak256(abi.encodePacked(leafAgent, leafUser2))
            : keccak256(abi.encodePacked(leafUser2, leafAgent));
        agentProof.push(leafUser2);
        user2Proof.push(leafAgent);
        nft.setMerkleRoot(merkleRoot);
        nft.setWlActive(true);
        nft.setPublicActive(true);

        vm.deal(AGENT, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    // ---- token ----

    function testTokenSupplyAndDistribution() public view {
        assertEq(cat.totalSupply(), 1_000_000_000 ether);
        assertEq(cat.balanceOf(address(nft)), 300_000_000 ether);
        assertEq(cat.balanceOf(address(bridge)), 500_000_000 ether);
        assertEq(cat.balanceOf(address(vesting)), 100_000_000 ether);
        assertEq(cat.balanceOf(address(this)), 100_000_000 ether);
    }

    function testTokenERC20Basics() public {
        assertEq(cat.name(), "Cat Network");
        assertEq(cat.symbol(), "CAT");
        assertEq(cat.decimals(), 18);

        // transfer
        assertTrue(cat.transfer(user2, 100 ether));
        assertEq(cat.balanceOf(user2), 100 ether);
        // approve + transferFrom
        vm.prank(user2);
        assertTrue(cat.approve(address(this), 40 ether));
        assertTrue(cat.transferFrom(user2, stranger, 40 ether));
        assertEq(cat.balanceOf(stranger), 40 ether);
        // burn / burnFrom
        vm.prank(user2);
        cat.burn(10 ether);
        assertEq(cat.balanceOf(user2), 50 ether);
        vm.prank(user2);
        cat.approve(address(this), 5 ether);
        cat.burnFrom(user2, 5 ether);
        assertEq(cat.balanceOf(user2), 45 ether);
        // reverts
        vm.prank(user2);
        vm.expectRevert(CatToken.InsufficientBalance.selector);
        cat.transfer(stranger, 1_000_000 ether);
        vm.prank(user2);
        vm.expectRevert(CatToken.InsufficientAllowance.selector);
        cat.transferFrom(stranger, user2, 1 ether);
    }

    // ---- Agent ID (real registry on the fork) ----

    function testAgentIdOwnershipOnFork() public view {
        IERC721 registry = IERC721(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
        assertEq(registry.ownerOf(AGENT_ID), AGENT);
    }

    // ---- WL mint ----

    function testMintWL() public {
        uint256 supplyBefore = cat.totalSupply();
        vm.prank(AGENT);
        nft.mintWL(agentProof, AGENT_ID);

        assertEq(nft.ownerOf(1), AGENT);
        assertEq(nft.wlMinted(), 1);
        assertTrue(nft.usedAgentId(AGENT_ID));
        assertEq(cat.balanceOf(AGENT), 9_000 ether); // 10,000 airdrop - 1,000 mint cost
        assertEq(cat.totalSupply(), supplyBefore - 1_000 ether); // 1,000 burned
        assertEq(nft.wlSpent(), 10_000 ether);
    }

    function testMintWLTwiceSameAgentIdReverts() public {
        vm.prank(AGENT);
        nft.mintWL(agentProof, AGENT_ID);
        vm.prank(AGENT);
        vm.expectRevert(CatNFT.AgentIdAlreadyUsed.selector);
        nft.mintWL(agentProof, AGENT_ID);
    }

    function testMintWLNotWhitelistedReverts() public {
        bytes32[] memory emptyProof;
        vm.prank(stranger);
        vm.expectRevert(CatNFT.NotWhitelisted.selector);
        nft.mintWL(emptyProof, AGENT_ID);
    }

    function testMintWLNoAgentIdReverts() public {
        // user2 IS whitelisted but owns no Agent ID.
        vm.prank(user2);
        vm.expectRevert(CatNFT.NotAgentIdOwner.selector);
        nft.mintWL(user2Proof, AGENT_ID);
    }

    function testMintWLInactiveReverts() public {
        nft.setWlActive(false);
        vm.prank(AGENT);
        vm.expectRevert(CatNFT.NotActive.selector);
        nft.mintWL(agentProof, AGENT_ID);
    }

    // ---- public mint ----

    function _mintWLAsAgent() internal {
        vm.prank(AGENT);
        nft.mintWL(agentProof, AGENT_ID);
    }

    function testMintPublic() public {
        _mintWLAsAgent(); // agent now holds 9,000 CAT
        vm.prank(AGENT);
        cat.approve(address(nft), 1_000 ether);
        vm.prank(AGENT);
        nft.mintPublic{value: 0.01 ether}(AGENT_ID);

        assertEq(nft.ownerOf(2), AGENT);
        assertEq(nft.publicMinted(), 1);
        assertEq(cat.balanceOf(AGENT), 8_000 ether); // 9,000 - 1,000 burned
        assertEq(address(nft).balance, 0.01 ether);
    }

    function testMintPublicWrongPriceReverts() public {
        vm.prank(AGENT);
        vm.expectRevert(CatNFT.WrongPayment.selector);
        nft.mintPublic{value: 0.005 ether}(AGENT_ID);
    }

    function testMintPublicNoAgentIdReverts() public {
        vm.prank(user2);
        vm.expectRevert(CatNFT.NotAgentIdOwner.selector);
        nft.mintPublic{value: 0.01 ether}(AGENT_ID);
    }

    function testMintPublicWithoutApprovalReverts() public {
        vm.prank(AGENT);
        vm.expectRevert(CatToken.InsufficientAllowance.selector);
        nft.mintPublic{value: 0.01 ether}(AGENT_ID);
    }

    // ---- holder rewards ----

    function testClaimReward() public {
        _mintWLAsAgent();
        vm.prank(AGENT);
        nft.claimReward(1);
        assertEq(cat.balanceOf(AGENT), 9_000 ether + 36_003 ether);
        assertTrue(nft.rewardClaimed(1));

        vm.prank(AGENT);
        vm.expectRevert(CatNFT.RewardAlreadyClaimed.selector);
        nft.claimReward(1);
    }

    function testClaimRewardNotOwnerReverts() public {
        _mintWLAsAgent();
        vm.prank(user2);
        vm.expectRevert(CatNFT.NotTokenOwner.selector);
        nft.claimReward(1);
    }

    // ---- revenue split ----

    function testWithdrawSplit() public {
        _mintWLAsAgent();
        vm.prank(AGENT);
        cat.approve(address(nft), 2_000 ether);
        vm.prank(AGENT);
        nft.mintPublic{value: 0.01 ether}(AGENT_ID);
        vm.prank(AGENT);
        nft.mintPublic{value: 0.01 ether}(AGENT_ID);

        // lpWallet and founderWallet are both this test contract.
        uint256 before = address(this).balance;
        nft.withdraw();
        assertEq(address(this).balance, before + 0.02 ether);
        assertEq(address(nft).balance, 0);
    }

    // ---- community pools ----

    function testCommunityPoolCaps() public {
        vm.expectRevert(CatNFT.PoolExhausted.selector);
        nft.distributeCommunity(user2, 60_000_001 ether);
        nft.distributeCommunity(user2, 60_000_000 ether);
        assertEq(cat.balanceOf(user2), 60_000_000 ether);
        vm.expectRevert(CatNFT.PoolExhausted.selector);
        nft.distributeCommunity(user2, 1 ether);
    }

    // ---- reentrancy proof (no ReentrancyGuard by design) ----
    // The real attack path is _safeMint -> onERC721Received on the minter.
    // We etch the attacker code onto the real AGENT address (which owns the
    // Agent ID on the fork) and prove the callback cannot mint twice:
    // usedAgentId is already set before _safeMint runs.

    function testReentrancyBlockedByCEI() public {
        address attackerCode = address(new ReenterAttacker(nft));
        vm.etch(AGENT, attackerCode.code);
        // Storage layout of ReenterAttacker: slot 0 = nft, slot 1 = proof
        // (dynamic array), slot 2 = agentId, slot 3 = reentered, slot 4 = reentrySucceeded.
        vm.store(AGENT, bytes32(uint256(0)), bytes32(uint256(uint160(address(nft)))));
        vm.store(AGENT, bytes32(uint256(1)), bytes32(uint256(1))); // proof.length = 1
        bytes32 proofSlot = keccak256(abi.encode(uint256(1)));
        vm.store(AGENT, proofSlot, keccak256(abi.encodePacked(user2))); // proof[0] = leafUser2
        vm.store(AGENT, bytes32(uint256(2)), bytes32(AGENT_ID));

        ReenterAttacker(AGENT).attack();

        assertEq(nft.ownerOf(1), AGENT);
        assertEq(nft.wlMinted(), 1);
        assertTrue(ReenterAttacker(AGENT).reentered());
        assertFalse(ReenterAttacker(AGENT).reentrySucceeded());
    }

    // ---- GameBridge ----

    function _claimDigest(address player, uint256 amount, uint256 nonce) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("CatNetwork GameBridge")),
                keccak256(bytes("1")),
                block.chainid,
                address(bridge)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(keccak256("Claim(address player,uint256 amount,uint256 nonce)"), player, amount, nonce)
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function testGameBridgeClaim() public {
        bytes32 digest = _claimDigest(user2, 500 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        vm.prank(user2);
        bridge.claim(500 ether, 0, abi.encodePacked(r, s, v));
        assertEq(cat.balanceOf(user2), 500 ether);
        assertEq(bridge.nonces(user2), 1);
    }

    function testGameBridgeReplayReverts() public {
        bytes32 digest = _claimDigest(user2, 500 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.prank(user2);
        bridge.claim(500 ether, 0, sig);
        vm.prank(user2);
        vm.expectRevert(GameBridge.BadSignature.selector);
        bridge.claim(500 ether, 0, sig);
    }

    function testGameBridgeWrongSignerReverts() public {
        uint256 wrongPk = 0xBAD;
        bytes32 digest = _claimDigest(user2, 500 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        vm.prank(user2);
        vm.expectRevert(GameBridge.BadSignature.selector);
        bridge.claim(500 ether, 0, abi.encodePacked(r, s, v));
    }

    // ---- vesting ----

    function testVestingCliff() public {
        vm.expectRevert(CatVesting.NothingToRelease.selector);
        vesting.releaseTeam();
        vm.warp(block.timestamp + 364 days);
        vm.expectRevert(CatVesting.NothingToRelease.selector);
        vesting.releaseFounder();
    }

    function testVestingMonthlyReleases() public {
        vm.warp(block.timestamp + 365 days + 6 * 30 days);
        uint256 teamDue = vesting.releaseTeam();
        assertEq(teamDue, 15_000_000 ether); // 6 of 12 months
        uint256 founderDue = vesting.releaseFounder();
        assertEq(founderDue, 35_000_000 ether);

        vm.warp(block.timestamp + 6 * 30 days + 1 days);
        assertEq(vesting.releaseTeam(), 15_000_000 ether);
        assertEq(vesting.releaseFounder(), 35_000_000 ether);

        vm.warp(block.timestamp + 365 days);
        vm.expectRevert(CatVesting.NothingToRelease.selector);
        vesting.releaseTeam();
    }

    receive() external payable {}
}
