// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Vault.sol";
import "./sudoSwapInterface.sol";

interface ICentral {
    struct ProposalInfo {
        // id of the current proposal
        uint256 id;
        // address of the proposer
        address proposer;
        // address of the pool interacted on sudoswap
        address interactedPool;
        // address of the target NFT
        address interactedNft;
        // NFT id of which the vault is going to purchase
        uint256 nftId;
        // floor price of the NFT the vault is going to purchase
        uint256 floorPrice;
        // lifetime of the vault
        uint256 lifetime; // time + lifetime (86400)
        // ETH value of the current proposal / vault
        uint256 value;
        // status of whether the vault is created or not
        bool vaultCreated;
        // address of the vault
        address vaultAddress;
        // status of whether the vault owns a NFT or not
        bool ownNFTs;
    }

    function createProposal(
        address interactedPool,
        address interactedNft,
        uint256 nftId,
        uint256 floorPrice,
        uint256 lifetime
    ) external returns (uint256);

    function getProposalInfo(
        uint256 proposalId
    )
        external
        view
        returns (uint256, address, address, uint256, uint256, uint256);

    function getProposalStatus(uint256 proposalId) external view returns (bool);

    function deposit(uint256 proposalId) external payable returns (address);

    function getBalanceCheck(
        uint256 proposalId
    ) external view returns (uint256);

    function refund(uint256 proposalId) external;

    receive() external payable;
}
