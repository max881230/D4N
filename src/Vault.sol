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
    uint256 public proposalCount = 0;
    uint256 public votingThreashold = 0;

    mapping(address => bool) mintCheck;
    mapping(address => uint256) balances;
    mapping(uint => ProposalInfo) public proposals;

    uint256 constant proposalLifetime = 86_400 * 1;
    uint256 constant voteLifetime = 86_400 * 2;

    address public veryFastRouter = 0x090C236B62317db226e6ae6CD4c0Fd25b7028b65;

    Central central;
    Central.ProposalInfo public VaultInfo;

    struct ProposalInfo {
        uint256 id;
        address proposer;
        string purpose;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool canceled;
        bool executed;
    }

    modifier checkProposalId(uint256 proposalId) {
        require(
            proposalId != 0 && proposalId <= proposalCount,
            "Invalid proposal ID"
        );
        _;
    }

    constructor(
        Central.ProposalInfo memory VaultInfo_,
        address centralAddr_
    ) ERC20("Vault", "VV") EIP712("Vault", "1") {
        central = Central(payable(centralAddr_));
        VaultInfo = VaultInfo_;
        VaultInfo.lifetime = block.timestamp + VaultInfo.lifetime;
        _mint(address(this), VaultInfo.value);
    }

    function sell(uint256 proposalId, uint256 minOutput) internal {
        // sell NFT procedure
        uint256[] memory nftIds = new uint[](1);
        nftIds[0] = VaultInfo.nftId;
        IERC721(VaultInfo.interactedNft).approve(
            veryFastRouter,
            VaultInfo.nftId
        );
        uint256[] memory minExpectedOutputPerNumNFTs = new uint[](1);
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

        proposals[proposalId].executed = true;
        VaultInfo.ownNFTs = false;
    }

    function propose(string memory purpose) public returns (uint256) {
        require(
            balances[msg.sender] > 0,
            "Only the investor in this vault has the privilege to propose"
        );
        proposalCount++;
        uint256 newProposalId = proposalCount;

        ProposalInfo storage newProposal = proposals[newProposalId];
        newProposal.id = newProposalId;
        newProposal.proposer = msg.sender;
        newProposal.purpose = purpose;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.startTime = block.timestamp + proposalLifetime;
        newProposal.endTime = newProposal.startTime + voteLifetime;
        newProposal.canceled = false;
        newProposal.executed = false;

        return newProposalId;
    }

    // function vote(uint256 proposalId) public checkProposalId(proposalId) {
    //     require(
    //         block.timestamp > proposals[proposalId].startTime,
    //         "Proposal is under reviewing"
    //     );
    //     require(
    //         block.timestamp < proposals[proposalId].endTime,
    //         "Proposal is expired"
    //     );
    //     castVote();
    // }

    // function castVote(uint256 proposalId) internal {}

    // function executeVote(uint256 proposalId) public {
    //     // check whether the forVotes is greater than againstVotes and the total amount of result must greater than 50 %
    //     if (proposals[proposalId].purpose == "sell") {
    //         //
    //         require(
    //             proposals[proposalId].canceled == false,
    //             "The proposal has been canceled"
    //         );
    //         sell(proposalId);
    //     }
    // }

    // turn balance into vault token for refund and voting
    function mintVaultToken() public {
        // read mapping balance value from central
        (uint256 id, uint256 balance) = getBalance();
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
    // function refund() internal {
    //     // assert all the investers in this vault has called mintVaultToken before, to update the balance record.
    // }

    // function closeVault() public {
    //     require(
    //         block.timestamp > VaultInfo.lifetime,
    //         "Vault hasn't expired yet"
    //     );

    //     if (VaultInfo.ownNFTs == false) {
    //         refund();
    //     } else {
    //         sell(??);
    //         refund();
    //     }
    // }

    function getBalance() public view returns (uint256, uint256) {
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
        returns (
            uint256 id,
            address proposer,
            string memory purpose,
            uint256 startTime,
            uint256 endTime
        )
    {
        ProposalInfo storage p = proposals[proposalId];
        return (p.id, p.proposer, p.purpose, p.startTime, p.endTime);
    }

    function getVaultInfo()
        public
        view
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

    function getVaultRemainingTime() public view returns (uint256) {
        return VaultInfo.lifetime - block.timestamp;
    }

    receive() external payable {}

    // function stake() public {}
    // function lend() public {}
}

// 先delegate (怎麼使用)
// 提案 propose 只有 balance > 0 才可以提案
// vote
// 檢查 getPriorVote

// executeVote
// sell NFT
