//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {console} from "forge-std/console.sol";

/**
 * @title A sample Raffle Contract
 * @author Edmundtcy
 * @notice This contract is for creating a raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle_NotEnoughEthSent();
    error Raffle_NotEnoughTimePassed();
    error Raffle_TransferFailed();
    error Raffle_NotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 currentBalance,
         uint256 numPlayers, 
         uint256 raffleState
    );

    /** Type declarations */
    enum RaffleState {
        OPEN,   // 0
        CALCULATING // 1
    }

    /** State Variable */
    uint16 private constant REQUEST_COMFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players; // We can pay the players
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player); // indexed parameter is called topic
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee, 
        uint256 interval, 
        address vrfCoordinator, 
        bytes32 gasLane, 
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator){ // Inherit from VRFConsumerBaseV2
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable{
        console.log("Hi Player!");
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }
        s_players.push(payable(msg.sender));
        // update storage, emit event
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation 
     * will call to see if it is time to perform upkeep
     * if it return true, then the performUpkeep function will be called
     * 
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players have entered)
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpKeep(
        bytes memory /**checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /** performData */){
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp >= i_interval);
        bool raffleIsOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = (address(this).balance > 0);
        bool hasPlayers = (s_players.length > 0);
        upkeepNeeded = timeHasPassed && raffleIsOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "0x00");
    }

    // 1. [x] Get a random number from Chainlink VRF to pick winner
    // 2. [] Automatically called by Chainlink Automation and anyone else based on time
    // 3. [] Stop player from entering when picking the winner
    function performUpKeep(bytes calldata /** performData */) external {
        (bool upkeepNeeded, ) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        // check to see if enough time has passed
        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert Raffle_NotEnoughTimePassed();
        }
        s_raffleState = RaffleState.CALCULATING;
        // 1. Request the RNG
        // 2. Get the RNG
        uint256 requestId = i_vrfCoordinator.requestRandomWords( // i_vrfCoordinator is the VRF Coordinator contract address
            i_gasLane, // gas lane
            i_subscriptionId,
            REQUEST_COMFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS // number of RNG numbers
        );
        // For proving randomness ?
        emit RequestedRaffleWinner(requestId);
    }

    //CEI: Checks, Effects (Effect our own contract), Interactions (With other contracts)
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // 1. Checks

        // 2. Effects
        // Use the random number to pick a winner from s_players array
        // Use modual to get a number between 0 and s_players.length
        uint256 indexOfwinnner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfwinnner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        // Reset the player array
        s_players = new address payable[](0);
        // Reset the last timestamp
        s_lastTimeStamp = block.timestamp;
        // Emit the winner pick log
        emit WinnerPicked(recentWinner);

        // 3. Interaction
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }
    
    /** Getter Function */
    function getEntranceFee() external view returns(uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState) {
        return s_raffleState;
    }

    function getPlayers(uint256 indexOfPlayer) external view returns(address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns(address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns(uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns(uint256) {
        return s_lastTimeStamp;
    }
}