// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LitToken — $LIT governance + utility token
/// @notice ERC20 with capped supply, Permit (EIP-2612), and Votes (ERC20Votes) for governance.
///         Burning is permissionless (anyone can burn their own tokens). Minting is one-time at deploy.
contract LitToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    error MintExceedsCap();
    error InitialMintAlreadyDone();

    bool private _initialMinted;

    constructor(address _treasury)
        ERC20("LITNUP", "LIT")
        ERC20Permit("LITNUP")
        Ownable(_treasury)
    {
        // No mint in constructor; call mintInitialSupply() once via governance/treasury
        // This split allows the treasury multisig to be set up before tokens land in it
    }

    /// @notice One-time mint of full supply to the treasury. Callable only by owner, only once.
    function mintInitialSupply() external onlyOwner {
        if (_initialMinted) revert InitialMintAlreadyDone();
        _initialMinted = true;
        _mint(owner(), MAX_SUPPLY);
    }

    /// @notice Permissionless burn of own tokens. Reduces total supply.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn from approved allowance. Used by BuybackBurn.
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // -------- required overrides --------

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner_)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner_);
    }
}
