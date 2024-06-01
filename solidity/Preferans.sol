// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Preferans {
    enum GameType { None, Spades, Diamonds, Hearts, Clubs, Misere, NoTrump }
    enum BiddingStatus { NotStarted, InProgress, Finished }
    enum PlayerStatus { NotIn, In, Out }

    struct Player {
        address addr;
        uint256 score;
        uint256 bula;
        uint256 leftSupa; 
        uint256 rightSupa; 
        PlayerStatus status;
        bool kontra;
        uint256 refeCount;
        uint256 tricksTaken; 
        uint256[] hand; 
    }

    struct Trick {
        uint256[3] cards;
        address[3] players;
        uint256 leadSuit;
    }

    struct GameCall {
        address player;
        GameType gameType;
    }

    GameCall[] public gameCalls;
    uint256[2] public stock;

    Player[3] public players;
    uint256 public currentPlayer;
    BiddingStatus public biddingStatus;
    GameType public currentGame;
    uint256 public highestBid;
    uint256 public currentTurn;
    uint256 public trickCount;
    address public dealer;
    address public currentLeader;
    uint256 public bidCount;
    uint256 public winningBid;
    address public winningBidder;
    Trick public currentTrick;
    mapping(address => bool) public hasBidded;
    bool public firstBidderChecked;
    uint256 public currentBidderIndex;
    uint256 public nextBidderIndex;
    bool public gameCalled;
    address public firstBidder;

    uint256 public kontraMultiplier;
    bool public kontraDeclared;

    uint256 public totalRefes; 

    uint256[] public deck; 
    mapping(uint256 => uint256) cardSuit; 
    mapping(uint256 => uint256) cardValue; 

    modifier onlyPlayer() {
        require(msg.sender == players[0].addr || msg.sender == players[1].addr || msg.sender == players[2].addr, "Not a player");
        _;
    }

    constructor(address[3] memory playerAddresses) {
        for (uint256 i = 0; i < 3; i++) {
            players[i] = Player({
                addr: playerAddresses[i],
                score: 100, 
                bula: 0,
                leftSupa: 0,
                rightSupa: 0,
                status: PlayerStatus.NotIn,
                kontra: false,
                refeCount: 0,
                tricksTaken: 0,
                hand: new uint256 ()
            });
        }
        currentPlayer = 0;
        biddingStatus = BiddingStatus.NotStarted;
        highestBid = 0;
        currentTurn = 0;
        trickCount = 0;
        kontraMultiplier = 1;
        kontraDeclared = false;
        dealer = playerAddresses[0]; 
        totalRefes = 0;

        initializeCardMappings();
    }

    function initializeCardMappings() internal {
        for (uint256 i = 0; i < 32; i++) {
            cardSuit[i] = i / 8; // 4 suits, 8 cards each
            cardValue[i] = i % 8; // Values from 0 to 7 within each suit
        }
    }

    function startBidding() external onlyPlayer {
        require(biddingStatus == BiddingStatus.NotStarted, "Bidding already started");
        biddingStatus = BiddingStatus.InProgress;
        highestBid = 0;
        bidCount = 0;
        currentBidderIndex = (currentTurn + 1) % 3;
        nextBidderIndex = (currentBidderIndex + 1) % 3;
        firstBidder = players[currentBidderIndex].addr;
        firstBidderChecked = false;
        gameCalled = false;
        gameCalls = new GameCall ;
        for (uint256 i = 0; i < 3; i++) {
            hasBidded[players[i].addr] = false;
        }
        shuffleAndDeal();
    }

    function shuffleAndDeal() internal {
        deck = new uint256 ;
        for (uint256 i = 0; i < 32; i++) {
            deck[i] = i;
        }
        shuffleDeck();

        uint256 cardIndex = 0;
        for (uint256 i = 0; i < 3; i++) {
            players ;
            for (uint256 j = 0; j < 10; j++) {
                players[i].hand[j] = deck[cardIndex++];
            }
        }
    }

    function shuffleDeck() internal {
        for (uint256 i = 0; i < deck.length; i++) {
            uint256 n = i + uint256(keccak256(abi.encodePacked(block.timestamp))) % (deck.length - i);
            uint256 temp = deck[n];
            deck[n] = deck[i];
            deck[i] = temp;
        }
    }

    function determineHighestGame() internal {
        GameType highestGame = GameType.None;
        address highestGameCaller = address(0);

        for (uint256 i = 0; i < gameCalls.length; i++) {
            if (gameCalls[i].gameType > highestGame) {
                highestGame = gameCalls[i].gameType;
                highestGameCaller = gameCalls[i].player;
            }
        }

        winningBidder = highestGameCaller;
        currentGame = highestGame;
    }

    function placeBid(uint256 bid, GameType gameType) external onlyPlayer {
        require(biddingStatus == BiddingStatus.InProgress, "Bidding not in progress");
        require(players[currentBidderIndex].addr == msg.sender, "Not your turn to bid");

        if (bid == 0) {  // fold
            players[currentBidderIndex].status = PlayerStatus.Out;
        } else if (gameType != GameType.None && !hasBidded[msg.sender]) {  // Igra
            gameCalls.push(GameCall({
                player: msg.sender,
                gameType: gameType
            }));
            hasBidded[msg.sender] = true;
            if (activePlayersCount() == 1 || atLeastOneGameCalledAndOthersBidded()) {
                endBidding();
            } else {
                advanceBidder();
            }
            return;
        } else {
            require(bid <= 7, "Bid cannot exceed 7");

            if (msg.sender == firstBidder) {
                require(bid >= highestBid, "First bidder can match or raise the highest bid");
                if (bid == 7) {
                    firstBidderChecked = true;
                }
            } else {
                require(bid > highestBid, "Other players must raise the bid");
            }

            highestBid = bid;
            winningBidder = msg.sender;
            players[currentBidderIndex].status = PlayerStatus.In;
            hasBidded[msg.sender] = true;
        }

        bidCount++;
        advanceBidder();

        if (activePlayersCount() == 1 || (highestBid == 7 && firstBidderChecked) || atLeastOneGameCalledAndOthersBidded()) {
            endBidding();
        }
    }

    function advanceBidder() internal {
        do {
            currentBidderIndex = nextBidderIndex;
            nextBidderIndex = (currentBidderIndex + 1) % 3;
        } while (players[currentBidderIndex].status == PlayerStatus.Out);
    }

    function activePlayersCount() internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].status != PlayerStatus.Out) {
                count++;
            }
        }
        return count;
    }

    function atLeastOneGameCalledAndOthersBidded() internal view returns (bool) {
        bool gameCalledByOnePlayer = gameCalls.length > 0;
        bool allOthersBidded = true;

        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr != gameCalls[0].player && !hasBidded[players[i].addr]) {
                allOthersBidded = false;
                break;
            }
        }

        return gameCalledByOnePlayer && allOthersBidded;
    }


    function endBidding() internal {
        require(biddingStatus == BiddingStatus.InProgress, "Bidding not in progress");
        biddingStatus = BiddingStatus.Finished;

        if (activePlayersCount() == 0) {
            recordRefe();
            resetGame();
        } else {
            if (gameCalls.length > 0) {
                determineHighestGame();
            } else {
                for (uint256 i = 0; i < 3; i++) {
                    if (players[i].addr == winningBidder) {
                        players[i].status = PlayerStatus.In;
                        break;
                    }
                }
            }

            if (!gameCalled) {
                for (uint256 i = 0; i < 3; i++) {
                    if (players[i].addr == winningBidder) {
                        players[i].hand.push(stock[0]);
                        players[i].hand.push(stock[1]);
                        break;
                    }
                }
            }

            stock[0] = 0;
            stock[1] = 0;
        }
    }

    function declareGame(GameType game) external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        require(msg.sender == winningBidder, "Only the winning bidder can declare the game");
        currentGame = game;
    }

    function followGame(bool follow) external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr == msg.sender) {
                players[i].status = follow ? PlayerStatus.In : PlayerStatus.NotIn;
            }
        }
    }

    function declareKontra() external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        kontraDeclared = true;
        kontraMultiplier *= 2;
    }

    function playCard(uint256 card) external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Game not started yet");
        require(currentTrick.players[currentTurn] == address(0), "Player has already played this trick");
        require(players[currentPlayer].addr == msg.sender, "Not your turn");

        require(isValidCardPlay(card), "Invalid card play");

        removeCardFromHand(msg.sender, card);

        currentTrick.cards[currentTurn] = card;
        currentTrick.players[currentTurn] = msg.sender;

        if (currentTurn == 0) {
            currentTrick.leadSuit = cardSuit[card];
        }

        currentTurn = (currentTurn + 1) % 3;

        if (currentTurn == 0) {
            resolveTrick();
        } else {
            nextTurn();
        }
    }

    function removeCardFromHand(address playerAddr, uint256 card) internal {
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr == playerAddr) {
                uint256 index = findCardIndex(players[i].hand, card);
                require(index < players[i].hand.length, "Card not found in hand");

                for (uint256 j = index; j < players[i].hand.length - 1; j++) {
                    players[i].hand[j] = players[i].hand[j + 1];
                }
                players[i].hand.pop();
                break;
            }
        }
    }

    function findCardIndex(uint256[] memory hand, uint256 card) internal pure returns (uint256) {
        for (uint256 i = 0; i < hand.length; i++) {
            if (hand[i] == card) {
                return i;
            }
        }
        return hand.length;
    }

    function isValidCardPlay(uint256 card) internal view returns (bool) {
        uint256 leadSuit = currentTrick.leadSuit;

        bool hasLeadSuit = false;
        for (uint256 i = 0; i < players[currentPlayer].hand.length; i++) {
            if (cardSuit[players[currentPlayer].hand[i]] == leadSuit) {
                hasLeadSuit = true;
                break;
            }
        }

        if (hasLeadSuit) {
            return cardSuit[card] == leadSuit;
        }

        bool hasTrump = false;
        for (uint256 i = 0; i < players[currentPlayer].hand.length; i++) {
            if (isTrump(cardSuit[players[currentPlayer].hand[i]])) {
                hasTrump = true;
                break;
            }
        }

        if (hasTrump && currentGame != GameType.Misere && currentGame != GameType.NoTrump) {
            return isTrump(cardSuit[card]);
        }

        return true;
    }

    function isTrump(uint256 suit) internal view returns (bool) {
        if (currentGame == GameType.Spades && suit == 0) {
            return true;
        } else if (currentGame == GameType.Diamonds && suit == 1) {
            return true;
        } else if (currentGame == GameType.Hearts && suit == 2) {
            return true;
        } else if (currentGame == GameType.Clubs && suit == 3) {
            return true;
        }
        return false;
    }

    function resolveTrick() internal {
        uint256 winningCardIndex = 0;
        for (uint256 i = 1; i < 3; i++) {
            if (beats(currentTrick.cards[i], currentTrick.cards[winningCardIndex])) {
                winningCardIndex = i;
            }
        }

        address winningPlayer = currentTrick.players[winningCardIndex];
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr == winningPlayer) {
                players[i].tricksTaken++;
                currentLeader = winningPlayer;
                break;
            }
        }

        currentTrick = Trick({
            cards: [uint256(0), uint256(0), uint256(0)],
            players: [address(0), address(0), address(0)],
            leadSuit: 0
        });

        if (++trickCount == 10) {
            calculateScores();
            resetGame();
        } else {
            currentTurn = (currentTurn + 1) % 3;
            nextTurn();
        }
    }

    function beats(uint256 card1, uint256 card2) internal view returns (bool) {
        if (cardSuit[card1] == cardSuit[card2]) {
            return cardValue[card1] > cardValue[card2];
        }
        if (isTrump(cardSuit[card1])) {
            return true;
        }
        if (isTrump(cardSuit[card2])) {
            return false;
        }
        return false;
    }

    function calculateScores() internal {
        uint256 baseScore;
        if (currentGame == GameType.Spades) {
            baseScore = 2;
        } else if (currentGame == GameType.Diamonds) {
            baseScore = 3;
        } else if (currentGame == GameType.Hearts) {
            baseScore = 4;
        } else if (currentGame == GameType.Clubs) {
            baseScore = 5;
        } else if (currentGame == GameType.Misere) {
            baseScore = 6;
        } else if (currentGame == GameType.NoTrump) {
            baseScore = 7;
        }

        for (uint256 i = 0; i < 3; i++) {
            if (players[i].status == PlayerStatus.In) {
                if (players[i].tricksTaken < baseScore) {
                    players[i].bula += baseScore * kontraMultiplier;
                } else {
                    players[i].bula -= baseScore * kontraMultiplier;
                }
            } else {
                uint256 leftPlayerIndex = (i + 2) % 3;
                uint256 rightPlayerIndex = (i + 1) % 3;
                players[i].leftSupa += players[i].tricksTaken * baseScore * kontraMultiplier;
                players[i].rightSupa += players[rightPlayerIndex].tricksTaken * baseScore * kontraMultiplier;
            }
        }
    }

    function getCurrentScores() external view returns (uint256[3] memory) {
        uint256[3] memory scores;
        for (uint256 i = 0; i < 3; i++) {
            scores[i] = players[i].score;
        }
        return scores;
    }

    function getCurrentSupa() external view returns (uint256[3][2] memory) {
        uint256[3][2] memory supas;
        for (uint256 i = 0; i < 3; i++) {
            supas[0][i] = players[i].leftSupa;
            supas[1][i] = players[i].rightSupa;
        }
        return supas;
    }

    function getCurrentBula() external view returns (uint256[3] memory) {
        uint256[3] memory bulas;
        for (uint256 i = 0; i < 3; i++) {
            bulas[i] = players[i].bula;
        }
        return bulas;
    }

    function recordRefe() internal {
        for (uint256 i = 0; i < 3; i++) {
            players[i].refeCount++;
        }
        totalRefes++;
    }

    function resetGame() internal {
        currentGame = GameType.None;
        biddingStatus = BiddingStatus.NotStarted;
        highestBid = 0;
        currentTurn = (currentTurn + 1) % 3;
        trickCount = 0;
        kontraMultiplier = 1;
        kontraDeclared = false;
        currentLeader = address(0);

        for (uint256 i = 0; i < 3; i++) {
            players[i].status = PlayerStatus.NotIn;
            players[i].tricksTaken = 0;
            players[i].hand = new uint256 (0);
        }
    }

    function nextTurn() internal {
        currentPlayer = (currentPlayer + 1) % 3;
    }
}
