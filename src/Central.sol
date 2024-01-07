// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./VaultDelegate.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./sudoSwapInterface.sol";

contract Central {
    address admin;
    uint256 public proposalCount = 0;
    uint256 public vaultCount = 0;
    address public interactPool;

    mapping(uint256 => mapping(address => uint256)) public proposalBalances;
    mapping(uint => ProposalInfo) public proposals;

    struct ProposalInfo {
        // id of the current proposal
        uint256 id;
        // address of the proposer
        address proposer;
        // address of the pool interacted on sudoswap
        address interactedPool;
        // NFT id of which the vault is going to purchase
        uint256 NFTId;
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

    modifier checkProposalId(uint256 proposalId) {
        require(
            proposalId != 0 && proposalId <= proposalCount,
            "Invalid proposal ID"
        );
        _;
    }

    // 可以拿掉 ERC20
    constructor(address admin_) {
        require(admin_ == msg.sender, "Invalid admin");
        admin = admin_;
    }

    // create a vaule with into parametet >
    function createVault(
        uint256 proposalId
    ) internal checkProposalId(proposalId) returns (address) {
        require(
            proposals[proposalId].vaultCreated == false,
            "vault has been created"
        );
        Vault vault = new Vault(proposals[proposalId], address(this));
        address payable vaultAddress = payable(address(vault));
        vaultCount++;

        proposals[proposalId].vaultCreated = true;
        proposals[proposalId].vaultAddress = vaultAddress;

        // initialize parameters for buying NFTs
        address poolAddress = proposals[proposalId].interactedPool;
        uint256 vaultValue = proposals[proposalId].value;
        uint256[] memory NFTIds = new uint[](1);
        NFTIds[0] = proposals[proposalId].NFTId;

        // purchase NFTs through a sudoswap pool
        uint256 totalCost = ISudoSwapPool(poolAddress).swapTokenForSpecificNFTs{
            value: vaultValue
        }(NFTIds, vaultValue, vaultAddress, false, vaultAddress);

        uint256 beforeBalance = address(this).balance;
        uint256 transferAmount = proposals[proposalId].value - totalCost;
        require(
            transferAmount == proposals[proposalId].value - totalCost,
            "Invalid amount"
        );
        vaultAddress.transfer(transferAmount);

        require(
            address(this).balance == beforeBalance - transferAmount,
            "Wrong balance"
        );

        // updata vault info
        proposals[proposalId].ownNFTs = true;

        return address(vault);
    }

    // create a proposal for a specific NFT
    // including data: sudoswap NFT pool address / NFT id / vault lifetime / NFT floor price / pool id
    function createProposal(
        address interactedPool,
        uint256 NFTId,
        uint256 floorPrice,
        uint256 lifetime
    ) public returns (uint256) {
        proposalCount++;
        uint256 newProposalId = proposalCount;

        ProposalInfo storage newProposal = proposals[newProposalId];

        newProposal.id = newProposalId;
        newProposal.proposer = msg.sender;
        newProposal.interactedPool = interactedPool;
        newProposal.NFTId = NFTId;
        newProposal.floorPrice = floorPrice;
        newProposal.lifetime = lifetime;
        newProposal.vaultCreated = false;

        return newProposalId;
    }

    function getProposalInfo(
        uint256 proposalId
    )
        public
        view
        checkProposalId(proposalId)
        returns (
            uint256 id,
            address interactedPool,
            uint256 NFTId,
            uint256 floorPrice,
            uint256 lifetime
        )
    {
        ProposalInfo storage p = proposals[proposalId];
        return (p.id, p.interactedPool, p.NFTId, p.floorPrice, p.lifetime);
    }

    function getProposalStatus(
        uint256 proposalId
    ) public view checkProposalId(proposalId) returns (bool status) {
        ProposalInfo storage p = proposals[proposalId];
        return p.vaultCreated;
    }

    function deposit(
        uint256 proposalId
    ) public payable checkProposalId(proposalId) returns (address) {
        require(msg.value != 0, "Amount is 0");

        uint256 amount = msg.value;
        address vaultAddr;

        proposalBalances[proposalId][msg.sender] += amount;
        // proposals[proposalId].balance[msg.sender] += amount;
        proposals[proposalId].value += amount;

        // if the vaule of specific vault reach the target price, the vault would be created.
        uint256 targetPrice = (proposals[proposalId].floorPrice * 15) / 10;
        if (proposals[proposalId].value >= targetPrice) {
            vaultAddr = createVault(proposalId);
        }
        return
            proposals[proposalId].value >= targetPrice ? vaultAddr : address(0);
    }

    function getBalanceCheck(
        uint256 proposalId
    ) public view checkProposalId(proposalId) returns (uint256 balance) {
        // return proposals[proposalId].balance[msg.sender];
        return proposalBalances[proposalId][msg.sender];
    }

    function updateFloorPrice(uint256 proposalId, uint256 floorPrice) public {}

    // if the prosal hasn't
    function refund(uint256 proposalId) public checkProposalId(proposalId) {
        // if the vault has been created, user cannot apply for refund
        require(
            proposals[proposalId].vaultCreated == false,
            "Vault has been created"
        );
        require(
            // proposals[proposalId].balance[msg.sender] >= 0,
            proposalBalances[proposalId][msg.sender] >= 0,
            "Iusufficient balance"
        );

        // uint256 amount = proposals[proposalId].balance[msg.sender];
        // proposals[proposalId].balance[msg.sender] = 0;
        uint256 amount = proposalBalances[proposalId][msg.sender];
        proposalBalances[proposalId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {}
}

// 改 balance
