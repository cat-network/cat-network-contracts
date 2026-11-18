// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {CatToken} from "./CatToken.sol";

/// @title CatNFTv2 — Cat Network NFT collection (5,555), v2
/// @notice v2 change (2026-11-19, Deni: "buka untuk semua wallet"): the
/// public mint is open to EVERY wallet. mintPublic() takes no agentId and
/// does NOT check Agent ID ownership. Everything else is identical to v1:
/// 0.01 BNB + 1,000 $CAT burned per public mint, 36,003 $CAT holder reward
/// per NFT, same pools and caps. WL mint (mintWL) still requires an Agent
/// ID, but WL is closed (wlActive=false) and stays closed.
/// @notice Whitepaper section 4: 1,000 whitelist mints FREE (gas only) +
/// 1,000 $CAT each, 4,555 public mints at 0.01 BNB + 1,000 $CAT each.
/// Every mint needs 1,000 $CAT (burned). WL minters also receive the 10,000
/// $CAT WL airdrop (9,000 to the minter, 1,000 burned as the mint cost).
/// The NFT contract also holds the 100,000,000 $CAT community allocation
/// (whitepaper section 5): WL airdrop 10M, community rewards 60M, referral
/// pool 20M, reserve 10M — each a hard on-chain cap.
/// @dev v1 required an Agent ID for every mint (Binance Agent ID Hackathon).
/// v2 drops that requirement for the PUBLIC mint only, so any wallet can mint.
/// NFT holders share the 200,000,000 $CAT mint-rewards pool: each NFT can
/// claim REWARD_PER_NFT once (200M / 5,555, rounded down).
/// Mint revenue (0.01 BNB x 4,555 = ~45.55 BNB) splits 50/50 on withdraw
/// between the liquidity-pool wallet and the founder wallet (whitepaper: ~22
/// BNB each).
/// @dev Lean build: no Pausable (the wlActive/publicActive flags stop minting)
/// and no ReentrancyGuard — every function follows checks-effects-interactions
/// (all state is updated before any external call), proven by the reentrancy
/// test in test/CatNetwork.t.sol.
contract CatNFTv2 is ERC721, Ownable {
    IERC721 public immutable agentIdRegistry;
    CatToken public immutable cat;

    /// @notice SPACE ID Agent ID registry on BNB Chain.
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    uint256 public constant MAX_SUPPLY = 5555;
    uint256 public constant WL_SUPPLY = 1000;
    uint256 public constant PUBLIC_PRICE = 0.01 ether;
    /// @notice $CAT consumed by every mint (whitepaper section 4).
    uint256 public constant MINT_CAT_COST = 1_000 ether;
    /// @notice 200,000,000 $CAT / 5,555 NFTs, rounded down.
    uint256 public constant REWARD_PER_NFT = 36_003 ether;

    // Community allocation pools (whitepaper section 5), hard caps.
    uint256 public constant WL_AIRDROP_POOL = 10_000_000 ether;
    uint256 public constant COMMUNITY_POOL = 60_000_000 ether;
    uint256 public constant REFERRAL_POOL = 20_000_000 ether;
    uint256 public constant RESERVE_POOL = 10_000_000 ether;
    /// @notice 10,000 $CAT airdropped per WL mint.
    uint256 public constant WL_AIRDROP_PER_MINT = 10_000 ether;

    uint256 public wlSpent;
    uint256 public communitySpent;
    uint256 public referralSpent;
    uint256 public reserveSpent;

    bytes32 public merkleRoot;
    bool public wlActive;
    bool public publicActive;

    uint256 public wlMinted;
    uint256 public publicMinted;
    uint256 public nextTokenId = 1;

    address public lpWallet;
    address public founderWallet;
    string private baseTokenURI;

    /// @dev Agent ID tokenId => already used for a free WL mint.
    mapping(uint256 => bool) public usedAgentId;
    /// @dev NFT tokenId => holder reward already claimed.
    mapping(uint256 => bool) public rewardClaimed;

    event Minted(address indexed minter, uint256 indexed tokenId, uint256 indexed agentId, bool whitelist);
    event RewardClaimed(address indexed owner, uint256 indexed tokenId, uint256 amount);
    event WLAirdrop(address indexed minter, uint256 toMinter, uint256 burned);
    event Distributed(string indexed pool, address indexed to, uint256 amount);
    event Withdrawn(uint256 toLp, uint256 toFounder);
    event BaseURISet(string baseURI);

    error NotActive();
    error SoldOut();
    error NotAgentIdOwner();
    error NotTokenOwner();
    error AgentIdAlreadyUsed();
    error RewardAlreadyClaimed();
    error NotWhitelisted();
    error WrongPayment();
    error PoolExhausted();
    error ZeroAddress();

    constructor(CatToken _cat, address _lpWallet, address _founderWallet)
        ERC721("Cat Network NFT", "CATN")
        Ownable(msg.sender)
    {
        if (_lpWallet == address(0) || _founderWallet == address(0)) revert ZeroAddress();
        cat = _cat;
        agentIdRegistry = IERC721(AGENT_ID_REGISTRY);
        lpWallet = _lpWallet;
        founderWallet = _founderWallet;
    }

    // ---- admin ----

    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
    }

    function setWlActive(bool _active) external onlyOwner {
        wlActive = _active;
    }

    function setPublicActive(bool _active) external onlyOwner {
        publicActive = _active;
    }

    function setBaseURI(string calldata _uri) external onlyOwner {
        baseTokenURI = _uri;
        emit BaseURISet(_uri);
    }

    function setWallets(address _lp, address _founder) external onlyOwner {
        if (_lp == address(0) || _founder == address(0)) revert ZeroAddress();
        lpWallet = _lp;
        founderWallet = _founder;
    }

    /// @notice Withdraw mint revenue, split 50/50 LP wallet / founder wallet.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        uint256 toLp = balance / 2;
        uint256 toFounder = balance - toLp;
        emit Withdrawn(toLp, toFounder);
        (bool okLp, ) = lpWallet.call{value: toLp}("");
        require(okLp, "lp transfer failed");
        (bool okF, ) = founderWallet.call{value: toFounder}("");
        require(okF, "founder transfer failed");
    }

    /// @notice Community rewards: contests, leaderboard, seasonal events.
    function distributeCommunity(address to, uint256 amount) external onlyOwner {
        if (communitySpent + amount > COMMUNITY_POOL) revert PoolExhausted();
        communitySpent += amount;
        require(cat.transfer(to, amount), "transfer failed");
        emit Distributed("community", to, amount);
    }

    /// @notice Referral pool: top referrers.
    function distributeReferral(address to, uint256 amount) external onlyOwner {
        if (referralSpent + amount > REFERRAL_POOL) revert PoolExhausted();
        referralSpent += amount;
        require(cat.transfer(to, amount), "transfer failed");
        emit Distributed("referral", to, amount);
    }

    /// @notice Reserve: future community programs.
    function distributeReserve(address to, uint256 amount) external onlyOwner {
        if (reserveSpent + amount > RESERVE_POOL) revert PoolExhausted();
        reserveSpent += amount;
        require(cat.transfer(to, amount), "transfer failed");
        emit Distributed("reserve", to, amount);
    }

    // ---- minting ----

    function _requireAgentId(uint256 agentId) internal view {
        if (agentIdRegistry.ownerOf(agentId) != msg.sender) revert NotAgentIdOwner();
    }

    function _mintNext(address to) internal returns (uint256 tokenId) {
        tokenId = nextTokenId;
        if (tokenId > MAX_SUPPLY) revert SoldOut();
        nextTokenId = tokenId + 1;
        _safeMint(to, tokenId);
    }

    /// @notice Free WL mint (gas only). Caller must be on the whitelist
    /// (merkle proof) and own an Agent ID that has not claimed a free mint.
    /// The 10,000 $CAT WL airdrop pays for this mint: 9,000 $CAT to the
    /// minter, 1,000 $CAT burned. No $CAT approval needed from the minter.
    function mintWL(bytes32[] calldata proof, uint256 agentId) external {
        if (!wlActive) revert NotActive();
        if (wlMinted >= WL_SUPPLY) revert SoldOut();
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert NotWhitelisted();
        _requireAgentId(agentId);
        if (usedAgentId[agentId]) revert AgentIdAlreadyUsed();
        if (wlSpent + WL_AIRDROP_PER_MINT > WL_AIRDROP_POOL) revert PoolExhausted();

        usedAgentId[agentId] = true;
        wlMinted += 1;
        wlSpent += WL_AIRDROP_PER_MINT;
        uint256 tokenId = _mintNext(msg.sender);
        // Effects done; now the only external calls (token is trusted).
        require(cat.transfer(msg.sender, WL_AIRDROP_PER_MINT - MINT_CAT_COST), "transfer failed");
        cat.burn(MINT_CAT_COST);
        emit WLAirdrop(msg.sender, WL_AIRDROP_PER_MINT - MINT_CAT_COST, MINT_CAT_COST);
        emit Minted(msg.sender, tokenId, agentId, true);
    }

    /// @notice Public mint: 0.01 BNB + 1,000 $CAT (burned from the minter).
    /// Open to ANY wallet (v2: no Agent ID needed). The minter must approve
    /// this contract to spend 1,000 $CAT before calling.
    function mintPublic() external payable {
        if (!publicActive) revert NotActive();
        if (publicMinted >= MAX_SUPPLY - WL_SUPPLY) revert SoldOut();
        if (msg.value != PUBLIC_PRICE) revert WrongPayment();

        publicMinted += 1;
        uint256 tokenId = _mintNext(msg.sender);
        cat.burnFrom(msg.sender, MINT_CAT_COST);
        emit Minted(msg.sender, tokenId, 0, false);
    }

    /// @notice Claim this NFT's share of the 200M $CAT holder-rewards pool.
    /// One claim per NFT, only by its current owner.
    function claimReward(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (rewardClaimed[tokenId]) revert RewardAlreadyClaimed();
        rewardClaimed[tokenId] = true;
        emit RewardClaimed(msg.sender, tokenId, REWARD_PER_NFT);
        require(cat.transfer(msg.sender, REWARD_PER_NFT), "transfer failed");
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }
}
