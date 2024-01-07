// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {LSSVMPair} from "lssvm/src/LSSVMPair.sol";

interface ISudoSwapPool {
    struct BuyOrderWithPartialFill {
        LSSVMPair pair;
        bool isERC721;
        uint256[] nftIds;
        uint256 maxInputAmount;
        uint256 ethAmount;
        uint256 expectedSpotPrice;
        uint256[] maxCostPerNumNFTs; // @dev This is zero-indexed, so maxCostPerNumNFTs[x] = max price we're willing to pay to buy x+1 NFTs
    }

    struct SellOrderWithPartialFill {
        LSSVMPair pair;
        bool isETHSell;
        bool isERC721;
        uint256[] nftIds;
        bool doPropertyCheck;
        bytes propertyCheckParams;
        uint128 expectedSpotPrice;
        uint256 minExpectedOutput;
        uint256[] minExpectedOutputPerNumNFTs;
    }

    struct Order {
        BuyOrderWithPartialFill[] buyOrders;
        SellOrderWithPartialFill[] sellOrders;
        address payable tokenRecipient;
        address nftRecipient;
        bool recycleETH;
    }

    function swapTokenForSpecificNFTs(
        uint256[] calldata nftIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address routerCaller
    ) external payable virtual returns (uint256);

    function swapNFTsForToken(
        uint256[] calldata nftIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external virtual returns (uint256 outputAmount);

    function swap(
        Order calldata swapOrder
    ) external payable returns (uint256[] memory results);
}
