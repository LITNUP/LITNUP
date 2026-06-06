// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";

contract MerkleAirdropTest is Test {
    LitToken token;
    MerkleAirdrop airdrop;

    address admin = makeAddr("admin");
    address sweep = makeAddr("sweep");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    bytes32 root;
    uint256 constant ALICE_AMT = 1_000 ether;
    uint256 constant BOB_AMT = 2_000 ether;

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        // Build merkle tree with 2 leaves: (0, alice, 1000), (1, bob, 2000)
        bytes32 leafA = keccak256(abi.encodePacked(uint256(0), alice, ALICE_AMT));
        bytes32 leafB = keccak256(abi.encodePacked(uint256(1), bob, BOB_AMT));
        root = leafA < leafB ? keccak256(abi.encodePacked(leafA, leafB)) : keccak256(abi.encodePacked(leafB, leafA));

        airdrop = new MerkleAirdrop(token, root, 30 days, sweep, admin);

        // Fund the airdrop contract
        vm.prank(admin);
        token.transfer(address(airdrop), ALICE_AMT + BOB_AMT);
    }

    function _proofForAlice() internal view returns (bytes32[] memory) {
        bytes32 leafB = keccak256(abi.encodePacked(uint256(1), bob, BOB_AMT));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafB;
        return proof;
    }

    function _proofForBob() internal view returns (bytes32[] memory) {
        bytes32 leafA = keccak256(abi.encodePacked(uint256(0), alice, ALICE_AMT));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafA;
        return proof;
    }

    function test_claim_happyPath() public {
        uint256 balBefore = token.balanceOf(alice);
        airdrop.claim(0, alice, ALICE_AMT, _proofForAlice());
        assertEq(token.balanceOf(alice) - balBefore, ALICE_AMT);
        assertTrue(airdrop.isClaimed(0));
    }

    function test_claim_doubleClaimReverts() public {
        airdrop.claim(0, alice, ALICE_AMT, _proofForAlice());
        vm.expectRevert(MerkleAirdrop.AlreadyClaimed.selector);
        airdrop.claim(0, alice, ALICE_AMT, _proofForAlice());
    }

    function test_claim_invalidProofReverts() public {
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(0xdead));
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        airdrop.claim(0, alice, ALICE_AMT, badProof);
    }

    function test_claim_wrongAmountReverts() public {
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        airdrop.claim(0, alice, ALICE_AMT + 1, _proofForAlice());
    }

    function test_claim_afterDeadlineReverts() public {
        vm.warp(block.timestamp + 31 days);
        vm.expectRevert(MerkleAirdrop.ClaimWindowClosed.selector);
        airdrop.claim(0, alice, ALICE_AMT, _proofForAlice());
    }

    function test_sweep_afterDeadline() public {
        // No claims; everyone forgets
        vm.warp(block.timestamp + 31 days);
        vm.prank(admin);
        airdrop.sweep();
        assertEq(token.balanceOf(sweep), ALICE_AMT + BOB_AMT);
    }

    function test_sweep_beforeDeadlineReverts() public {
        vm.prank(admin);
        vm.expectRevert(MerkleAirdrop.ClaimWindowOpen.selector);
        airdrop.sweep();
    }

    function test_bothCanClaim() public {
        airdrop.claim(0, alice, ALICE_AMT, _proofForAlice());
        airdrop.claim(1, bob, BOB_AMT, _proofForBob());
        assertEq(token.balanceOf(alice), ALICE_AMT);
        assertEq(token.balanceOf(bob), BOB_AMT);
    }
}
