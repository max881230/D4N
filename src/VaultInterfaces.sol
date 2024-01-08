// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IVault {
    struct ProposalInfo {
        // id of the current proposal
        uint256 id;
        // address of the proposer
        address proposer;
        // purpose of the proposal
        string purpose;
        // min income for selling the NFTs
        uint256 minOutput;
        // votes for the proposal
        uint256 forVotes;
        // votes against the proposal
        uint256 againstVotes;
        // start time of a proposal
        uint256 startTime;
        // end time of a proposal
        uint256 endTime;
        // status of whether the proposal is canceled or not
        bool canceled;
        // status of whether the proposal is executed or not
        bool executed;
    }

    function propose(
        string memory purpose,
        uint256 minOutput
    ) external returns (uint256);

    function vote(uint256 proposalId, uint8 support) external;

    function executeVote(uint256 proposalId) external;

    function mintVaultToken() external;

    function refund() external;

    function closeVault() external;

    function getBalance() external view returns (uint256, uint256);

    function getProposalInfo(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 id,
            address proposer,
            string memory purpose,
            uint256 minOutput,
            uint256 startTime,
            uint256 endTime
        );

    function getProposalStatus(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 forVotes,
            uint256 againstVotes,
            bool canceled,
            bool executed
        );

    function getVaultInfo()
        external
        view
        returns (
            uint256 id,
            address interactedPool,
            uint256 nftId,
            uint256 vaultValue,
            uint256 lifetime
        );

    function getVaultRemainingTime() external view returns (uint256);
}
