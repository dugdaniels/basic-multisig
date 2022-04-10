// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "src/BasicMultisig.sol";

interface CheatCodes {
    function deal(address who, uint256 newBalance) external;

    function prank(address) external;

    function expectCall(address where, bytes calldata data) external;

    function expectRevert(bytes memory msg) external;

    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData
    ) external;
}

contract BasicMultisigTest is DSTest {
    BasicMultisig multisig;
    address[] owners = [address(1), address(2), address(3)];
    uint256 required = 2;

    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    function setUp() public {
        multisig = new BasicMultisig(owners, required);
    }
}

contract ConstructorTests is BasicMultisigTest {
    function testSetsOwners() public {
        for (uint256 i = 0; i < owners.length; i++) {
            assertEq(multisig.owners(i), owners[i]);
        }
    }

    function testSetsIsOwner() public {
        for (uint256 i = 0; i < owners.length; i++) {
            assertTrue(multisig.isOwner(owners[i]));
        }
    }

    function testSetsRequired() public {
        assertEq(multisig.required(), required);
    }
}

contract SubmitTransactionTests is BasicMultisigTest {
    function nonOwnerSubmission() public {
        address recipient = address(0);
        uint256 value = 0;
        bytes memory callData;
        cheats.expectRevert(bytes("Only the owner can submit transactions"));
        cheats.prank(address(4));
        multisig.submitTransaction(recipient, value, callData);
    }

    function testZeroAddressRecipient() public {
        address recipient = address(0);
        uint256 value = 0;
        bytes memory callData;
        cheats.expectRevert(bytes("Recipient cannot be the zero address"));
        cheats.prank(address(1));
        multisig.submitTransaction(recipient, value, callData);
    }
}

contract AddTransactionTests is BasicMultisigTest {
    address recipient = address(1);
    uint256 value = 1;
    bytes callData = bytes("Calldata");

    event Submission(uint256 indexed transactionId);

    function submitTransaction() internal {
        cheats.prank(address(1));
        multisig.submitTransaction(recipient, value, callData);
    }

    function testAddTransaction() public {
        uint256 id = multisig.transactionCount();
        submitTransaction();

        (
            address recipient_,
            uint256 value_,
            bytes memory callData_,
            ,
            bool executed_
        ) = multisig.transactions(id);

        assertEq(recipient_, recipient);
        assertEq(value_, value);
        checkEq0(callData_, callData);
        assertTrue(!executed_);
    }

    function testAddTransactionEvent() public {
        uint256 id = multisig.transactionCount();
        cheats.expectEmit(true, false, false, false);
        emit Submission(id);
        submitTransaction();
    }
}

contract ApproveTransactionTests is BasicMultisigTest {
    event ApproveTransaction(
        uint256 indexed transactionId,
        address indexed approver
    );

    function submitTransaction() private returns (uint256 _id) {
        address recipient = address(1);
        uint256 value = 0;
        bytes memory callData;
        cheats.prank(address(1));
        _id = multisig.submitTransaction(recipient, value, callData);
    }

    function testOwnersMustApprove() public {
        uint256 id = submitTransaction();
        cheats.expectRevert(bytes("Only owners can approve transactions"));
        cheats.prank(address(4));
        multisig.approveTransaction(id);
    }

    function testOwnerCanApprove() public {
        uint256 id = submitTransaction();
        (, , , uint256 approvalCount, ) = multisig.transactions(id);
        assertEq(approvalCount, 1);

        cheats.prank(address(2));
        multisig.approveTransaction(id);
        (, , , approvalCount, ) = multisig.transactions(id);
        assertEq(approvalCount, 2);
    }

    function testCannontApproveExecutedTransaction() public {
        uint256 id = submitTransaction();
        // Submitter automatically approves
        cheats.prank(address(2));
        multisig.approveTransaction(id);
        // Transaction is executed after two approvals
        cheats.prank(address(3));
        cheats.expectRevert(bytes("Transaction has already been executed"));
        multisig.approveTransaction(id);
    }

    function testCannotApproveTwice() public {
        uint256 id = submitTransaction();
        cheats.prank(address(1));
        cheats.expectRevert(
            bytes("You have already approved this transaction")
        );
        multisig.approveTransaction(id);
    }

    function testApproveTransactionEvent() public {
        uint256 id = submitTransaction();
        address approver = address(2);
        cheats.expectEmit(true, true, false, false);
        emit ApproveTransaction(id, approver);
        cheats.prank(approver);
        multisig.approveTransaction(id);
    }
}

contract ExecuteTransactionTest is BasicMultisigTest {
    address recipient = address(1);
    uint256 value = 1;
    bytes callData = bytes("Calldata");

    event ApproveTransaction(
        uint256 indexed transactionId,
        address indexed approver
    );
    event Execute(uint256 transactionId);

    function submitTransaction() internal returns (uint256) {
        cheats.deal(address(multisig), 1);
        cheats.prank(address(1));
        return multisig.submitTransaction(recipient, value, callData);
    }

    function testExecutesTransaction() public {
        uint256 transactionId = submitTransaction();

        // Check starting balances
        assertEq(address(multisig).balance, 1);
        assertEq(recipient.balance, 0);

        // 2nd approval to trigger execution
        cheats.expectCall(address(1), callData);
        cheats.prank(address(2));
        multisig.approveTransaction(transactionId);

        // Check balances after execution
        assertEq(address(multisig).balance, 0);
        assertEq(recipient.balance, 1);
    }

    function testExecuteEvent() public {
        address approver = address(2);
        uint256 transactionId = submitTransaction();

        // Expect the approve event...
        cheats.expectEmit(true, true, false, false);
        emit ApproveTransaction(transactionId, approver);

        // then the execute event
        cheats.expectEmit(true, false, false, false);
        emit Execute(transactionId);

        cheats.prank(approver);
        multisig.approveTransaction(transactionId);
    }
}
