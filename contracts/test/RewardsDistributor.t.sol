// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {RewardsDistributor} from "../src/RewardsDistributor.sol";

contract RewardsDistributorTest is Test {
    LitnupToken token;
    RewardsDistributor dist;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    bytes32 constant CHANNEL_VE = keccak256("ve-week-1");

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        dist = new RewardsDistributor(token, admin);

        vm.startPrank(admin);
        token.approve(address(dist), type(uint256).max);
        dist.registerChannel(CHANNEL_VE, "veLITNUP weekly");
        vm.stopPrank();
    }

    /// Helper: leaf encoding must match contract: keccak256(bytes.concat(keccak256(abi.encode(channelId, user, amount))))
    function _leaf(bytes32 channelId, address user, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(channelId, user, amount))));
    }

    /// Build a 2-leaf merkle tree (alice, bob) bound to CHANNEL_VE
    function _build2(address u1, uint256 a1, address u2, uint256 a2)
        internal pure returns (bytes32 root, bytes32[] memory proofA, bytes32[] memory proofB)
    {
        bytes32 leafA = _leaf(CHANNEL_VE, u1, a1);
        bytes32 leafB = _leaf(CHANNEL_VE, u2, a2);
        // sorted-pair hash convention used by OZ MerkleProof
        if (leafA < leafB) {
            root = keccak256(abi.encodePacked(leafA, leafB));
        } else {
            root = keccak256(abi.encodePacked(leafB, leafA));
        }
        proofA = new bytes32[](1);
        proofA[0] = leafB;
        proofB = new bytes32[](1);
        proofB[0] = leafA;
    }

    function test_publishAndClaim_singleEpoch() public {
        (bytes32 root, bytes32[] memory proofA, bytes32[] memory proofB)
            = _build2(alice, 100 ether, bob, 50 ether);

        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        vm.stopPrank();

        // Alice claims
        uint256 paid = dist.claim(CHANNEL_VE, alice, 100 ether, proofA);
        assertEq(paid, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);

        // Bob claims
        uint256 paid2 = dist.claim(CHANNEL_VE, bob, 50 ether, proofB);
        assertEq(paid2, 50 ether);
    }

    function test_cumulative_supersedes_priorClaim() public {
        // Epoch 1: alice = 100, bob = 50
        (bytes32 root1, bytes32[] memory proofA1,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root1, 150 ether);
        vm.stopPrank();

        dist.claim(CHANNEL_VE, alice, 100 ether, proofA1);
        assertEq(token.balanceOf(alice), 100 ether);

        // Epoch 2: alice cumulative = 250 (was 100, earned 150 more)
        (bytes32 root2, bytes32[] memory proofA2,) = _build2(alice, 250 ether, bob, 100 ether);
        vm.prank(admin);
        dist.publishRoot(CHANNEL_VE, root2, 250 ether);

        uint256 paid = dist.claim(CHANNEL_VE, alice, 250 ether, proofA2);
        assertEq(paid, 150 ether); // only the delta
        assertEq(token.balanceOf(alice), 250 ether);
    }

    function test_invalidProof_reverts() public {
        (bytes32 root,, bytes32[] memory proofB) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        vm.stopPrank();

        // Alice presents bob's proof
        vm.expectRevert(RewardsDistributor.InvalidProof.selector);
        dist.claim(CHANNEL_VE, alice, 100 ether, proofB);
    }

    function test_doubleClaim_sameEpoch_reverts() public {
        (bytes32 root, bytes32[] memory proofA,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        vm.stopPrank();

        dist.claim(CHANNEL_VE, alice, 100 ether, proofA);
        vm.expectRevert(RewardsDistributor.AlreadyFullyClaimed.selector);
        dist.claim(CHANNEL_VE, alice, 100 ether, proofA);
    }

    function test_inactiveChannel_blocksClaim() public {
        (bytes32 root, bytes32[] memory proofA,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        dist.deactivateChannel(CHANNEL_VE);
        vm.stopPrank();

        vm.expectRevert(RewardsDistributor.ChannelInactive.selector);
        dist.claim(CHANNEL_VE, alice, 100 ether, proofA);
    }

    function test_pendingClaim_view() public {
        (bytes32 root, bytes32[] memory proofA,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        vm.stopPrank();

        assertEq(dist.pendingClaim(CHANNEL_VE, alice, 100 ether), 100 ether);
        dist.claim(CHANNEL_VE, alice, 100 ether, proofA);
        assertEq(dist.pendingClaim(CHANNEL_VE, alice, 100 ether), 0);
    }

    function test_unclaimedFunds_view() public {
        (bytes32 root, bytes32[] memory proofA,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        vm.stopPrank();

        assertEq(dist.unclaimedFunds(CHANNEL_VE), 1_000 ether);
        dist.claim(CHANNEL_VE, alice, 100 ether, proofA);
        assertEq(dist.unclaimedFunds(CHANNEL_VE), 900 ether);
    }

    function test_recoverChannelFunds_afterDeactivation() public {
        (bytes32 root, bytes32[] memory proofA,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        vm.stopPrank();

        dist.claim(CHANNEL_VE, alice, 100 ether, proofA); // 100 claimed, 900 remains

        // Cannot recover while active.
        vm.prank(admin);
        vm.expectRevert(RewardsDistributor.ChannelStillActive.selector);
        dist.recoverChannelFunds(CHANNEL_VE, admin);

        vm.startPrank(admin);
        dist.deactivateChannel(CHANNEL_VE);
        uint256 before = token.balanceOf(admin);
        dist.recoverChannelFunds(CHANNEL_VE, admin);
        vm.stopPrank();
        assertEq(token.balanceOf(admin) - before, 900 ether);
    }

    function test_channelBoundLeaf_notReplayableAcrossChannels() public {
        bytes32 otherChannel = keccak256("ve-week-2");
        vm.prank(admin);
        dist.registerChannel(otherChannel, "another");

        // Build a tree valid for CHANNEL_VE, publish the SAME root on both channels.
        (bytes32 root, bytes32[] memory proofA,) = _build2(alice, 100 ether, bob, 50 ether);
        vm.startPrank(admin);
        dist.fundChannel(CHANNEL_VE, 1_000 ether);
        dist.fundChannel(otherChannel, 1_000 ether);
        dist.publishRoot(CHANNEL_VE, root, 150 ether);
        dist.publishRoot(otherChannel, root, 150 ether);
        vm.stopPrank();

        // Proof works on the bound channel...
        assertEq(dist.claim(CHANNEL_VE, alice, 100 ether, proofA), 100 ether);
        // ...but NOT on the other channel (leaf binds channelId).
        vm.expectRevert(RewardsDistributor.InvalidProof.selector);
        dist.claim(otherChannel, alice, 100 ether, proofA);
    }
}
