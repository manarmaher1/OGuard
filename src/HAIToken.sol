// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title HAIToken
 * @notice Mock representation of the Hacken $HAI token.
 * @dev Reproduces the vulnerability pattern confirmed in Hacken's
 *      post-incident report: a single owner address controls minting
 *      with no rate limits or behavioral restrictions.
 *      This is the pattern OGuard is designed to protect.
 */
contract HAIToken is ERC20, Ownable {

    constructor() 
        ERC20("Hacken Token", "HAI") 
        Ownable(msg.sender) 
    {
        // Initial supply minted to deployer
        // In the real hack the deployer was Hacken's bridge infrastructure
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    /**
     * @notice Mint function controlled by owner.
     * @dev In the real HAI contract this was controlled by a single
     *      private key on a decommissioned DigitalOcean server.
     *      No rate limits. No behavioral checks. One key = unlimited power.
     *      This is the vulnerability OGuard prevents.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}