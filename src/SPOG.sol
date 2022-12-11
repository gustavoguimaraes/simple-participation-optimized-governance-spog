// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IERC20 {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function mint(uint256 amount) external;

    function totalSupply() external view returns (uint256);
}

interface IAuction {
    function sell(uint256 amount) external;
}

/**
 * @title SPOG
 * @dev A governance contract that allows users to stake tokens and vote on proposals
 * @dev Reference: https://hackmd.io/6Y8x2jL1R0CBo6RRBESpLA?both
 * @notice This contract is an imcomplete version from the SPOG doc. It is missing the following: GRIEF and BUYOUT functionalities.
 * A Simple Participation Optimized Governance (“SPOG”) contract minimizes the consensus surface to a binary choice on the following:
 * - Call or do not call arbitrary code
 *
 * In order to deploy an SPOG contract, the creator must first input an ERC20 token address (the token can be specific to the SPOG or an existing ERC20) along with the following arguments, which are immutable. Additionally, all SPOGs should be endowed with a purpose that is ideally a single sentence.
 *
 * Arguments:
 *
 * - TOKEN
 *   - The ERC20 address that will be used to govern the SPOG
 *   - Can be an existing token (e.g. WETH) or a SPOG-specific token
 * - TAX
 *   - The cost, in CASH to call VOTE
 * - CASH
 *   - ERC20 token address to be used for SELL and TAX (e.g. DAI or WETH)
 * - TIME
 *   - The duration of a vote
 * - INFLATOR
 *   - The percentage supply increase in SFG tokens each time VOTE is called
 *
 * SPOG token holders are likened to “nodes” in a decentralized consensus mechanism and are therefore punished for being “offline.”
 */
contract SPOG {
}
