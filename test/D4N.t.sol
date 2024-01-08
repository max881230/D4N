// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "../src/Vault.sol";
import {Central} from "../src/Central.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/sudoSwapInterface.sol";

contract testFinal is Test {
    Vault public vault1;
    Vault public vault2;
    Central public central;

    uint256 mainnetFork;
    address admin = makeAddr("admin");
    address user1 = payable(makeAddr("user1"));
    address user2 = payable(makeAddr("user2"));
    address user3 = payable(makeAddr("user3"));

    address BAYCPool = 0xCed43cC307C3d5453386Ce8b06fa14fcB6457fd4;
    address BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;

    address veryFastRouter = 0x090C236B62317db226e6ae6CD4c0Fd25b7028b65;
    address vault1Addr;
    address vault2Addr;

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        mainnetFork = vm.createFork(MAINNET_RPC_URL);

        vm.selectFork(mainnetFork);
        vm.rollFork(18_532_608);
        assertEq(block.number, 18_532_608);

        vm.startPrank(admin);

        central = new Central(admin);

        deal(admin, 1000 ether);
        deal(user1, 15 ether);
        deal(user2, 15 ether);
        deal(user3, 15 ether);

        vm.stopPrank();
    }

    function testCreateProposal() public {
        vm.startPrank(user1);
        uint256 proposalId = central.createProposal(
            BAYCPool,
            BAYC,
            2483,
            30 ether,
            86_400 * 10
        );
        central.getProposalInfo(proposalId);
        central.getProposalStatus(proposalId);
        vm.stopPrank();
    }

    function testDeposit() public {
        testCreateProposal();
        vm.startPrank(user1);
        central.deposit{value: 15 ether}(1);
        assertEq(15 ether, central.getBalanceCheck(1));
        vm.stopPrank();
    }

    function testRefund() public {
        testDeposit();
        vm.startPrank(user1);
        central.refund(1);
        assertEq(user1.balance, 15 ether);
        vm.stopPrank();
    }

    function testCreateVaultAndBuyNft() public {
        testDeposit();
        vm.prank(user2);
        central.deposit{value: 15 ether}(1);
        vm.startPrank(user3);
        vault1Addr = central.deposit{value: 15 ether}(1);
        assertEq(true, central.getProposalStatus(1));
        // console2.log(vault1Addr.balance);

        (, , address interactedNft, , , ) = central.getProposalInfo(1);

        assertEq(IERC721(interactedNft).ownerOf(2483), vault1Addr);
        vm.stopPrank();
    }

    function testVaultGetBalance() public {
        testCreateVaultAndBuyNft();
        vm.startPrank(user1);
        vault1 = Vault(payable(vault1Addr));
        (, uint256 balance) = vault1.getBalance();
        assertEq(balance, 15 ether);
        vm.stopPrank();
    }

    function testMintVaultToken() public {
        testCreateVaultAndBuyNft();
        vault1 = Vault(payable(vault1Addr));
        vm.prank(user1);
        vault1.mintVaultToken();
        vm.prank(user2);
        vault1.mintVaultToken();
        vm.prank(user3);
        vault1.mintVaultToken();
        assertEq(vault1.balanceOf(user1), 15 ether);
        assertEq(vault1.balanceOf(user2), 15 ether);
        assertEq(vault1.balanceOf(user3), 15 ether);
    }

    function testDelegateVote() public {
        testMintVaultToken();
        vm.prank(user1);
        vault1.delegate(user1);
        vm.prank(user2);
        vault1.delegate(user2);
        vm.prank(user3);
        vault1.delegate(user3);

        assertEq(vault1.getVotes(user1), 15 ether);
        assertEq(vault1.getVotes(user2), 15 ether);
        assertEq(vault1.getVotes(user3), 15 ether);
    }

    function testCreateVaultProposal() public {
        testDelegateVote();
        vm.rollFork(18_532_609);
        vm.startPrank(user1);
        string memory purpose = "sell";
        vault1.propose(purpose, 1 ether);
        vm.stopPrank();
    }

    function testVoteProposal() public {
        testCreateVaultProposal();
        vm.prank(user1);
        // proposal is under reviewing
        vm.expectRevert();
        vault1.vote(1, 1);

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(user1);
        vault1.vote(1, 1);
        // cannot vote for twice
        vm.expectRevert();
        vault1.vote(1, 1);
        vm.stopPrank();

        vm.prank(user2);
        vault1.vote(1, 1);
        vm.prank(user3);
        vault1.vote(1, 0);

        (uint256 forVotes, uint256 againstVotes, , ) = vault1.getProposalStatus(
            1
        );
        assertEq(forVotes, 30 ether);
        assertEq(againstVotes, 15 ether);
    }

    function testExecuteProposal() public {
        testVoteProposal();
        console2.log(address(vault1).balance);

        vm.startPrank(user1);
        // vote is still on-going
        vm.expectRevert();
        vault1.executeVote(1);

        vm.warp(block.timestamp + 2 days);
        vault1.executeVote(1);

        console2.log(address(vault1).balance);
        // proposal has been executed
        vm.expectRevert();
        vault1.executeVote(1);
        vm.stopPrank();
    }

    function testgetVaultInfo() public {
        testCreateVaultAndBuyNft();
        vault1 = Vault(payable(vault1Addr));
        vault1.getVaultInfo();
    }

    function testGetVaultRemainingTime() public {
        testCreateVaultAndBuyNft();
        vault1 = Vault(payable(vault1Addr));
        vault1.getVaultRemainingTime();
    }

    function testSudoSwapBuyNFT() public {
        vm.startPrank(admin);
        assertEq(admin.balance, 1000 ether);
        uint256[] memory value = new uint[](1);
        value[0] = 2483;

        uint256 cost = ISudoSwapPool(BAYCPool).swapTokenForSpecificNFTs{
            value: 40 ether
        }(value, 40 ether, admin, false, admin);

        assertEq(IERC721(BAYC).ownerOf(2483), admin);

        // console2.log(admin.balance);
        // console2.log(cost);
        vm.stopPrank();
    }

    function testSudoSwapSellNFT() public {
        testSudoSwapBuyNFT();
        vm.startPrank(admin);
        // console2.log(admin.balance);
        uint256[] memory nftIds = new uint[](1);
        nftIds[0] = 2483;

        IERC721(BAYC).approve(veryFastRouter, 2483);
        uint256[] memory minExpectedOutputPerNumNFTs = new uint[](1);
        minExpectedOutputPerNumNFTs[0] = 25 ether;

        ISudoSwapPool.Order memory swapOrder;
        ISudoSwapPool.BuyOrderWithPartialFill[] memory buyOrders;
        ISudoSwapPool.SellOrderWithPartialFill[]
            memory sellOrders = new ISudoSwapPool.SellOrderWithPartialFill[](1);

        sellOrders[0].pair = LSSVMPair(BAYCPool);
        sellOrders[0].isETHSell = true;
        sellOrders[0].isERC721 = true;
        sellOrders[0].nftIds = nftIds;
        sellOrders[0].doPropertyCheck = false;
        sellOrders[0].propertyCheckParams = "0x";
        sellOrders[0].expectedSpotPrice = 25 ether;
        sellOrders[0].minExpectedOutput = 25 ether;
        sellOrders[0].minExpectedOutputPerNumNFTs = minExpectedOutputPerNumNFTs;

        swapOrder = ISudoSwapPool.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(admin),
            nftRecipient: admin,
            recycleETH: false
        });
        ISudoSwapPool(veryFastRouter).swap(swapOrder);
        // console2.log(admin.balance);
        vm.stopPrank();
    }
}
