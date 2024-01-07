// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "../src/VaultDelegate.sol";
import {Govern} from "../src/GovDelegate.sol";
import {Central} from "../src/Central.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/sudoSwapInterface.sol";

contract testFinal is Test {
    Vault public vault1;
    Vault public vault2;
    Govern public govern;
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
            2483,
            30 ether,
            10
        );
        central.getProposalInfo(proposalId);
        central.getProposalStatus(proposalId);
        vm.stopPrank();
    }

    // function testProposalWithError() public {
    //     vm.startPrank(user1);
    //     uint256 proposalId = central.createProposal(
    //         BAYCPool,
    //         2483,
    //         30 ether,
    //         10
    //     );
    //     vm.expectRevert();
    //     central.getProposalInfo(0);
    //     vm.expectRevert();
    //     central.getProposalStatus(0);
    //     vm.stopPrank();
    // }

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

    function testCreateVault() public {
        testDeposit();
        vm.startPrank(user1);
        vault1Addr = central.deposit{value: 20 ether}(1);
        assertEq(true, central.getProposalStatus(1));
        console2.log(vault1Addr.balance);
        vm.stopPrank();
    }

    function testBuyNFT() public {
        vm.startPrank(user1);
        assertEq(user1.balance, 1000 ether);
        // mint
        uint256[] memory value = new uint[](3);
        value[0] = 2483;
        value[1] = 2974;
        value[2] = 433;

        uint256 cost = ISudoSwapPool(BAYCPool).swapTokenForSpecificNFTs{
            value: 112864715998456310682
        }(value, 112864715998456310682, user1, false, user1);

        // assertEq(IERC721(BAYC).ownerOf(2483), user1);
        // assertEq(IERC721(BAYC).ownerOf(2974), user1);
        // assertEq(IERC721(BAYC).ownerOf(433), user1);

        console2.log(user1.balance);
        console2.log(cost);
        vm.stopPrank();
    }

    function testSellNFT() public {
        testBuyNFT();
        vm.startPrank(user1);
        uint256[] memory nftIds = new uint[](1);
        nftIds[0] = 2483;

        // IERC721(BAYC).approve(BAYCPool, 2483);

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

    function testVaultGetBalance() public {
        testCreateVault();
        vm.startPrank(user1);
        vault1 = Vault(payable(vault1Addr));
        (uint256 id, uint256 balance) = vault1.getBalance();
        assertEq(balance, 50 ether);
        // console2.log(balance);
        vm.stopPrank();
    }
}
