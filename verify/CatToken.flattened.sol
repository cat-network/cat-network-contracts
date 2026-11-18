// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/CatToken.sol

/// @title CatToken ($CAT) — Cat Network (lean minimal ERC20)
/// @notice Fixed supply of 1,000,000,000 $CAT, minted once to the deployer.
/// Distribution is done by the deploy script (see script/Deploy.s.sol):
///   500M -> GameBridge (Tap to Earn mining rewards, released 1:1 as players mine)
///   200M -> CatNFT (NFT holder rewards, claimable per NFT)
///   100M -> CatNFT community pools (WL airdrop 10M / community 60M / referral 20M / reserve 10M)
///   100M -> CatVesting (team 30M + founder 70M, 12-month cliff, 12 monthly releases)
///   100M -> owner (liquidity pool seed, paired with mint BNB revenue)
/// @dev Hand-rolled minimal ERC20 (no OpenZeppelin) to keep deployment gas
/// low enough to fit the ~0.0003 BNB budget. Standard ERC20 behaviour only:
/// transfer / approve / transferFrom / burn / burnFrom, 18 decimals.
/// The NFT mint burns the 1,000 $CAT each mint requires (whitepaper section 4).
contract CatToken {
    string public constant name = "Cat Network";
    string public constant symbol = "CAT";
    uint8 public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1 billion

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    constructor() {
        totalSupply = TOTAL_SUPPLY;
        balanceOf[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert InsufficientAllowance();
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        _transfer(from, to, value);
        return true;
    }

    /// @notice Burn the caller's own $CAT (used by the NFT contract for the
    /// 1,000 $CAT mint cost, and by WL airdrop accounting).
    function burn(uint256 value) external {
        if (balanceOf[msg.sender] < value) revert InsufficientBalance();
        balanceOf[msg.sender] -= value;
        totalSupply -= value;
        emit Transfer(msg.sender, address(0), value);
    }

    /// @notice Burn $CAT from an account that approved this contract
    /// (used by CatNFT.mintPublic for the 1,000 $CAT mint cost).
    function burnFrom(address from, uint256 value) external {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert InsufficientAllowance();
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        if (balanceOf[from] < value) revert InsufficientBalance();
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < value) revert InsufficientBalance();
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
