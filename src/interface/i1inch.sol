// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILimitOrderProtocol {
    struct Order {
        uint256 salt;
        uint256 maker; // Address encoded as uint256
        uint256 receiver; // Address encoded as uint256
        uint256 makerAsset; // Address encoded as uint256
        uint256 takerAsset; // Address encoded as uint256
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 makerTraits;
    }

    function fillOrder(Order memory order, bytes32 r, bytes32 vs, uint256 amount, uint256 takerTraits)
        external
        payable
        returns (uint256, uint256, bytes32);

    function fillOrderArgs(
        Order memory order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits,
        bytes memory args
    ) external payable returns (uint256, uint256, bytes32);

    function fillContractOrder(Order memory order, bytes memory signature, uint256 amount, uint256 takerTraits)
        external
        returns (uint256, uint256, bytes32);

    function fillContractOrderArgs(
        Order memory order,
        bytes memory signature,
        uint256 amount,
        uint256 takerTraits,
        bytes memory args
    ) external returns (uint256, uint256, bytes32);

    function hashOrder(Order memory order) external view returns (bytes32);

    function cancelOrder(uint256 makerTraits, bytes32 orderHash) external;

    function bitsInvalidateForOrder(uint256 makerTraits, uint256 additionalMask) external;

    function remainingInvalidatorForOrder(address maker, bytes32 orderHash) external view returns (uint256);

    function rawRemainingInvalidatorForOrder(address maker, bytes32 orderHash) external view returns (uint256);

    function simulate(address target, bytes calldata data) external;
}

interface IOrderMixin {
    struct Order {
        uint256 salt;
        uint256 maker;
        uint256 receiver;
        uint256 makerAsset;
        uint256 takerAsset;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 makerTraits;
    }
}

interface IPreInteraction {
    function preInteraction(
        IOrderMixin.Order memory order,
        bytes memory extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingAmount,
        bytes memory extraData
    ) external;
}

interface IPostInteraction {
    function postInteraction(
        IOrderMixin.Order memory order,
        bytes memory extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingAmount,
        bytes memory extraData
    ) external;
}
