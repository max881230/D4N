// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ISudoSwapPool} from "./sudoSwapInterface.sol";
import {LSSVMPair} from "lssvm/src/LSSVMPair.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Central} from "./Central.sol";

contract Vault is ERC20Votes {
    bool public isRefundable = false;
    bool public isVaultAcitve = true;
    uint256 public proposalCount = 0;
    uint256 public votingThreashold = 0;

    mapping(address => bool) mintCheck;
    mapping(address => uint256) balances;
    mapping(uint256 => ProposalInfo) public proposals;
    mapping(uint256 => uint256) public proposalBlock;
    mapping(uint256 => mapping(address => bool)) public proposalVoteCheck;

    uint256 constant proposalLifetime = 86_400 * 1;
    uint256 constant voteLifetime = 86_400 * 2;

    address public veryFastRouter = 0x090C236B62317db226e6ae6CD4c0Fd25b7028b65;

    Central central;
    Central.ProposalInfo public VaultInfo;

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

    modifier checkProposalId(uint256 proposalId) {
        require(
            proposalId != 0 && proposalId <= proposalCount,
            "Invalid proposal ID"
        );
        _;
    }

    modifier isActive() {
        require(isVaultAcitve == true, "Vault has expired");
        _;
    }

    constructor(
        Central.ProposalInfo memory VaultInfo_,
        address centralAddr_
    ) ERC20("Vault", "VV") EIP712("Vault", "1") {
        central = Central(payable(centralAddr_));
        VaultInfo = VaultInfo_;
        VaultInfo.lifetime = block.timestamp + VaultInfo.lifetime;
        VaultInfo.ownNFTs = true;
        _mint(address(this), VaultInfo.value);
    }

    function propose(
        string memory purpose,
        uint256 minOutput
    ) public isActive returns (uint256) {
        require(
            getPastVotes(msg.sender, block.number - 1) > 0,
            "Only investors who has vote amount can raise proposal"
        );
        proposalCount++;
        uint256 newProposalId = proposalCount;

        ProposalInfo storage newProposal = proposals[newProposalId];
        proposalBlock[newProposalId] = block.number - 1;
        newProposal.id = newProposalId;
        newProposal.proposer = msg.sender;
        newProposal.purpose = purpose;
        newProposal.minOutput = minOutput;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.startTime = block.timestamp + proposalLifetime;
        newProposal.endTime = newProposal.startTime + voteLifetime;
        newProposal.canceled = false;
        newProposal.executed = false;

        return newProposalId;
    }

    function _sell(uint256 proposalId) internal {
        require(VaultInfo.ownNFTs == true, "There are no NFTs in this vault");
        // sell NFT procedure start
        uint256[] memory nftIds = new uint[](1);
        nftIds[0] = VaultInfo.nftId;
        IERC721(VaultInfo.interactedNft).approve(
            veryFastRouter,
            VaultInfo.nftId
        );
        uint256[] memory minExpectedOutputPerNumNFTs = new uint[](1);
        uint256 minOutput;
        if (block.timestamp > VaultInfo.lifetime && proposalId == 0) {
            minOutput = 1 ether;
        } else {
            minOutput = proposals[proposalId].minOutput;
        }
        minExpectedOutputPerNumNFTs[0] = minOutput;

        ISudoSwapPool.Order memory swapOrder;
        ISudoSwapPool.BuyOrderWithPartialFill[] memory buyOrders;
        ISudoSwapPool.SellOrderWithPartialFill[]
            memory sellOrders = new ISudoSwapPool.SellOrderWithPartialFill[](1);

        sellOrders[0].pair = LSSVMPair(VaultInfo.interactedPool);
        sellOrders[0].isETHSell = true;
        sellOrders[0].isERC721 = true;
        sellOrders[0].nftIds = nftIds;
        sellOrders[0].doPropertyCheck = false;
        sellOrders[0].propertyCheckParams = "0x";
        sellOrders[0].expectedSpotPrice = uint128(minOutput);
        sellOrders[0].minExpectedOutput = minOutput;
        sellOrders[0].minExpectedOutputPerNumNFTs = minExpectedOutputPerNumNFTs;

        swapOrder = ISudoSwapPool.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(address(this)),
            nftRecipient: address(this),
            recycleETH: false
        });
        ISudoSwapPool(veryFastRouter).swap(swapOrder);
        // end of selling NFT

        VaultInfo.ownNFTs = false;
        isRefundable = true;
    }

    function vote(
        uint256 proposalId,
        uint8 support
    ) public checkProposalId(proposalId) isActive {
        require(
            block.timestamp > proposals[proposalId].startTime,
            "Proposal is under reviewing"
        );
        require(
            block.timestamp < proposals[proposalId].endTime,
            "Proposal is expired"
        );
        _castVote(proposalId, support);
    }

    function _castVote(uint256 proposalId, uint8 support) internal {
        // getPastVotes to get amount of votes
        uint256 votes = getPastVotes(msg.sender, proposalBlock[proposalId]);

        require(
            proposalVoteCheck[proposalId][msg.sender] == false,
            "You have already voted for this proposal"
        );
        proposalVoteCheck[proposalId][msg.sender] = true;

        // 1 is for, 0 is against
        require(support == 0 || support == 1, "Invalid voting choice");
        support == 1
            ? proposals[proposalId].forVotes += votes
            : proposals[proposalId].againstVotes += votes;
    }

    function executeVote(
        uint256 proposalId
    ) public checkProposalId(proposalId) isActive {
        require(
            block.timestamp > proposals[proposalId].endTime,
            "Voting is still ongoing"
        );
        require(
            proposals[proposalId].executed == false,
            "Proposal has been executed"
        );

        uint256 totalVotes = getPastTotalSupply(proposalBlock[proposalId]);
        // check whether the forVotes is greater than againstVotes and if it is, the total amount of for votes must greater than 50 % of total votes to pass
        if (
            proposals[proposalId].againstVotes * 2 > totalVotes ||
            proposals[proposalId].forVotes * 2 < totalVotes
        ) {
            proposals[proposalId].canceled = true;
        }

        require(
            proposals[proposalId].canceled == false,
            "The proposal has been rejected"
        );
        if (
            keccak256(abi.encodePacked(proposals[proposalId].purpose)) ==
            keccak256(abi.encodePacked("sell"))
        ) {
            proposals[proposalId].executed = true;
            _sell(proposalId);
        }
    }

    // a must-do function if the investor wants to retrieve their assets back
    // turn balance into vault token for refund and voting
    function mintVaultToken() public isActive {
        // read mapping balance value from central
        (, uint256 balance) = getBalance();
        require(balance > 0, "You don't have any assets in this vault");
        require(
            mintCheck[msg.sender] == false,
            "You have already minted vault token"
        );
        mintCheck[msg.sender] = true;
        balances[msg.sender] = balance;
        _transfer(address(this), msg.sender, balance);
    }

    // refund can only be executed when the vault has expired
    function refund() public {
        // assert all the investers in this vault has called mintVaultToken before,
        // to update the balance record.
        require(isRefundable == true, "There are still NFTs in this vault");
        require(
            balances[msg.sender] > 0,
            "You don't have any assets in this vault"
        );

        uint256 amount = balances[msg.sender];
        balances[msg.sender] = 0;
        payable(msg.sender).transfer(
            (address(this).balance * amount) / VaultInfo.value
        );
    }

    function closeVault() public isActive {
        require(
            block.timestamp > VaultInfo.lifetime,
            "Vault hasn't expired yet"
        );
        if (VaultInfo.ownNFTs == true) {
            // vault still has Nfts in it, the vault will set a minOutput price automatically
            // and force to sell Nfts.
            _sell(0);
            isRefundable = true;
        }
        isVaultAcitve = false;
    }

    function getBalance() public view isActive returns (uint256, uint256) {
        return (
            VaultInfo.id,
            central.proposalBalances(VaultInfo.id, msg.sender)
        );
    }

    function getProposalInfo(
        uint256 proposalId
    )
        public
        view
        checkProposalId(proposalId)
        isActive
        returns (
            uint256 id,
            address proposer,
            string memory purpose,
            uint256 minOutput,
            uint256 startTime,
            uint256 endTime
        )
    {
        ProposalInfo storage p = proposals[proposalId];
        return (
            p.id,
            p.proposer,
            p.purpose,
            p.minOutput,
            p.startTime,
            p.endTime
        );
    }

    function getProposalStatus(
        uint256 proposalId
    )
        public
        view
        checkProposalId(proposalId)
        isActive
        returns (
            uint256 forVotes,
            uint256 againstVotes,
            bool canceled,
            bool executed
        )
    {
        ProposalInfo storage p = proposals[proposalId];
        return (p.forVotes, p.againstVotes, p.canceled, p.executed);
    }

    function getVaultInfo()
        public
        view
        isActive
        returns (
            uint256 id,
            address interactedPool,
            uint256 nftId,
            uint256 vaultVaule,
            uint256 lifetime
        )
    {
        Central.ProposalInfo storage v = VaultInfo;
        return (v.id, v.interactedPool, v.nftId, v.value, v.lifetime);
    }

    function getVaultRemainingTime() public view isActive returns (uint256) {
        return VaultInfo.lifetime - block.timestamp;
    }

    receive() external payable {}

    // function stake() public {}
    // function lend() public {}
}
