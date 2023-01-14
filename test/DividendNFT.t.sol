// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DividendNFT} from "../src/DividendNFT.sol";
import {Helper} from "./Helper.sol";

contract DividendNFTTest is Test, Helper {
    DividendNFT public dividendNFT;
    address public self = address(this);

    address public user = makeAddr("user");
    address public anotherUser = makeAddr("anotherUser");

    event DividendsComputed(
        uint256 indexed computeDate,
        uint256 dividendPerShare,
        uint256 nextComputeRewardsDate
    );

    function setUp() public {
        dividendNFT = new DividendNFT("NFT", "NFT", "filename.jpg");
    }

    function testInit() public {
        assertEq(dividendNFT.getBalance(), 0);
        assertEq(dividendNFT.mintPrice(), 0.00001 ether);
        assertEq(dividendNFT.phase(), 0);
        assertEq(dividendNFT.magnifiedDividendPerShare(), 0);
        assertEq(
            dividendNFT.nextComputeRewardsDate(),
            block.timestamp + dividendNFT.PERIOD()
        );
    }

    function testOwner() public {
        assertEq(dividendNFT.owner(), self);
    }

    function testOwnerInitBalance() public {
        assertEq(dividendNFT.balanceOf(self), 50000);
    }

    function testNFTUrl() public {
        //console.log(dividendNFT.tokenURI(2));
        assertTrue(strcmp("ipfs://filename.jpg", dividendNFT.tokenURI(2)));
    }

    function testReceive() public {
        uint256 phaseBefore = dividendNFT.phase();
        uint256 recalcDivsDate = dividendNFT.nextComputeRewardsDate();
        (bool success, ) = payable(address(dividendNFT)).call{value: 1 ether}(
            ""
        );
        assertTrue(success);
        assertEq(dividendNFT.getBalance(), 1 ether);
        assertEq(dividendNFT.phase(), phaseBefore);
        assertEq(recalcDivsDate, dividendNFT.nextComputeRewardsDate());
    }

    function testSetMintPrice() public {
        dividendNFT.setMintPrice(1 ether);
        assertEq(dividendNFT.mintPrice(), 1 ether);
    }

    function testSetMintPriceNotAnOwner() public {
        uint256 beforePrice = dividendNFT.mintPrice();
        hoax(user);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        dividendNFT.setMintPrice(1 ether);
        assertEq(dividendNFT.mintPrice(), beforePrice);
    }

    function testMint() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);
        // Receiver receiver = new Receiver();
        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);
    }

    function testMintVary(address user_, uint256 quantity_) public {
        vm.assume(user_ != address(0));
        vm.assume(quantity_ < 50_000 && quantity_ > 0);
        uint256 beforeBalance = dividendNFT.balanceOf(user_);
        // Receiver receiver = new Receiver();
        startHoax(user_);
        dividendNFT.mint{value: quantity_ * dividendNFT.mintPrice()}(quantity_);
        assertEq(dividendNFT.balanceOf(user_), beforeBalance + quantity_);
    }

    function testMint10_000() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);
        // Receiver receiver = new Receiver();
        startHoax(user);
        dividendNFT.mint{value: 10_000 * dividendNFT.mintPrice()}(10_000);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10_000);
    }

    function testNoRewards() public {
        vm.expectRevert(DividendNFT.NoRewards.selector);
        dividendNFT.withdrawRewards();
        dividendNFT.getAllowedWithdrawAmount();
        assertEq(dividendNFT.getAllowedWithdrawAmount(), 0);
    }

    function testDividendsComputed() public {
        vm.expectEmit(true, true, true, true);
        uint256 phaseBefore = dividendNFT.phase();
        uint256 timestampBefore = block.timestamp;
        vm.warp(block.timestamp + dividendNFT.PERIOD() + 1);

        (bool success, ) = payable(address(dividendNFT)).call{value: 1 ether}(
            ""
        );

        assertTrue(success);
        assertEq(dividendNFT.getBalance(), 1 ether);
        assertEq(dividendNFT.phase(), phaseBefore + 1);
        assertEq(block.timestamp, timestampBefore + dividendNFT.PERIOD() + 1);

        emit DividendsComputed(
            block.timestamp,
            1 ether / dividendNFT.totalSupply(),
            block.timestamp + dividendNFT.PERIOD() - 1
        );
    }

    //1. юзер наминтил токены до рассчёта
    function testMintBeforeCompudeDivs() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);
        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(0, user);
        assertEq(earnedDivs, 0);
        assertEq(dividendNFT.magnifiedDividendPerShare(), 0);
    }

    //2. наминтил токены после рассчёта
    function testMintAfterCompudeDivs() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);
        testDividendsComputed();
        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(0, user);
        assertEq(earnedDivs, 0);

        uint256 canWithdrawUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawUser, 0);
        changePrank(self);

        uint256 canWithdrawOwner = dividendNFT.getAllowedWithdrawAmount();
        assertEq(
            canWithdrawOwner,
            (dividendNFT.magnifiedDividendPerShare() /
                dividendNFT.MAGNITUDE()) * dividendNFT.balanceOf(self)
        );
    }

    //3. получил дивы и продал
    function testWithdrawedAndTransferedToAnother() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);

        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);

        changePrank(self);
        testDividendsComputed();

        changePrank(user);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(earnedDivs, 0);

        uint256 canWithdrawUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawUser, canWithdrawAmountValue(user));

        dividendNFT.withdrawRewards();

        uint256 claimedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(claimedDivs, canWithdrawUser);

        assertEq(dividendNFT.phase(), 1);
        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 0);

        for (uint256 i = 0; i < 10; i++) {
            dividendNFT.transferFrom(user, anotherUser, 50_000 + i);
        }

        assertEq(dividendNFT.balanceOf(user), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 10);

        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), claimedDivs);
        assertEq(dividendNFT.claimedAtPhase(1, user), claimedDivs);

        changePrank(anotherUser);
        uint256 canWithdrawAnotherUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawAnotherUser, 0);
    }

    //4. не получил дивы и продал
    function testNoWithdrawedAndTransferedToAnother() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);

        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);

        changePrank(self);
        testDividendsComputed();

        changePrank(user);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(earnedDivs, 0);

        uint256 canWithdrawUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawUser, canWithdrawAmountValue(user));

        uint256 claimedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(claimedDivs, 0);

        assertEq(dividendNFT.phase(), 1);
        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 0);

        for (uint256 i = 0; i < 10; i++) {
            dividendNFT.transferFrom(user, anotherUser, 50_000 + i);
        }

        assertEq(dividendNFT.balanceOf(user), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 10);

        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.claimedAtPhase(1, user), 0);

        changePrank(anotherUser);
        uint256 canWithdrawAnotherUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawAnotherUser, canWithdrawAmountValue(anotherUser));

        dividendNFT.withdrawRewards();

        assertEq(
            dividendNFT.claimedAtPhase(1, anotherUser),
            canWithdrawAnotherUser
        );
        assertEq(dividendNFT.claimedAtPhase(1, user), 0);
    }

    //5. продал часть не получив дивы
    function testNoWithdrawedPartAndTransferedToAnother() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);

        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);

        changePrank(self);
        testDividendsComputed();

        changePrank(user);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(earnedDivs, 0);

        uint256 canWithdrawUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawUser, canWithdrawAmountValue(user));

        uint256 claimedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(claimedDivs, 0);

        assertEq(dividendNFT.phase(), 1);
        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 0);

        for (uint256 i = 0; i < 5; i++) {
            dividendNFT.transferFrom(user, anotherUser, 50_000 + i);
        }

        assertEq(dividendNFT.balanceOf(user), 5);
        assertEq(dividendNFT.balanceOf(anotherUser), 5);

        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.claimedAtPhase(1, user), 0);

        changePrank(anotherUser);
        uint256 canWithdrawAnotherUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawAnotherUser, canWithdrawAmountValue(anotherUser));

        dividendNFT.withdrawRewards();

        assertEq(
            dividendNFT.claimedAtPhase(1, anotherUser),
            canWithdrawAnotherUser
        );
        assertEq(dividendNFT.claimedAtPhase(1, user), 0);
    }

    //6. продал часть получив дивы
    function testWithdrawedAndPartTransferedToAnother() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);

        startHoax(user);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 10);

        changePrank(self);
        testDividendsComputed();

        changePrank(user);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(earnedDivs, 0);

        uint256 canWithdrawUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawUser, canWithdrawAmountValue(user));

        uint256 claimedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(claimedDivs, 0);

        assertEq(dividendNFT.phase(), 1);
        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 0);

        dividendNFT.withdrawRewards();

        for (uint256 i = 0; i < 5; i++) {
            dividendNFT.transferFrom(user, anotherUser, 50_000 + i);
        }

        assertEq(dividendNFT.balanceOf(user), 5);
        assertEq(dividendNFT.balanceOf(anotherUser), 5);

        assertEq(
            dividendNFT.claimedAtPhase(1, anotherUser),
            canWithdrawUser / 2
        );
        assertEq(dividendNFT.claimedAtPhase(1, user), canWithdrawUser);

        changePrank(anotherUser);
        uint256 canWithdrawAnotherUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawAnotherUser, 0);

        assertEq(
            dividendNFT.claimedAtPhase(1, anotherUser),
            canWithdrawUser / 2
        );
        assertEq(dividendNFT.claimedAtPhase(1, user), canWithdrawUser);
    }

    //6. продал часть получив дивы, другой выводит
    function testWithdrawedAndPartTransferedToAnotherThatWithdraws() public {
        uint256 beforeBalance = dividendNFT.balanceOf(user);

        startHoax(user);
        dividendNFT.mint{value: 20 * dividendNFT.mintPrice()}(20);
        assertEq(dividendNFT.balanceOf(user), beforeBalance + 20);
        vm.stopPrank();
        changePrank(anotherUser);
        deal(anotherUser, 1 ether);
        dividendNFT.mint{value: 10 * dividendNFT.mintPrice()}(10);

        changePrank(self);
        testDividendsComputed();

        changePrank(user);

        uint256 earnedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(earnedDivs, 0);

        uint256 canWithdrawUser = dividendNFT.getAllowedWithdrawAmount();
        assertEq(canWithdrawUser, canWithdrawAmountValue(user));

        uint256 claimedDivs = dividendNFT.claimedAtPhase(1, user);
        assertEq(claimedDivs, 0);

        assertEq(dividendNFT.phase(), 1);
        assertEq(dividendNFT.claimedAtPhase(1, anotherUser), 0);
        assertEq(dividendNFT.balanceOf(anotherUser), 10);

        dividendNFT.withdrawRewards();

        for (uint256 i = 0; i < 10; i++) {
            dividendNFT.transferFrom(user, anotherUser, 50_000 + i);
        }

        assertEq(dividendNFT.balanceOf(user), 10);
        assertEq(dividendNFT.balanceOf(anotherUser), 20);

        assertEq(dividendNFT.claimedAtPhase(1, user), canWithdrawUser);

        changePrank(anotherUser);
        uint256 canWithdrawAnotherUser = dividendNFT.getAllowedWithdrawAmount();

        assertEq(
            canWithdrawAnotherUser,
            canWithdrawAmountValue(anotherUser) -
                dividendNFT.claimedAtPhase(1, anotherUser)
        );

        dividendNFT.withdrawRewards();
    }

    function canWithdrawAmountValue(address useraddress)
        private
        view
        returns (uint256)
    {
        return ((dividendNFT.magnifiedDividendPerShare() *
            dividendNFT.balanceOf(useraddress)) / dividendNFT.MAGNITUDE());
    }

    receive() external payable {}
}
