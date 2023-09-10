//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ZuniSwapV2Pair.sol";
import "./Interface/IZuniSwapV2Pair.sol";

contract ZuniSwapV2Factory {
    error IdenticalAddresses();
    error PairExists();
    error ZeroAddress();

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    mapping(address => mapping(address => address)) public pairs;
    address[] public allPairs;

    //we will not check if the given token exists or not, it is up to the user to give valid ERC20 address
    function createPair(
        address tokenA,
        address tokenB
    ) public returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();

        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        if (token0 == address(0)) revert ZeroAddress();

        if (pairs[token0][token1] != address(0)) revert PairExists();

        //for CREATE2 we need the bytecode of the deployed contract and the salt.
        //we need both the constructor logic and the runtime bytecode for this.
        bytes memory bytecode = type(ZuniSwapV2Pair).creationCode;
        //salt is calculated by hashing the addresses of both the tokens, unique and constant for every pair.
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        IZuniSwapV2Pair(pair).initialize(token0, token1);

        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
