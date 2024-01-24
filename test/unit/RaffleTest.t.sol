//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test{
    /** Events */
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            ,
            gasLane,
            interval,
            entranceFee,
            callbackGasLimit,
            vrfCoordinator,
            ,
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRafflerevertIfYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle_NotEnoughEthSent.selector);
        // Act
        raffle.enterRaffle();
        // Assert
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assert(raffle.getPlayers(0) == PLAYER);
    }

    function testEmitEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER); // we expect to emit this event
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpKeep("");
        vm.expectRevert(Raffle.Raffle_NotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // Check Upkeep
    function testCheckUpkeepReturnsFalseIfIthasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
    // Arrange
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);
    raffle.performUpKeep("");
    // Act
    (bool upkeepNeeded, ) = raffle.checkUpKeep("");
    // Assert
    assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        assert(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public{
        // Arrange make sure checkUpkeep is true
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act
        raffle.performUpKeep("");
    }
    
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public{
        // Arrange make sure checkUpkeep is false
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Act Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpKeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed{
        // Act
        vm.recordLogs(); // Record all logs and save them
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // First event should be from RandomWordsRequested on VRFCoordinatorV2Mock.sol
        // Second event should be from RequestedRaffleWinner on Raffle.sol
        bytes32 requestId = entries[1].topics[1];
        // Zero topic refers to the event
        // First topic refers to the requestId
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Assert
        assert(uint256(requestId) > 0);
        assert(raffleState == Raffle.RaffleState.CALCULATING);
    }

    // FullfillRandomWords

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    // Fuzz test
    function testFullfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) 
        public raffleEnteredAndTimePassed skipFork
    {
        // Arrange
        vm.expectRevert("nonexistent request");
        // Pretent to be the vrfCoordinator
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    // Full test
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() 
        public raffleEnteredAndTimePassed skipFork
    {
        // Enter the raffle, be the ChainLinkVRF, and fulfill the request, pick a winner and send money
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        vm.recordLogs(); // Record all logs and save them
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        console.log(address(raffle).balance);
        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        // Pretent to be the ChainLinkVRF
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId), 
            address(raffle)
        );

        uint256 prize = entranceFee * (additionalEntrants + 1);
        // Assert
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
    }

}