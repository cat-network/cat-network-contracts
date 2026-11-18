// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title GameBridge — Tap to Earn mining rewards
/// @notice Holds the 500,000,000 $CAT mining allocation (whitepaper section 5).
/// Game CAT is earned off-chain in the Tap to Earn game and converts 1:1.
/// The game server (signer) signs each player's claim; the player submits it
/// on-chain. One signature can only be used once (per-player nonce).
/// @dev Signature covers: player, amount, nonce, chainId, this contract.
/// The signer key lives on the game server, never on-chain.
contract GameBridge is Ownable, EIP712 {
    using ECDSA for bytes32;

    IERC20 public immutable cat;
    address public signer;

    /// @dev player => next usable nonce
    mapping(address => uint256) public nonces;

    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(address player,uint256 amount,uint256 nonce)");

    event Claimed(address indexed player, uint256 amount, uint256 nonce);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    error BadSignature();
    error ZeroAmount();
    error ZeroAddress();

    constructor(IERC20 _cat, address _signer) Ownable(msg.sender) EIP712("CatNetwork GameBridge", "1") {
        if (_signer == address(0)) revert ZeroAddress();
        cat = _cat;
        signer = _signer;
    }

    /// @notice Claim mined game CAT as $CAT. `amount` is the player's total
    /// earned game CAT being converted in this claim (server decides the amount).
    function claim(uint256 amount, uint256 nonce, bytes calldata signature) external {
        if (amount == 0) revert ZeroAmount();
        if (nonce != nonces[msg.sender]) revert BadSignature();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(CLAIM_TYPEHASH, msg.sender, amount, nonce))
        );
        if (digest.recover(signature) != signer) revert BadSignature();

        nonces[msg.sender] = nonce + 1;
        require(cat.transfer(msg.sender, amount), "transfer failed");
        emit Claimed(msg.sender, amount, nonce);
    }

    /// @notice Rotate the game-server signer key.
    function setSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) revert ZeroAddress();
        emit SignerUpdated(signer, _signer);
        signer = _signer;
    }
}
