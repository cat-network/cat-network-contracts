// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20 ^0.8.24;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/CatVesting.sol

/// @title CatVesting — team + founder lock
/// @notice Holds 100,000,000 $CAT: team 30,000,000 (3%) + founder 70,000,000 (7%).
/// Whitepaper section 5: locked for 12 months from token launch, then unlock
/// in equal monthly parts. This contract implements a 12-month cliff followed
/// by 12 equal monthly releases (1/12 per month). Neither team nor founder
/// can sell before the community has had a full year.
/// @dev Launch time = deployment time. Anyone may call release(); each
/// beneficiary can only ever receive their own allocation.
contract CatVesting {
    IERC20 public immutable cat;

    address public immutable team;
    address public immutable founder;

    uint256 public constant TEAM_ALLOCATION = 30_000_000 ether;
    uint256 public constant FOUNDER_ALLOCATION = 70_000_000 ether;

    uint256 public immutable start; // token launch = deployment
    uint256 public constant CLIFF = 365 days;
    uint256 public constant RELEASE_MONTHS = 12;
    uint256 public constant MONTH = 30 days;

    uint256 public teamReleased;
    uint256 public founderReleased;

    event Released(address indexed beneficiary, uint256 amount);

    error NothingToRelease();
    error ZeroAddress();

    constructor(IERC20 _cat, address _team, address _founder) {
        if (_team == address(0) || _founder == address(0)) revert ZeroAddress();
        cat = _cat;
        team = _team;
        founder = _founder;
        start = block.timestamp;
    }

    /// @notice Vested amount for a given allocation at the current time.
    /// @dev Takes the allocation as a parameter (not the beneficiary address)
    /// so team and founder stay distinct even if both roles ever share one wallet.
    function _vested(uint256 allocation) internal view returns (uint256) {
        if (block.timestamp < start + CLIFF) return 0;
        uint256 monthsElapsed = (block.timestamp - (start + CLIFF)) / MONTH;
        if (monthsElapsed > RELEASE_MONTHS) monthsElapsed = RELEASE_MONTHS;
        return (allocation * monthsElapsed) / RELEASE_MONTHS;
    }

    function _release(address beneficiary, uint256 allocation, bool isTeam) internal returns (uint256) {
        uint256 released = isTeam ? teamReleased : founderReleased;
        uint256 due = _vested(allocation) - released;
        if (due == 0) revert NothingToRelease();
        if (isTeam) teamReleased += due;
        else founderReleased += due;
        emit Released(beneficiary, due);
        require(cat.transfer(beneficiary, due), "transfer failed");
        return due;
    }

    /// @notice Release the team share vested so far.
    function releaseTeam() external returns (uint256) {
        return _release(team, TEAM_ALLOCATION, true);
    }

    /// @notice Release the founder share vested so far.
    function releaseFounder() external returns (uint256) {
        return _release(founder, FOUNDER_ALLOCATION, false);
    }
}
