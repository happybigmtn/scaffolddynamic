// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./FreeChips.sol";

contract BaccaratGame is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    FreeChips public freeChipsToken;
    uint256 public houseEdgeAccumulated;

    enum BetType { Player, Banker, Tie }

    struct Bet {
        address player;
        uint256 amount;
        BetType betType;
    }

    struct Game {
        uint8[3] playerHand;
        uint8[3] bankerHand;
        BetType winner;
        Bet[] bets;
        bool isCompleted;
    }

    struct Commitment {
        uint256 blockNumber;
        uint256 playerSeed;
    }

    mapping(bytes32 => Game) public games;
    mapping(address => uint256) public playerHouseEdgeBalances;
    mapping(address => Commitment) public commitments;

    event GameStarted(bytes32 indexed gameId);
    event BetPlaced(address indexed player, uint256 amount, BetType betType);
    event GameCompleted(bytes32 indexed gameId, BetType winner);
    event Payout(address indexed player, uint256 amount);
    event HouseEdgeRebateClaimed(address indexed player, uint256 amount);
    event GameCommitted(address indexed player, uint256 blockNumber);

    uint256 public constant PLAYER_HOUSE_EDGE = 124; // 1.24%
    uint256 public constant BANKER_HOUSE_EDGE = 106; // 1.06%
    uint256 public constant TIE_HOUSE_EDGE = 1436; // 14.36%
    uint256 private constant HOUSE_EDGE_DENOMINATOR = 10000;

    function initialize(address _freeChipsToken) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __Pausable_init();
        freeChipsToken = FreeChips(_freeChipsToken);
    }

    function commitToPlay(uint256 playerSeed) external whenNotPaused {
        require(commitments[msg.sender].blockNumber == 0, "Existing commitment found");
        commitments[msg.sender] = Commitment(block.number, playerSeed);
        emit GameCommitted(msg.sender, block.number);
    }

    function placeBet(BetType _betType, uint256 _amount) external nonReentrant whenNotPaused {
        // Check allowance before transferring
        uint256 allowance = freeChipsToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Insufficient FREE token allowance");

        // Attempt to transfer tokens
        bool transferSuccess = freeChipsToken.transferFrom(msg.sender, address(this), _amount);
        require(transferSuccess, "FREE transfer failed");

        bytes32 gameId = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        games[gameId].bets.push(Bet({player: msg.sender, amount: _amount, betType: _betType}));

        emit BetPlaced(msg.sender, _amount, _betType);
        emit GameStarted(gameId);

        playGame(gameId);
    }

    function playGame(bytes32 gameId) private {
        Game storage game = games[gameId];
        require(!game.isCompleted, "Game already completed");

        dealHands(gameId);
        determineBaccaratWinner(gameId);
        settleBets(gameId);

        game.isCompleted = true;
        emit GameCompleted(gameId, game.winner);

        delete games[gameId];
    }

    function dealHands(bytes32 gameId) private {
        Game storage game = games[gameId];
        uint256 randomValue = generateRandomNumber();

        game.playerHand[0] = uint8((randomValue % 13) + 1);
        game.playerHand[1] = uint8(((randomValue / 13) % 13) + 1);
        game.bankerHand[0] = uint8(((randomValue / 169) % 13) + 1);
        game.bankerHand[1] = uint8(((randomValue / 2197) % 13) + 1);

        uint8 playerScore = calculateHandValue(game.playerHand);
        uint8 bankerScore = calculateHandValue(game.bankerHand);

        if (playerScore < 8 && bankerScore < 8) {
            if (playerScore <= 5) {
                game.playerHand[2] = uint8(((randomValue / 28561) % 13) + 1);
                playerScore = calculateHandValue(game.playerHand);
            }
            if (shouldBankerDrawThirdCard(bankerScore, game.playerHand[2])) {
                game.bankerHand[2] = uint8(((randomValue / 371293) % 13) + 1);
            }
        }
    }

    function calculateHandValue(uint8[3] memory hand) private pure returns (uint8) {
        uint8 total = 0;
        for (uint8 i = 0; i < 3; i++) {
            if (hand[i] == 0) break;
            total += hand[i] > 9 ? 0 : hand[i];
        }
        return total % 10;
    }

    function shouldBankerDrawThirdCard(uint8 bankerScore, uint8 playerThirdCard) private pure returns (bool) {
        if (bankerScore >= 7) return false;
        if (bankerScore <= 2) return true;
        if (bankerScore == 3) return playerThirdCard != 8;
        if (bankerScore == 4) return playerThirdCard >= 2 && playerThirdCard <= 7;
        if (bankerScore == 5) return playerThirdCard >= 4 && playerThirdCard <= 7;
        if (bankerScore == 6) return playerThirdCard == 6 || playerThirdCard == 7;
        return false;
    }

    function determineBaccaratWinner(bytes32 gameId) private {
        Game storage game = games[gameId];
        uint8 playerScore = calculateHandValue(game.playerHand);
        uint8 bankerScore = calculateHandValue(game.bankerHand);

        if (playerScore > bankerScore) {
            game.winner = BetType.Player;
        } else if (bankerScore > playerScore) {
            game.winner = BetType.Banker;
        } else {
            game.winner = BetType.Tie;
        }
    }

    function settleBets(bytes32 gameId) private {
        Game storage game = games[gameId];
        for (uint256 i = 0; i < game.bets.length; i++) {
            Bet memory bet = game.bets[i];
            uint256 payout = 0;
            uint256 houseEdge;

            if (bet.betType == BetType.Player) {
                houseEdge = bet.amount * PLAYER_HOUSE_EDGE / HOUSE_EDGE_DENOMINATOR;
            } else if (bet.betType == BetType.Banker) {
                houseEdge = bet.amount * BANKER_HOUSE_EDGE / HOUSE_EDGE_DENOMINATOR;
            } else {
                houseEdge = bet.amount * TIE_HOUSE_EDGE / HOUSE_EDGE_DENOMINATOR;
            }

            if (bet.betType == game.winner) {
                payout = calculatePayout(bet.amount, bet.betType);
                freeChipsToken.transfer(bet.player, payout);
                emit Payout(bet.player, payout);
            } else {
                houseEdgeAccumulated += houseEdge;
            }
        }
    }

    function calculatePayout(uint256 betAmount, BetType _betType) private pure returns (uint256) {
        if (_betType == BetType.Tie) {
            return betAmount * 9; // 8:1 payout for Tie
        } else {
            return betAmount * 2; // 1:1 payout for Player or Banker
        }
    }

    function generateRandomNumber() internal returns (uint256) {
        Commitment memory commitment = commitments[msg.sender];
        require(commitment.blockNumber > 0, "No commitment found");
        require(block.number > commitment.blockNumber, "Wait for next block");
        require(block.number - commitment.blockNumber <= 256, "Commitment expired");

        uint256 randomValue = uint256(keccak256(abi.encodePacked(
            blockhash(commitment.blockNumber),
            commitment.playerSeed,
            msg.sender
        )));

        delete commitments[msg.sender];

        return randomValue;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}