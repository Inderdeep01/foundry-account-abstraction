// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {ZkMinimalAccount} from "src/zksync/ZkMinimalAccount.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";

contract ZkMinimalAccountTest is Test{
    ZkMinimalAccount minimalAccount;
    ERC20Mock usdc;
    uint256 public constant AMOUNT = 1e18;
    bytes32 constant EMPTY_BYTES32 = bytes32(0);
    address constant ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public{
        minimalAccount = new ZkMinimalAccount();
        minimalAccount.transferOwnership(ANVIL_ACCOUNT);
        usdc = new ERC20Mock();
        vm.deal(address(minimalAccount), 1e18);
    }

    function testZkOwnerCanExecuteCommands() public{
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        Transaction memory tx = _createUnsignedTransaction(minimalAccount.owner(), 0x71, dest, value, functionData);
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.executeTransaction(EMPTY_BYTES32, EMPTY_BYTES32, tx);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testZkValidateTransaction() public{
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        Transaction memory txn = _createUnsignedTransaction(minimalAccount.owner(), 0x71, dest, value, functionData);
        txn = _signTransaction(txn);
        // Act
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        bytes4 magic = minimalAccount.validateTransaction(EMPTY_BYTES32, EMPTY_BYTES32, txn);
        // Assert
        assertEq(magic, ACCOUNT_VALIDATION_SUCCESS_MAGIC);
    }

    /// HELPERS
    function _signTransaction(Transaction memory transaction) internal view returns(Transaction memory){
        bytes32 unsignedTxHash = MemoryTransactionHelper.encodeHash(transaction);
        uint256 ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ANVIL_KEY, unsignedTxHash);
        transaction.signature = abi.encodePacked(r, s, v);
        return transaction;
    }

    function _createUnsignedTransaction(address from, uint8 txType, address to, uint256 value, bytes memory data) internal view returns(Transaction memory){
        uint256 nonce = vm.getNonce(address(minimalAccount));
        bytes32[] memory factoryDeps = new bytes32[](0);
        return Transaction({
            txType : txType,
            from : uint256(uint160(from)),
            to : uint256(uint160(to)),
            gasLimit : 16777216,
            gasPerPubdataByteLimit : 16777216,
            maxFeePerGas : 16777216,
            maxPriorityFeePerGas : 16777216,
            paymaster : 0,
            nonce : nonce,
            value : value,
            reserved : [uint256(0), uint256(0), uint256(0), uint256(0)],
            data : data,
            signature : hex"",
            factoryDeps : factoryDeps,
            paymasterInput : hex"",
            reservedDynamic : hex""
        });
    }
}