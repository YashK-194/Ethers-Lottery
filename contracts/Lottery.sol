//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

error Lottery__notEnoughEthEntered();
error Lottery__transferFailed();
error Lottery__lotteryIsNotOpen();
error Lottry__upkeepNotNeeded(
    uint256 currentBalance,
    uint256 numParticipants,
    uint256 lotteryState
);

contract Lottery is VRFConsumerBaseV2, AutomationCompatibleInterface {
    //-- Type Declaretions --
    enum lotteryState {
        OPEN,
        CALCULATING
    }
    //-- State Variables --
    uint256 private immutable i_entryFees;
    address payable[] private s_participantsList;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    //-- Lottery Variables --
    address private S_lastWinner;
    lotteryState private s_lotteryState;
    uint256 private s_lastBlockTimestamp;
    uint256 immutable i_interval;

    //-- Events --
    event lotteryEnter(address indexed participant);
    event requestedLotteryWinner(uint256 indexed requestId);
    event winnerPicked(address indexed winner);

    constructor(
        address vrfCoordinatorV2,
        uint256 entryFees,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_entryFees = entryFees;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lotteryState = lotteryState.OPEN;
        s_lastBlockTimestamp = block.timestamp;
        i_interval = interval;
    }

    function enterLottery() public payable {
        if (msg.value > i_entryFees) {
            revert Lottery__notEnoughEthEntered();
        }
        if (s_lotteryState != lotteryState.OPEN) {
            revert Lottery__lotteryIsNotOpen();
        }
        s_participantsList.push(payable(msg.sender));

        emit lotteryEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        override
        returns (bool upkeepNeeded, bytes memory /*performData*/)
    {
        bool isOpen = (lotteryState.OPEN == s_lotteryState);
        bool timePassed = ((block.timestamp - s_lastBlockTimestamp) >
            i_interval);
        bool hasPlayers = (s_participantsList.length > 0);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        //return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Lottry__upkeepNotNeeded(
                address(this).balance,
                s_participantsList.length,
                uint256(s_lotteryState)
            );
        }
        s_lotteryState = lotteryState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit requestedLotteryWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 winnerIndex = randomWords[0] % s_participantsList.length;
        address payable lastWinner = s_participantsList[winnerIndex];
        s_lotteryState = lotteryState.CALCULATING;
        S_lastWinner = lastWinner;
        s_participantsList = new address payable[](0);
        s_lastBlockTimestamp = block.timestamp;

        (bool success, ) = lastWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Lottery__transferFailed();
        }
        emit winnerPicked(lastWinner);
    }

    //-- View / Pure Functions --
    function getEntryFees() public view returns (uint256) {
        return i_entryFees;
    }

    function getParticipants(
        uint256 participantsListIndex
    ) public view returns (address) {
        return s_participantsList[participantsListIndex];
    }

    function getLastWinnerO() public view returns (address) {
        return S_lastWinner;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getNumberOfParticipants() public view returns (uint256) {
        return s_participantsList.length;
    }

    function getLatestTimestamp() public view returns (uint256){
        return s_lastBlockTimestamp;
    }

    function getRequestConfirmations() public pure returns (uint256){
        return REQUEST_CONFIRMATIONS;
    }
}
