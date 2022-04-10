// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

contract BasicMultisig {
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public required;
    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public approvals;

    event Submission(uint256 indexed transactionId);
    event ApproveTransaction(
        uint256 indexed transactionId,
        address indexed approver
    );
    event Execute(uint256 transactionId);
    event ExecuteError(uint256 transactionId);

    struct Transaction {
        address recipient;
        uint256 value;
        bytes callData;
        uint256 approvalCount;
        bool executed;
    }

    constructor(address[] memory _owners, uint256 _required) {
        require(_required > 0, "Required must be greater than 0");
        require(
            _required <= _owners.length,
            "Required greater than number of owners"
        );

        owners = _owners;
        for (uint256 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
        required = _required;
    }

    function submitTransaction(
        address _recipient,
        uint256 _value,
        bytes memory _callData
    ) public returns (uint256 _transactionId) {
        require(isOwner[msg.sender], "Only owners can submit transactions");
        require(
            _recipient != address(0),
            "Recipient cannot be the zero address"
        );
        _transactionId = addTransaction(_recipient, _value, _callData);
    }

    function addTransaction(
        address _recipient,
        uint256 _value,
        bytes memory _callData
    ) private returns (uint256 _transactionId) {
        _transactionId = transactionCount;
        transactions[_transactionId] = Transaction({
            recipient: _recipient,
            value: _value,
            callData: _callData,
            approvalCount: 0,
            executed: false
        });

        transactionCount++;
        emit Submission(_transactionId);

        approveTransaction(_transactionId);
    }

    function approveTransaction(uint256 _transactionId) public {
        Transaction storage transaction = transactions[_transactionId];

        require(isOwner[msg.sender], "Only owners can approve transactions");
        require(
            !approvals[_transactionId][msg.sender],
            "You have already approved this transaction"
        );
        require(!transaction.executed, "Transaction has already been executed");

        approvals[_transactionId][msg.sender] = true;
        transaction.approvalCount++;
        emit ApproveTransaction(_transactionId, msg.sender);
        executeTransaction(_transactionId);
    }

    function executeTransaction(uint256 _transactionId) internal {
        Transaction storage transaction = transactions[_transactionId];

        if (transaction.approvalCount >= required) {
            transaction.executed = true;
            (bool success, ) = (transaction.recipient).call{
                value: transaction.value
            }(transaction.callData);
            if (success) {
                emit Execute(_transactionId);
            } else {
                emit ExecuteError(_transactionId);
                transaction.executed = false;
            }
        }
    }
}
