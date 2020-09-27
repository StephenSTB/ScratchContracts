pragma solidity >=0.6.0;

import "../client/node_modules/@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

//import "./ScratchPriceConsumer.sol";

import "./ScratchToken.sol";

contract Scratch is VRFConsumerBase{

    // Variables for VRFConsumerBase
    bytes32 internal keyHash;
    uint256 internal fee;

    // Mapping of requestId to address
    mapping(bytes32 => address) private RequestIDtoAddress;

    mapping(address => uint) public AddressToRound;

    mapping(uint => PoolTotal) public PoolTotals;

    // Event to retreive the requestId of the BuyScratchCard function call.
    event RequestID(bytes32 requestId);

    event RequestFulfilled(uint randomness);

    event Dividend(address player, uint round, uint poolPercent, uint userPoolPercent, uint dividend);

    event NewRound(uint totalPool, uint tokenSupply, uint mintAmount, uint roundNumber);

    // Contract variable to get the LINK price.
    //ScratchPriceConsumer private Client;

    // Contract variable to handle the current crypto scratch card game round.
    ScratchCardRound private CardRound;

    // Contract variable to represent the Scratch Token
    ScratchToken private Token;

    uint public RoundNumber;

    uint public MintAmount;

    struct PoolTotal{
        uint liquidity;
        uint tokens;
    } 


     /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: Rinkeby
     * Chainlink VRF Coordinator address: 0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B
     * LINK token address:                0x01BE23585060835E02B77ef475b0Cc51aA1e0709
     * Key Hash: 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311
     */
     /**
     * Constructor inherits VRFConsumerBase
     *
     * Network: Ropsten
     * Chainlink VRF Coordinator address: 0x2e184F4120eFc6BF4943E3822FA0e5c3829e2fbD
     * LINK token address:                0x20fE562d797A42Dcb3399062AE9546cd06f63280
     * Key Hash: 0x757844cd6652a5805e9adb8203134e10a26ef59f62b864ed6a8c054733a1dcb0
     */

     /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: Kovan
     * Chainlink VRF Coordinator address: 0xf490AC64087d59381faF8Bf49Da299C073aAC152
     * LINK token address:                0xa36085F69e2889c224210F603D836748e7dC0088
     * Key Hash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
     */
    constructor(uint initialLink, ScratchToken scratchToken) public payable
        VRFConsumerBase(
            0xf490AC64087d59381faF8Bf49Da299C073aAC152, // VRF Coordinator
            0xa36085F69e2889c224210F603D836748e7dC0088  // LINK Token
        ) 
    {
        keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
        fee = 0.1 * 10 ** 18; // 0.1 LINK

        ///Client = new ScratchPriceConsumer();

        CardRound = new ScratchCardRound(initialLink);

        RoundNumber = 1;

        Token = scratchToken;

        MintAmount = 10 ** 18;
    }

    /**
     * Function to buy a card.
     */ 
    function buyScatchCard(uint userProvidedSeed) public{
        //uint cardPrice = (2000000000000000000 / RequestLinkPrice()) * 100000000;
        // Determine Card price
        uint cardPrice = CardRound.getCardPrice() + fee;
        
        // Test for correct payment
        require(LINK.allowance(msg.sender, address(this)) >= cardPrice , "Not enough Link can be sent to the contract.");

        // Pay for a card in link.
        if(LINK.transferFrom(msg.sender, address(this), cardPrice)){        
            // Set the senders round to the current round. (loss of previous round dividends occur if not claimed before calling this function)
            AddressToRound[msg.sender] = RoundNumber;

            // Determine scratch card random value and emit RequestID.
            emit RequestID(getScratchCard(userProvidedSeed, msg.sender));
        }
    }

    /**
     * Requests randomness from a user-provided seed
     */
    function getScratchCard(uint userProvidedSeed, address sender) private  returns(bytes32 requestId){
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK - fill contract with faucet");
        bytes32 requestID = requestRandomness(keyHash, fee, userProvidedSeed);
        RequestIDtoAddress[requestID] = sender;
        return requestID;
    }

    /*
    function requestRandom(uint userProvidedSeed) public {
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK - fill contract with faucet");
        emit RequestID(requestRandomness(keyHash, fee, userProvidedSeed));
    }*/

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(msg.sender == vrfCoordinator, "Fulillment only permitted by Coordinator");
        // Distribute possible winnings.
        uint prize = CardRound.claimPrize(RequestIDtoAddress[requestId], requestId, randomness);
        if(prize > 0){
            LINK.transfer(RequestIDtoAddress[requestId], prize);
        }
        Token.mint(RequestIDtoAddress[requestId], MintAmount);
        //delete(RequestIDtoAddress[requestId]);
    }

    /*
    * Function to start a new round of the game.
    */
    function newRound() public{
        require(CardRound.RoundOverThreshold() ,"The round is not over yet.");
        require(Token.balanceOf(msg.sender)  > 0, "You are not a participant.");

        PoolTotals[RoundNumber] = PoolTotal(LINK.balanceOf(address(this)), Token.getTotalSupply());

        CardRound = new ScratchCardRound(((PoolTotals[RoundNumber].liquidity / 10000) * 2896));

        MintAmount = (MintAmount / 100) * 80;

        RoundNumber++;

        emit NewRound(PoolTotals[RoundNumber-1].liquidity, PoolTotals[RoundNumber-1].tokens, MintAmount, RoundNumber);
    } 

    // function to pay the sender their dividends from previous rounds.
    function receiveDividend() public{
        require(AddressToRound[msg.sender] < RoundNumber && AddressToRound[msg.sender] > 0, "Invalid dividend participant.");
        uint i = AddressToRound[msg.sender];
        AddressToRound[msg.sender] = RoundNumber;
        for( i; i < RoundNumber; i++ ){
            uint poolPercent = ((PoolTotals[i].liquidity / 10000) * 6000);
            uint userPoolPercent = Token.balanceOf(msg.sender) / (PoolTotals[i].tokens / (10 ** 18));
            uint dividend = (userPoolPercent / (10 ** 9)) * (poolPercent / (10 ** 9));
            LINK.transfer(msg.sender, dividend);
            emit Dividend(msg.sender, i ,poolPercent, userPoolPercent, dividend);
        }
    }

    /*
    *
    *   Helper functions.
    */

    function getCardRound() public view returns(address CardRoundAddress){
        return address(CardRound);
    }

    function getPlayerRound(address player) public view returns(uint CardRoundNumber){
        return AddressToRound[player];
    }

    function getRound() public view returns(uint round){
        return RoundNumber;
    }

    function getToken() public view returns(address TokenAddress){
        return address(Token);
    }
    /*
    function transferToContract(uint value) public returns(bool success){
        return LINK.transferFrom(msg.sender, address(this), value);
    }*/

    function getContractAllowance() public view returns(uint256 allowance){
        return LINK.allowance(msg.sender, address(this));
    }

    /*
    function requestLinkPrice() public view returns(uint256 price){
        return uint(Client.getLatestPrice());
    }*/

    /*
    function transferLinkToClient(uint value) public returns(bool success){
        return LINK.transfer(address(Client), value);
    }*/

    function getLinkBalance(address owner) public view returns(uint balance)
    {
        return LINK.balanceOf(owner);
    }
}

// Contract to handle a round of cards.
contract ScratchCardRound {

    // Variable to hold the CryptoScratch contract address.
    address private _owner;

    // Variable to represnt the block that this card can expire.
    uint MaxBlock;

    // Event to emit a players prize.
    event PrizeClaim(address player, bytes32 requestId, uint number, uint prize); 

    // Array to the number of winning tickets left.
    uint[] internal winNumbers;

    // Array to hold the pays of the current round.
    uint[] internal winPays;

    // Array to hold win thresholds of prizes.
    uint[] private winThreshold = [197388, 232338, 244388, 248338, 249858, 249958, 249998, 250000];

    // Variable to hold the price of a card.
    uint private cardPrice;

    constructor(uint total) public{
        // Initialize owner
        _owner = msg.sender;

        MaxBlock = block.number + 576000;

        winNumbers.push(39600);
        winNumbers.push(12000);
        winNumbers.push(4000);
        winNumbers.push(1500);
        winNumbers.push(120);
        winNumbers.push(40);
        winNumbers.push(2);

        // Single unit of a win.
        cardPrice = total /  72400;

        winPays.push(cardPrice /2);
        winPays.push(cardPrice);
        winPays.push(2 * cardPrice);
        winPays.push(10 * cardPrice);
        winPays.push(30 * cardPrice);
        winPays.push(100 * cardPrice);
        winPays.push(5000 * cardPrice);

    }

    function claimPrize(address player, bytes32 requestId, uint randomNumber) public returns(uint prize){
        require(msg.sender == _owner, "Only Scratch contract can call this method.");
        // Initialize prizeNumber to be a number between 0 and 249,999.
        uint prizeNumber = randomNumber % 250000;

        // Losing condition
        if(prizeNumber < winThreshold[0]){
            emit PrizeClaim(player, requestId, prizeNumber, 0); // ClaimPrize event.
            return 0;
        }
        // Loop for wins.
        for(uint i = 0; i < 7; i++){
            if(prizeNumber >= winThreshold[i] && prizeNumber < winThreshold[i+1]){
                emit PrizeClaim(player, requestId, prizeNumber, winPays[i]); // ClaimPrize event.
                winNumbers[i]--;
                return winPays[i];
            }
        }
        return 0;
    }

    // Returns the price of a card.
    function getCardPrice() public view returns(uint price){
        return cardPrice;
    }

    // Returns the amount of unclaimed prizes and their pays.
    function unclaimedPrizes() public view returns (uint[] memory num, uint[] memory pays){
        return (winNumbers, winPays);
    }

    // Returns whether the round should be over.
    function RoundOverThreshold() public view returns (bool success){
        if(block.number >= MaxBlock){
            return true;
        }
        for(uint i = 6; i > 1; i--){
            if(winNumbers[i] > 0){
                return false;
            }
        }
        return true;
    }

    // SOLID OPTION 1.
    // ~ 250,000 plays to clear round ~ $500,000 given 2$ ticket.
    // ~ 1/3.45 prize distribution of $144,800  1: 4.365 prob per card of win.
    //
    //         tickets  base      thresh     base $    units
    // .5x   - 39600  -      1   197388    - $39,600   19800
    // 1x    - 12000  -      2   232338    - $24,000   12000
    // 2x    - 4000   -      4 - 244388    - $16,000   8000
    // 10x   - 1500   -     20 - 248338    - $30,000   15000
    // 30x   - 120    -     60 - 249858    -  $7,200   3600
    // 100x  - 40     -    200 - 249958    -  $8,000   4000 
    // 5000x - 2      - 10,000 - 249998    - $20,000   10000

    // SOLID OPTION 2
    // ~ 250,000 plays to clear round ~ $500,000 given 2$ ticket.
    // ~ 1/4 prize distribution of $125,000  1:8.462 prob per card of win.
    //
    //         tickets  base      thresh     remain    base $
    // 1x    - 24500
    // 2x    - 3500  -      4                         - $14,000  
    // 10x   - 1400  -     20                         - $28,000
    // 30x   - 100   -     60 - 249858                -  $6,000
    // 100x  - 40    -    200 - 249958                -  $8,000        
    // 5000x - 2     - 10,000 - 249998                - $20,000
    
}


