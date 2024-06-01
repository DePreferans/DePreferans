// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract Preferans {
    enum GameType { None, Spades, Diamonds, Hearts, Clubs, Misere, NoTrump }
    enum BiddingStatus { NotStarted, InProgress, Finished }
    enum PlayerStatus { NotIn, In, Out, Called }

    struct Player {
        address payable addr;
        uint256 score;
        int256 bula;
        uint256 leftSupa; 
        uint256 rightSupa; 
        PlayerStatus status;
        bool kontra;
        uint256 refeCount;
        uint256 tricksTaken; 
        uint256[] hand; 
        bool withdrawn;
    }
    //Ruka koja je odigrana u partiji
    struct Trick {
        uint256[3] cards;
        address[3] players;
        uint256 leadSuit;
    }
    // "igra" 
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

    //Uslov pred f-ju da mogu samo igraci da je pozivaju
    modifier onlyPlayer() {
        require(msg.sender == players[0].addr || msg.sender == players[1].addr || msg.sender == players[2].addr, "Not a player");
        _;
    }

    //Kreiranje pametnog ugovora i defisanje pocetnih parametara za igru
    constructor(address[3] memory playerAddresses, uint256 refeCount) payable {
        for (uint256 i = 0; i < 3; i++) {
            players[i] = Player({
                addr: payable (playerAddresses[i]),
                score: msg.value, 
                bula: int256(msg.value / 100),
                leftSupa: 0,
                rightSupa: 0,
                status: PlayerStatus.NotIn,
                kontra: false,
                refeCount: 0,
                tricksTaken: 0,
                hand: new uint256[] (0),
                withdrawn: false
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
        totalRefes = refeCount;

        initializeCardMappings();
    }

    //Generisanje karata
    function initializeCardMappings() internal {
        for (uint256 i = 0; i < 32; i++) {
            cardSuit[i] = i / 8; // 4 znaka, 8 karata za svaki znak
            cardValue[i] = i % 8; // Vrednosti od 0 - 7 za svaku kartu (od 7 - Ace)
        }
    }

    //Funkcija koja oznacava pocetak licitacije za igru
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
        delete gameCalls;
        for (uint256 i = 0; i < 3; i++) {
            hasBidded[players[i].addr] = false;
        }
        shuffleAndDeal();
    }

    //F-ja za generisanje spila i raspodelu karata ka igracima i u "kup"
    function shuffleAndDeal() internal {
        deck = new uint256[] (0) ;
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
        stock[0] = deck[30];
        stock[1] = deck[31];
    }

    //F-ja za mesanje karata
    function shuffleDeck() internal {
        for (uint256 i = 0; i < deck.length; i++) {
            uint256 n = i + uint256(keccak256(abi.encodePacked(block.timestamp))) % (deck.length - i);
            uint256 temp = deck[n];
            deck[n] = deck[i];
            deck[i] = temp;
        }
    }

    //F-ja za definisanje najjace "igre" 
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

    //Funkcija sa kojom se postavlja licitacija (dalje, broj ili "igra")
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
            if (atLeastOneGameCalledAndOthersBidded()) {
                endBidding();
            } else {
                advanceBidder();
            }
            return;
        } else { //Obicna licitacija
            require(bid > highestBid && bid == highestBid + 1, "Cant overbid");
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
        } else if (activePlayersCount() == 0 && bidCount == 3) {
            endBidding();
        }
    }

    //F-ja za oznacavanje ko sledeci treba da licitira
    function advanceBidder() internal {
        do {
            currentBidderIndex = nextBidderIndex;
            nextBidderIndex = (currentBidderIndex + 1) % 3;
        } while (players[currentBidderIndex].status == PlayerStatus.Out);
    }

    //F-ja koja vraca koliko trenutno ima aktivnih igraca
    function activePlayersCount() internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].status != PlayerStatus.Out) {
                count++;
            }
        }
        return count;
    }

    //F-ja koja vraca da li su svi glasali ako postoji barem jedna proglasena "igra"
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

    //F-ja koja oznacava kraj licitacija i vrsi prelaz na sledeci tok ruke
    function endBidding() internal {
        require(biddingStatus == BiddingStatus.InProgress, "Bidding not in progress");
        biddingStatus = BiddingStatus.Finished;

        if (activePlayersCount() == 0) { //Ako su svi rekli dalje
            recordRefe();
            resetGame();
        } else { //Ako je prozvana igra
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

            if (!gameCalled) { //Ako je normalna licitacija
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

    //F-ja sa kojom se proziva igra
    function declareGame(GameType game) external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        require(msg.sender == winningBidder, "Only the winning bidder can declare the game");
        currentGame = game;
        for(uint i = 0; i < 3; i++) { //Ako trenutni igrac ima refe
            if(players[i].addr == msg.sender && players[i].refeCount > 0){
                kontraMultiplier *= 2;
                players[i].refeCount--;
            }
        }
    }

    //F-ja koja izbacuje karte iz ruku igraca koji je pobedio u licitaciji
    function removeCardsAfterAddingStockCards(uint256 card1, uint256 card2) external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        require(msg.sender == winningBidder, "Only the winning bidder can declare the game");
        for (uint256 i = 0; i < 3; i++) {
            if(players[i].addr == winningBidder) {
                uint256 index1 = findCardIndex(players[i].hand, card1);
                require(index1 < players[i].hand.length, "Card not found in hand");

                uint256 index2 = findCardIndex(players[i].hand, card2);
                require(index2 < players[i].hand.length, "Card not found in hand");

                for (uint256 j = index1; j < players[i].hand.length - 1; j++) {
                    players[i].hand[j] = players[i].hand[j + 1];
                }
                players[i].hand.pop();
                for (uint256 k = index2; k < players[i].hand.length - 1; k++) {
                    players[i].hand[k] = players[i].hand[k + 1];
                }
                players[i].hand.pop();
                break;
            }
        }
    }

    //F-ja gde ostali igraci biraju da li ce da prate igru ili ne
    function followGame(bool follow) external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr == msg.sender) {
                players[i].status = follow ? PlayerStatus.In : PlayerStatus.NotIn;
            }
        }
    }

    //F-ja sa kojom se oznacava da igrac koji je odlucio da ne prati igru pude pozvan da igra
    function callToGame() external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr == msg.sender && players[i].status == PlayerStatus.In && players[i].addr != winningBidder) {
                uint256 leftPlayerIndex = (i + 2) % 3;
                uint256 rightPlayerIndex = (i + 1) % 3;
                if (players[leftPlayerIndex].status == PlayerStatus.NotIn){
                    players[leftPlayerIndex].status = PlayerStatus.Called;
                } else if (players[rightPlayerIndex].status == PlayerStatus.NotIn){
                    players[rightPlayerIndex].status = PlayerStatus.Called;
                }
            }
        }
    }

    //F-ja sa kojom igrac koji prati igru moze da pozove kontru
    function declareKontra() external onlyPlayer {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].addr == msg.sender && players[i].status == PlayerStatus.In && players[i].addr != winningBidder) {
                kontraDeclared = true;
                kontraMultiplier *= 2;
                uint256 leftPlayerIndex = (i + 2) % 3;
                uint256 rightPlayerIndex = (i + 1) % 3;
                if (players[leftPlayerIndex].status == PlayerStatus.NotIn){
                    players[leftPlayerIndex].status = PlayerStatus.Called;
                } else if (players[rightPlayerIndex].status == PlayerStatus.NotIn){
                    players[rightPlayerIndex].status = PlayerStatus.Called;
                }
            }
        }
    }

    //F-ja sa kojom igrac koji vodi igru ako je data kontra moze da pozove rekontru
    function declareReKontra() external onlyPlayer() {
        require(biddingStatus == BiddingStatus.Finished, "Bidding not finished");
        require(winningBidder == msg.sender, "Only Bidding winner can recounter");
        require(kontraDeclared == true, "Kontra wans-t declared");
        kontraMultiplier *= 2;
    }

    //F-ja sa kojom igrac odigrava kartu iz ruke
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

    //F-ja sa kojom se karta koja je odigrana izbacuje iz ruke
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

    //F-ja sa kojom se pronalazi karta koja zeli da se odigra u ruci
    function findCardIndex(uint256[] memory hand, uint256 card) internal pure returns (uint256) {
        for (uint256 i = 0; i < hand.length; i++) {
            if (hand[i] == card) {
                return i;
            }
        }
        return hand.length;
    }

    //F-ja koja proverava validnost odigrane karte
    function isValidCardPlay(uint256 card) internal view returns (bool) {
        uint256 leadSuit = currentTrick.leadSuit;

        bool hasLeadSuit = false;
        for (uint256 i = 0; i < players[currentPlayer].hand.length; i++) {
            if (cardSuit[players[currentPlayer].hand[i]] == leadSuit) {
                hasLeadSuit = true;
                break;
            }
        }

        if (hasLeadSuit) { //Ako ima vodecu kartu
            return cardSuit[card] == leadSuit;
        }

        bool hasTrump = false;
        for (uint256 i = 0; i < players[currentPlayer].hand.length; i++) {
            if (isTrump(cardSuit[players[currentPlayer].hand[i]])) { //Ako ima aduta
                hasTrump = true;
                break;
            }
        }

        if (hasTrump && currentGame != GameType.Misere && currentGame != GameType.NoTrump) { 
            return isTrump(cardSuit[card]);
        }

        return true;
    }

    //F-ja za proveru da li je znak adut
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

    //F-ja za razresavanje ruke (tri karte koje su odigrane na tabli)
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

    //F-ja za uporedjivanje jacine karata koje su na tabli
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

    //F-ja sa kojom se za svakog igraca na osnovu igre racunaju bule i supe
    function calculateScores() internal {
        uint256 baseScore;
        uint8 gameWasCalled = (gameCalled ? 2 : 0);
        uint8 playersThatPlayedCount = 0;
        if (currentGame == GameType.Spades) {
            baseScore = 4 + gameWasCalled;
        } else if (currentGame == GameType.Diamonds) {
            baseScore = 6 + gameWasCalled;
        } else if (currentGame == GameType.Hearts) {
            baseScore = 8 + gameWasCalled;
        } else if (currentGame == GameType.Clubs) {
            baseScore = 10 + gameWasCalled;
        } else if (currentGame == GameType.Misere) {
            baseScore = 12 + gameWasCalled;
        } else if (currentGame == GameType.NoTrump) {
            baseScore = 14 + gameWasCalled;
        }
        for (uint256 i = 0; i < 3; i++) {
            if (players[i].status == PlayerStatus.In || players[i].status == PlayerStatus.Called ) {
                playersThatPlayedCount++;
            }
        }
        for (uint256 i = 0; i < 3; i++) {
            uint256 leftPlayerIndex = (i + 2) % 3;
            uint256 rightPlayerIndex = (i + 1) % 3;
            if (players[i].status == PlayerStatus.In) {
                if(players[i].addr == winningBidder) {
                    if(currentGame == GameType.Misere && players[i].tricksTaken == 0) {
                        players[i].bula -= int256(baseScore * kontraMultiplier);
                    } else if (players[i].tricksTaken < 6) {
                        players[i].bula -= int256(baseScore * kontraMultiplier);
                    } else {
                        players[i].bula += int256(baseScore * kontraMultiplier);
                    }
                }else {
                    uint256 totalTricksTaken = players[i].tricksTaken + (
                        (players[leftPlayerIndex].status == PlayerStatus.Called || players[leftPlayerIndex].status == PlayerStatus.In) && players[leftPlayerIndex].addr != winningBidder ? 
                        players[leftPlayerIndex].tricksTaken : 
                        0) + 
                    (
                        (players[rightPlayerIndex].status == PlayerStatus.Called || players[rightPlayerIndex].status == PlayerStatus.In) && players[rightPlayerIndex].addr != winningBidder ? 
                        players[rightPlayerIndex].tricksTaken : 
                        0
                    );
                    if(playersThatPlayedCount > 2 && totalTricksTaken < 4) {
                        players[i].bula += int256(baseScore * kontraMultiplier);
                        if(players[leftPlayerIndex].addr == winningBidder) {
                            players[i].leftSupa += totalTricksTaken * baseScore * kontraMultiplier;
                        }
                        if(players[rightPlayerIndex].addr == winningBidder) {
                            players[i].rightSupa += totalTricksTaken * baseScore * kontraMultiplier;
                        }
                    } else if(players[i].tricksTaken < 2) {
                        players[i].bula += int256(baseScore * kontraMultiplier);
                        if(players[leftPlayerIndex].addr == winningBidder) {
                            players[i].leftSupa +=  players[i].tricksTaken * baseScore * kontraMultiplier;
                        }
                        if(players[rightPlayerIndex].addr == winningBidder) {
                            players[i].rightSupa += players[i].tricksTaken * baseScore * kontraMultiplier;
                        }
                    }
                    else {
                        if(players[leftPlayerIndex].addr == winningBidder) {
                            players[i].leftSupa +=  players[i].tricksTaken * baseScore * kontraMultiplier;
                        }
                        if(players[rightPlayerIndex].addr == winningBidder) {
                            players[i].rightSupa += players[i].tricksTaken * baseScore * kontraMultiplier;
                        }
                    }
                }
            } 
        }
    }

    //F-ja koja vraca trenutne krajnje rezultate igraca u partiji
    function getCurrentScores() external view returns (int256[3] memory) {
        int256[3] memory scores;
        for (uint256 i = 0; i < 3; i++) {
            uint256 leftPlayerIndex = (i + 2) % 3;
            uint256 rightPlayerIndex = (i + 1) % 3;
            scores[i] = 0 - (players[i].bula*10) - int256(players[i].leftSupa) - int256(players[i].rightSupa) + int256(players[leftPlayerIndex].rightSupa) + int256(players[rightPlayerIndex].leftSupa); 
        }
        return scores;
    }

    //F-ja za racunanje trenutnih supa za svakog igraca
    function getCurrentSupa() external view returns (uint256[3][2] memory) {
        uint256[3][2] memory supas;
        for (uint256 i = 0; i < 3; i++) {
            supas[0][i] = players[i].leftSupa;
            supas[1][i] = players[i].rightSupa;
        }
        return supas;
    }

    //F-ja za racunanje trenutnih bula za svakog igraca
    function getCurrentBula() external view returns (int256[3] memory) {
        int256[3] memory bulas;
        for (uint256 i = 0; i < 3; i++) {
            bulas[i] = players[i].bula;
        }
        return bulas;
    }

    //F-ja sa kojom se belezi refe
    function recordRefe() internal {
        if(totalRefes > 0){
            for (uint256 i = 0; i < 3; i++) {
                players[i].refeCount++;
            }
            totalRefes--;
        }
    }

    //F-ja sa kojom se resetuju parametri za novu ruku
    function resetGame() internal {
        currentGame = GameType.None;
        biddingStatus = BiddingStatus.NotStarted;
        highestBid = 0;
        currentTurn = (currentTurn + 1) % 3;
        trickCount = 0;
        kontraMultiplier = 1;
        kontraDeclared = false;
        currentLeader = address(0);
        delete gameCalls;
        winningBidder = address(0);
        winningBid = 0;

        for (uint256 i = 0; i < 3; i++) {
            players[i].status = PlayerStatus.NotIn;
            players[i].tricksTaken = 0;
            players[i].hand = new uint256[] (0);
        }
    }

    //F-ja sa kojom se obavestava ko sledeci igra za dato bacanje
    function nextTurn() internal {
        currentPlayer = (currentPlayer + 1) % 3;
    }

    //F-ja sa kojom se isplacuju svi igraci nakon partije
    function withdraw() external payable onlyPlayer() {
        int256 difference = 0;
        require(players[0].addr == msg.sender && players[0].withdrawn == false || 
                players[1].addr == msg.sender && players[1].withdrawn == false || 
                players[2].addr == msg.sender && players[2].withdrawn == false, 
                "You have already withdrew" );

        int256 totalBula = 0;
        for(uint i = 0; i < 3; i++) {
            totalBula += players[i].bula;
        }
        require(totalBula == 0, "Game is not over");

        int256[3] memory scores;
        for (uint256 i = 0; i < 3; i++) {
            uint256 leftPlayerIndex = (i + 2) % 3;
            uint256 rightPlayerIndex = (i + 1) % 3;
            scores[i] = 0 - (players[i].bula*10) - int256(players[i].leftSupa) - int256(players[i].rightSupa) + int256(players[leftPlayerIndex].rightSupa) + int256(players[rightPlayerIndex].leftSupa); 
        }
        
        for (uint256 i = 0; i < 3; i++) {
            uint256 leftPlayerIndex = (i + 2) % 3;
            uint256 rightPlayerIndex = (i + 1) % 3;
            if(players[i].addr == msg.sender){
                difference = scores[i] - scores[leftPlayerIndex];
                if(difference < 0){
                    (bool sent, bytes memory data) = players[i].addr.call{value: uint256(0 - difference)}("");
                    require(sent, "Failed to send wei");
                    players[i].withdrawn = true;
                }
                difference = scores[i] - scores[rightPlayerIndex];
                if(difference < 0){
                    (bool sent, bytes memory data) = players[i].addr.call{value: uint256(0 - difference)}("");
                    require(sent, "Failed to send wei");
                    players[i].withdrawn = true;
                }
            }
        }

    }
}
