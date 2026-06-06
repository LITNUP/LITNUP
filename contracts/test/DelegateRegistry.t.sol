// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {DelegateRegistry} from "../src/DelegateRegistry.sol";

contract DelegateRegistryTest is Test {
    DelegateRegistry reg;
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address carol = makeAddr("carol");

    bytes32 VOTE;
    bytes32 CLAIM;

    function setUp() public {
        reg = new DelegateRegistry(admin);
        VOTE = reg.CLASS_VOTE();
        CLAIM = reg.CLASS_CLAIM();
    }

    function test_setDelegate_happyPath() public {
        vm.prank(alice);
        reg.setDelegate(VOTE, bob);
        assertEq(reg.delegateOf(alice, VOTE), bob);
    }

    function test_setDelegate_unknownClassReverts() public {
        bytes32 unknown = keccak256("unknown");
        vm.prank(alice);
        vm.expectRevert(DelegateRegistry.UnknownClass.selector);
        reg.setDelegate(unknown, bob);
    }

    function test_setDelegate_noChangeReverts() public {
        vm.prank(alice);
        reg.setDelegate(VOTE, bob);
        vm.prank(alice);
        vm.expectRevert(DelegateRegistry.NoChange.selector);
        reg.setDelegate(VOTE, bob);
    }

    function test_clearAll_resetsBothClasses() public {
        vm.startPrank(alice);
        reg.setDelegate(VOTE, bob);
        reg.setDelegate(CLAIM, carol);
        reg.clearAll();
        vm.stopPrank();
        assertEq(reg.delegateOf(alice, VOTE), address(0));
        assertEq(reg.delegateOf(alice, CLAIM), address(0));
    }

    function test_enableClass_governanceOnly() public {
        bytes32 customClass = keccak256("custom");
        vm.expectRevert();
        reg.enableClass(customClass);

        vm.prank(admin);
        reg.enableClass(customClass);
        assertTrue(reg.allowedClass(customClass));
    }

    function test_disableClass_alreadyDelegatedStaysIntact() public {
        // Alice delegates while CLASS_VOTE is enabled
        vm.prank(alice);
        reg.setDelegate(VOTE, bob);
        // Admin disables the class
        vm.prank(admin);
        reg.disableClass(VOTE);
        assertFalse(reg.allowedClass(VOTE));
        // Existing delegation remains in storage
        assertEq(reg.delegateOf(alice, VOTE), bob);
        // But new sets revert
        vm.prank(carol);
        vm.expectRevert(DelegateRegistry.UnknownClass.selector);
        reg.setDelegate(VOTE, bob);
    }

    function test_delegatorsOf_returnsRecord() public {
        vm.prank(alice);
        reg.setDelegate(VOTE, bob);
        vm.prank(carol);
        reg.setDelegate(VOTE, bob);
        address[] memory list = reg.delegatorsOf(bob, VOTE);
        assertEq(list.length, 2);
        assertEq(list[0], alice);
        assertEq(list[1], carol);
    }
}
