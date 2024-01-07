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
    address user2 = makeAddr("user2");
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
        deal(user1, 1000 ether);

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
        central.deposit{value: 30 ether}(1);
        assertEq(30 ether, central.getBalanceCheck(1));
        vm.stopPrank();
    }

    function testRefund() public {
        testDeposit();
        vm.startPrank(user1);
        central.refund(1);
        assertEq(user1.balance, 1000 ether);
        vm.stopPrank();
    }

    function testCreateVaultAndBuyNft() public {
        testDeposit();
        vm.startPrank(user1);
        vault1Addr = central.deposit{value: 20 ether}(1);
        assertEq(true, central.getProposalStatus(1));
        // console2.log(vault1Addr.balance);

        (
            uint256 id,
            address interactedPool,
            address interactedNft,
            uint256 nftId,
            uint256 floorPrice,
            uint256 lifetime
        ) = central.getProposalInfo(1);

        assertEq(IERC721(interactedNft).ownerOf(2483), vault1Addr);
        vm.stopPrank();
    }

    function testVaultGetBalance() public {
        testCreateVaultAndBuyNft();
        vm.startPrank(user1);
        vault1 = Vault(payable(vault1Addr));
        (uint256 id, uint256 balance) = vault1.getBalance();
        assertEq(balance, 50 ether);
        vm.stopPrank();
    }

    function testMintVaultToken() public {
        testCreateVaultAndBuyNft();
        vm.startPrank(user1);
        vault1 = Vault(payable(vault1Addr));
        vault1.mintVaultToken();
        vm.stopPrank();
    }

    function testCreateVaultProposal() public {
        testMintVaultToken();
        vm.startPrank(user1);
        string memory purpose = "sell";
        vault1 = Vault(payable(vault1Addr));
        vault1.propose(purpose);
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
        vm.startPrank(user1);
        assertEq(user1.balance, 1000 ether);
        uint256[] memory value = new uint[](1);
        value[0] = 2483;

        uint256 cost = ISudoSwapPool(BAYCPool).swapTokenForSpecificNFTs{
            value: 40 ether
        }(value, 40 ether, user1, false, user1);

        assertEq(IERC721(BAYC).ownerOf(2483), user1);

        console2.log(user1.balance);
        console2.log(cost);
        vm.stopPrank();
    }

    function testSudoSwapSellNFT() public {
        testSudoSwapBuyNFT();
        vm.startPrank(user1);
        uint256[] memory nftIds = new uint[](1);
        nftIds[0] = 2483;

        IERC721(BAYC).approve(veryFastRouter, 2483);
        uint256[] memory minExpectedOutputPerNumNFTs = new uint[](1);
        minExpectedOutputPerNumNFTs[0] = 30 ether;

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
        sellOrders[0].expectedSpotPrice = 30 ether;
        sellOrders[0].minExpectedOutput = 30 ether;
        sellOrders[0].minExpectedOutputPerNumNFTs = minExpectedOutputPerNumNFTs;

        swapOrder = ISudoSwapPool.Order({
            buyOrders: buyOrders,
            sellOrders: sellOrders,
            tokenRecipient: payable(user1),
            nftRecipient: user1,
            recycleETH: false
        });
        ISudoSwapPool(veryFastRouter).swap(swapOrder);

        vm.stopPrank();
    }
}
