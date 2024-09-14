// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    // ERRORS
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();
    error ZkMinimalAccount__NotFromBootLoaderOrOwner();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__FailedToPay();
    error ZkMinimalAccount__InvalidTransaction();

    // MODIFIERS
    modifier fromBootLoaderOnly(){
        if(msg.sender != BOOTLOADER_FORMAL_ADDRESS){
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    modifier fromBootLoaderOrOwnerOnly(){
        if(msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()){
            revert ZkMinimalAccount__NotFromBootLoaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender){

    }

    // EXTERNAL FUNCTIONS

    receive() external payable{}

    /// @notice must increase the nonce
    /// @notice must validate the tx
    /// @notice also check if we have enough money in this wallet
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
    external
    payable
    fromBootLoaderOnly
    returns (bytes4 magic){
        return _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
    external
    fromBootLoaderOrOwnerOnly
    payable{
        return _executeTransaction(_transaction);
    }

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable{
        bytes4 validationResult = _validateTransaction(_transaction);
        if(validationResult == ACCOUNT_VALIDATION_SUCCESS_MAGIC){
            _executeTransaction(_transaction);
        } else {
            revert ZkMinimalAccount__InvalidTransaction();
        }
    }

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
    external
    payable{
        bool success = _transaction.payToTheBootloader();
        if(!success){
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
    external
    payable{}

    // INTERNAL FUNCTIONS
    function _validateTransaction(Transaction calldata _transaction) internal returns(bytes4 magic){
        // Increament the nonce
        SystemContractsCaller.systemCallWithPropagatedRevert(uint32(gasleft()), address(NONCE_HOLDER_SYSTEM_CONTRACT), 0, abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, _transaction.nonce));
        // Check for the fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if(totalRequiredBalance > address(this).balance){
            revert ZkMinimalAccount__NotEnoughBalance();
        }
        // Check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if(isValidSigner){
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        // Return Magic number
        return magic;
    }

    function _executeTransaction(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if(to == address(DEPLOYER_SYSTEM_CONTRACT)){
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        }else {
            bool success;
            assembly{
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if(!success){
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
