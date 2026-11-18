// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
